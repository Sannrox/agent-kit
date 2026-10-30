use std::collections::HashMap;
use std::sync::Mutex;
use std::time::Duration;

use serde::{Deserialize, Serialize};
use time::OffsetDateTime;
use time::format_description::well_known::Rfc3339;

use crate::error::Error;
use crate::ids::{FencingToken, HolderId, Lease, LeaseName};
use crate::protocol::{Op, Slot, apply, grant};
use crate::store::LeaseStore;

/// Coordination API used by [`KubernetesStore`].
pub(crate) trait CoordinationApi {
    fn get(&self, namespace: &str, name: &str) -> Result<Option<K8sLease>, Error>;
    fn create(&self, lease: &K8sLease) -> Result<K8sLease, Error>;
    fn update(&self, lease: &K8sLease) -> Result<K8sLease, Error>;
}

/// Kubernetes Lease document mapped onto a [`Slot`].
#[derive(Clone, Debug)]
pub(crate) struct K8sLease {
    pub(crate) namespace: String,
    pub(crate) name: String,
    pub(crate) resource_version: String,
    pub(crate) slot: Slot,
    pub(crate) ttl: Duration,
}

/// In-memory coordination API. Conformance uses this; no cluster required.
#[derive(Debug, Default)]
pub struct MemoryApi {
    objects: Mutex<HashMap<(String, String), K8sLease>>,
    versions: Mutex<u64>,
}

impl MemoryApi {
    pub fn new() -> Self {
        Self::default()
    }

    fn next_version(&self) -> String {
        let mut versions = self.versions.lock().unwrap_or_else(|e| e.into_inner());
        *versions += 1;
        versions.to_string()
    }
}

impl CoordinationApi for MemoryApi {
    fn get(&self, namespace: &str, name: &str) -> Result<Option<K8sLease>, Error> {
        let objects = self.objects.lock().unwrap_or_else(|e| e.into_inner());
        Ok(objects
            .get(&(namespace.to_string(), name.to_string()))
            .cloned())
    }

    fn create(&self, lease: &K8sLease) -> Result<K8sLease, Error> {
        let mut objects = self.objects.lock().unwrap_or_else(|e| e.into_inner());
        let key = (lease.namespace.clone(), lease.name.clone());
        if objects.contains_key(&key) {
            return Err(Error::unavailable("kubernetes lease already exists"));
        }
        let mut stored = lease.clone();
        stored.resource_version = self.next_version();
        objects.insert(key, stored.clone());
        Ok(stored)
    }

    fn update(&self, lease: &K8sLease) -> Result<K8sLease, Error> {
        let mut objects = self.objects.lock().unwrap_or_else(|e| e.into_inner());
        let key = (lease.namespace.clone(), lease.name.clone());
        match objects.get(&key) {
            Some(current) if current.resource_version == lease.resource_version => {}
            Some(_) => return Err(Error::unavailable("kubernetes resourceVersion conflict")),
            None => return Err(Error::unavailable("kubernetes lease missing")),
        }
        let mut stored = lease.clone();
        stored.resource_version = self.next_version();
        objects.insert(key, stored.clone());
        Ok(stored)
    }
}

/// Kubernetes Lease store. `MemoryApi` is for tests; [`HttpApi`] talks to a cluster.
pub struct KubernetesStore<A> {
    api: A,
    namespace: String,
}

impl KubernetesStore<MemoryApi> {
    pub fn memory(namespace: impl Into<String>) -> Self {
        Self {
            api: MemoryApi::new(),
            namespace: namespace.into(),
        }
    }
}

impl KubernetesStore<HttpApi> {
    pub fn http(
        namespace: impl Into<String>,
        base: impl Into<String>,
        token: impl Into<String>,
    ) -> Self {
        Self {
            api: HttpApi::new(base, token),
            namespace: namespace.into(),
        }
    }
}

fn mutate<A: CoordinationApi, T>(
    api: &A,
    namespace: &str,
    name: &LeaseName,
    ttl: Duration,
    f: impl Fn(&mut Slot) -> Result<T, Error>,
) -> Result<T, Error> {
    for _ in 0..2 {
        let current = api.get(namespace, name.as_str())?;
        let (mut slot, resource_version, existed) = match current {
            Some(lease) => (lease.slot, lease.resource_version, true),
            None => (Slot::empty(), String::new(), false),
        };
        let out = f(&mut slot)?;
        let next = K8sLease {
            namespace: namespace.to_string(),
            name: name.as_str().to_string(),
            resource_version,
            slot,
            ttl,
        };
        let wrote = if existed {
            api.update(&next)
        } else {
            api.create(&next)
        };
        match wrote {
            Ok(_) => return Ok(out),
            Err(Error::Unavailable(msg))
                if msg.contains("conflict") || msg.contains("already exists") =>
            {
                continue;
            }
            Err(err) => return Err(err),
        }
    }
    Err(Error::unavailable("kubernetes lease cas raced"))
}

