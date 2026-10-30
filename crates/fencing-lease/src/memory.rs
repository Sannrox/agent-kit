use std::collections::HashMap;
use std::sync::Mutex;
use std::time::Duration;

use crate::error::Error;
use crate::ids::{FencingToken, HolderId, Lease, LeaseName};
use crate::protocol::{Op, Slot, apply, grant};
use crate::store::LeaseStore;

/// In-process store for tests and single-process hosts.
#[derive(Debug, Default)]
pub struct MemoryStore {
    slots: Mutex<HashMap<String, Slot>>,
}

impl MemoryStore {
    pub fn new() -> Self {
        Self::default()
    }

    fn with_slot<T>(
        &self,
        name: &LeaseName,
        f: impl FnOnce(&mut Slot) -> Result<T, Error>,
    ) -> Result<T, Error> {
        let mut slots = self.slots.lock().unwrap_or_else(|e| e.into_inner());
        let slot = slots
            .entry(name.as_str().to_string())
            .or_insert_with(Slot::empty);
        f(slot)
    }
}

impl LeaseStore for MemoryStore {
    fn acquire(
        &self,
        name: &LeaseName,
        holder: &HolderId,
        ttl: Duration,
        now_ms: u64,
    ) -> Result<Lease, Error> {
        self.with_slot(name, |slot| {
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
        self.with_slot(&lease.name, |slot| {
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
        self.with_slot(&lease.name, |slot| {
            apply(
                slot,
                Op::Release {
                    holder: &lease.holder,
                    token: lease.token,
                },
            )?;
            Ok(())
        })
    }

    fn held(&self, name: &LeaseName, now_ms: u64) -> Result<Option<Lease>, Error> {
        self.with_slot(name, |slot| {
            Ok(slot
                .unexpired(now_ms)?
                .map(|view| view.into_lease(name.clone())))
        })
    }

    fn last_token(&self, name: &LeaseName) -> Result<FencingToken, Error> {
        self.with_slot(name, |slot| Ok(slot.last_token()))
    }
}