fn held_of<A: CoordinationApi>(
    api: &A,
    namespace: &str,
    name: &LeaseName,
    now_ms: u64,
) -> Result<Option<Lease>, Error> {
    match api.get(namespace, name.as_str())? {
        Some(lease) => Ok(lease
            .slot
            .unexpired(now_ms)?
            .map(|view| view.into_lease(name.clone()))),
        None => Ok(None),
    }
}

fn last_token_of<A: CoordinationApi>(
    api: &A,
    namespace: &str,
    name: &LeaseName,
) -> Result<FencingToken, Error> {
    match api.get(namespace, name.as_str())? {
        Some(lease) => Ok(lease.slot.last_token()),
        None => Ok(FencingToken::ZERO),
    }
}

macro_rules! lease_store_for {
    ($api:ty) => {
        impl LeaseStore for KubernetesStore<$api> {
            fn acquire(
                &self,
                name: &LeaseName,
                holder: &HolderId,
                ttl: Duration,
                now_ms: u64,
            ) -> Result<Lease, Error> {
                mutate(&self.api, &self.namespace, name, ttl, |slot| {
                    grant(
                        slot,
                        name,
                        Op::Acquire {
                            holder,
                            ttl,
                            now_ms,
                        },
                    )
                })
            }

            fn renew(&self, lease: &Lease, ttl: Duration, now_ms: u64) -> Result<Lease, Error> {
                mutate(&self.api, &self.namespace, &lease.name, ttl, |slot| {
                    grant(
                        slot,
                        &lease.name,
                        Op::Renew {
                            holder: &lease.holder,
                            token: lease.token,
                            ttl,
                            now_ms,
                        },
                    )
                })
            }

            fn release(&self, lease: &Lease) -> Result<(), Error> {
                mutate(
                    &self.api,
                    &self.namespace,
                    &lease.name,
                    Duration::from_secs(1),
                    |slot| {
                        apply(
                            slot,
                            Op::Release {
                                holder: &lease.holder,
                                token: lease.token,
                            },
                        )?;
                        Ok(())
                    },
                )
            }

            fn held(&self, name: &LeaseName, now_ms: u64) -> Result<Option<Lease>, Error> {
                held_of(&self.api, &self.namespace, name, now_ms)
            }

            fn last_token(&self, name: &LeaseName) -> Result<FencingToken, Error> {
                last_token_of(&self.api, &self.namespace, name)
            }
        }
    };
}

lease_store_for!(MemoryApi);
lease_store_for!(HttpApi);

/// HTTP client for `coordination.k8s.io/v1` Lease objects.
pub struct HttpApi {
    base: String,
    token: String,
}

impl HttpApi {
    /// `base` is the API server root (scheme plus host). `token` is a bearer token.
    pub fn new(base: impl Into<String>, token: impl Into<String>) -> Self {
        Self {
            base: base.into().trim_end_matches('/').to_string(),
            token: token.into(),
        }
    }

    fn url(&self, namespace: &str, name: &str) -> String {
        format!(
            "{}/apis/coordination.k8s.io/v1/namespaces/{namespace}/leases/{name}",
            self.base
        )
    }

    fn collection(&self, namespace: &str) -> String {
        format!(
            "{}/apis/coordination.k8s.io/v1/namespaces/{namespace}/leases",
            self.base
        )
    }
}

impl CoordinationApi for HttpApi {
    fn get(&self, namespace: &str, name: &str) -> Result<Option<K8sLease>, Error> {
        let response = ureq::get(&self.url(namespace, name))
            .set("Authorization", &format!("Bearer {}", self.token))
            .set("Accept", "application/json")
            .call();
        match response {
            Ok(response) => {
                let object: LeaseObject = response.into_json().map_err(Error::unavailable)?;
                Ok(Some(object.into_lease()?))
            }
            Err(ureq::Error::Status(404, _)) => Ok(None),
            Err(err) => Err(Error::unavailable(err)),
        }
    }

    fn create(&self, lease: &K8sLease) -> Result<K8sLease, Error> {
        let object = LeaseObject::from_lease(lease)?;
        let response = ureq::post(&self.collection(&lease.namespace))
            .set("Authorization", &format!("Bearer {}", self.token))
            .set("Accept", "application/json")
            .set("Content-Type", "application/json")
            .send_json(object);
        match response {
            Ok(response) => {
                let object: LeaseObject = response.into_json().map_err(Error::unavailable)?;
                object.into_lease()
            }
            Err(ureq::Error::Status(409, _)) => {
                Err(Error::unavailable("kubernetes lease already exists"))
            }
            Err(err) => Err(Error::unavailable(err)),
        }
    }

    fn update(&self, lease: &K8sLease) -> Result<K8sLease, Error> {
        let object = LeaseObject::from_lease(lease)?;
        let response = ureq::put(&self.url(&lease.namespace, &lease.name))
            .set("Authorization", &format!("Bearer {}", self.token))
            .set("Accept", "application/json")
            .set("Content-Type", "application/json")
            .send_json(object);
        match response {
            Ok(response) => {
                let object: LeaseObject = response.into_json().map_err(Error::unavailable)?;
                object.into_lease()
            }
            Err(ureq::Error::Status(409, _)) => {
                Err(Error::unavailable("kubernetes resourceVersion conflict"))
            }
            Err(err) => Err(Error::unavailable(err)),
        }
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct LeaseObject {
    api_version: String,
    kind: String,
    metadata: ObjectMeta,
    spec: LeaseSpec,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ObjectMeta {
    name: String,
    namespace: String,
    #[serde(default)]
    resource_version: String,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct LeaseSpec {
    #[serde(skip_serializing_if = "Option::is_none")]
    holder_identity: Option<String>,
    #[serde(default)]
    lease_duration_seconds: i32,
    #[serde(skip_serializing_if = "Option::is_none")]
    acquire_time: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    renew_time: Option<String>,
    #[serde(default)]
    lease_transitions: i32,
}

impl LeaseObject {
    fn from_lease(lease: &K8sLease) -> Result<Self, Error> {
        let transitions = i32::try_from(lease.slot.last_token).map_err(Error::unavailable)?;
        let ttl_secs = i32::try_from(lease.ttl.as_secs().max(1)).map_err(Error::unavailable)?;
        let renew_time = lease
            .slot
            .expires_at_ms
            .map(|expires| {
                let start = expires.saturating_sub(lease.ttl.as_millis() as u64);
                unix_ms_to_rfc3339(start)
            })
            .transpose()?;
        Ok(Self {
            api_version: "coordination.k8s.io/v1".into(),
            kind: "Lease".into(),
            metadata: ObjectMeta {
                name: lease.name.clone(),
                namespace: lease.namespace.clone(),
                resource_version: lease.resource_version.clone(),
            },
            spec: LeaseSpec {
                holder_identity: lease.slot.holder.clone(),
                lease_duration_seconds: ttl_secs,
                acquire_time: renew_time.clone(),
                renew_time,
                lease_transitions: transitions,
            },
        })
    }

    fn into_lease(self) -> Result<K8sLease, Error> {
        let ttl = Duration::from_secs(self.spec.lease_duration_seconds.max(0) as u64);
        let last_token = u64::try_from(self.spec.lease_transitions.max(0)).unwrap_or(0);
        let expires_at_ms = match self.spec.renew_time.as_deref() {
            Some(text) => Some(rfc3339_to_unix_ms(text)?.saturating_add(ttl.as_millis() as u64)),
            None => None,
        };
        let holder = self.spec.holder_identity;
        let token = holder.as_ref().map(|_| last_token);
        Ok(K8sLease {
            namespace: self.metadata.namespace,
            name: self.metadata.name,
            resource_version: self.metadata.resource_version,
            slot: Slot {
                last_token,
                holder,
                token,
                expires_at_ms,
            },
            ttl,
        })
    }
}

fn unix_ms_to_rfc3339(ms: u64) -> Result<String, Error> {
    let secs = i64::try_from(ms / 1000).map_err(Error::unavailable)?;
    let nanos = i64::try_from(ms % 1000).map_err(Error::unavailable)? * 1_000_000;
    let ts = OffsetDateTime::from_unix_timestamp(secs).map_err(Error::unavailable)?
        + time::Duration::nanoseconds(nanos);
    ts.format(&Rfc3339).map_err(Error::unavailable)
}

fn rfc3339_to_unix_ms(text: &str) -> Result<u64, Error> {
    let ts = OffsetDateTime::parse(text, &Rfc3339).map_err(Error::unavailable)?;
    let ms = ts.unix_timestamp().saturating_mul(1000) + i64::from(ts.nanosecond() / 1_000_000);
    u64::try_from(ms.max(0)).map_err(Error::unavailable)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn lease_object_round_trip_keeps_token() {
        let lease = K8sLease {
            namespace: "ns".into(),
            name: "engine".into(),
            resource_version: "1".into(),
            slot: Slot {
                last_token: 4,
                holder: Some("a".into()),
                token: Some(4),
                expires_at_ms: Some(2_000),
            },
            ttl: Duration::from_secs(1),
        };
        let object = LeaseObject::from_lease(&lease).unwrap();
        let back = object.into_lease().unwrap();
        assert_eq!(back.slot.last_token, 4);
        assert_eq!(back.slot.holder.as_deref(), Some("a"));
    }
}
