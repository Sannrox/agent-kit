use std::time::Duration;

use crate::error::Error;
use crate::ids::{FencingToken, HolderId, Lease, LeaseName};

/// Persisted lease slot. `last_token` survives release so tokens never recede.
#[derive(Clone, Debug, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub(crate) struct Slot {
    pub last_token: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub holder: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub token: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub expires_at_ms: Option<u64>,
}

impl Slot {
    pub fn empty() -> Self {
        Self {
            last_token: 0,
            holder: None,
            token: None,
            expires_at_ms: None,
        }
    }

    pub fn last_token(&self) -> FencingToken {
        FencingToken::from_raw(self.last_token)
    }

    pub fn unexpired(&self, now_ms: u64) -> Result<Option<LeaseView>, Error> {
        match (&self.holder, self.token, self.expires_at_ms) {
            (Some(holder), Some(token), Some(expires_at_ms)) if expires_at_ms > now_ms => {
                Ok(Some(LeaseView {
                    holder: HolderId::new(holder.clone())?,
                    token: FencingToken::from_raw(token),
                    expires_at_ms,
                }))
            }
            _ => Ok(None),
        }
    }

    pub fn held(&self) -> Result<Option<LeaseView>, Error> {
        match (&self.holder, self.token, self.expires_at_ms) {
            (Some(holder), Some(token), Some(expires_at_ms)) => Ok(Some(LeaseView {
                holder: HolderId::new(holder.clone())?,
                token: FencingToken::from_raw(token),
                expires_at_ms,
            })),
            _ => Ok(None),
        }
    }

    fn put(&mut self, holder: &HolderId, token: FencingToken, expires_at_ms: u64) {
        self.last_token = token.get();
        self.holder = Some(holder.as_str().to_string());
        self.token = Some(token.get());
        self.expires_at_ms = Some(expires_at_ms);
    }

    fn clear_hold(&mut self) {
        self.holder = None;
        self.token = None;
        self.expires_at_ms = None;
    }
}

#[derive(Clone, Debug)]
pub(crate) struct LeaseView {
    pub holder: HolderId,
    pub token: FencingToken,
    pub expires_at_ms: u64,
}

impl LeaseView {
    pub fn into_lease(self, name: LeaseName) -> Lease {
        Lease {
            name,
            holder: self.holder,
            token: self.token,
            expires_at_ms: self.expires_at_ms,
        }
    }
}

pub(crate) enum Op<'a> {
    Acquire {
        holder: &'a HolderId,
        ttl: Duration,
        now_ms: u64,
    },
    Renew {
        holder: &'a HolderId,
        token: FencingToken,
        ttl: Duration,
        now_ms: u64,
    },
    Release {
        holder: &'a HolderId,
        token: FencingToken,
    },
}

pub(crate) fn grant(slot: &mut Slot, name: &LeaseName, op: Op<'_>) -> Result<Lease, Error> {
    apply(slot, op)?
        .map(|view| view.into_lease(name.clone()))
        .ok_or_else(|| Error::unavailable("lease protocol produced no grant"))
}

pub(crate) fn apply(slot: &mut Slot, op: Op<'_>) -> Result<Option<LeaseView>, Error> {
    match op {
        Op::Acquire {
            holder,
            ttl,
            now_ms,
        } => match slot.unexpired(now_ms)? {
            Some(held) if held.holder == *holder => {
                let expires_at_ms = expiry(now_ms, ttl);
                slot.put(holder, held.token, expires_at_ms);
                Ok(Some(LeaseView {
                    holder: holder.clone(),
                    token: held.token,
                    expires_at_ms,
                }))
            }
            Some(held) => Err(Error::Contended {
                holder: held.holder,
                token: held.token,
            }),
            None => {
                let token = slot.last_token().next()?;
                let expires_at_ms = expiry(now_ms, ttl);
                slot.put(holder, token, expires_at_ms);
                Ok(Some(LeaseView {
                    holder: holder.clone(),
                    token,
                    expires_at_ms,
                }))
            }
        },
        Op::Renew {
            holder,
            token,
            ttl,
            now_ms,
        } => match slot.unexpired(now_ms)? {
            Some(held) if held.holder == *holder && held.token == token => {
                let expires_at_ms = expiry(now_ms, ttl);
                slot.put(holder, token, expires_at_ms);
                Ok(Some(LeaseView {
                    holder: holder.clone(),
                    token,
                    expires_at_ms,
                }))
            }
            Some(held) => Err(Error::FenceLost {
                held: held.token,
                presented: token,
            }),
            None => Err(Error::FenceLost {
                held: slot.last_token(),
                presented: token,
            }),
        },
        Op::Release { holder, token } => match slot.held()? {
            Some(held) if held.holder == *holder && held.token == token => {
                slot.clear_hold();
                Ok(None)
            }
            Some(held) => Err(Error::FenceLost {
                held: held.token,
                presented: token,
            }),
            None => Err(Error::FenceLost {
                held: slot.last_token(),
                presented: token,
            }),
        },
    }
}

fn expiry(now_ms: u64, ttl: Duration) -> u64 {
    now_ms.saturating_add(ttl.as_millis() as u64)
}

/// Refuses an effect whose token is older than `current`.
pub fn refuse_older(presented: FencingToken, current: FencingToken) -> Result<(), Error> {
    if presented < current {
        Err(Error::FenceLost {
            held: current,
            presented,
        })
    } else {
        Ok(())
    }
}

/// Highest token admitted so far. A paused holder cannot pass after takeover.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Fence {
    highest: FencingToken,
}

impl Fence {
    pub const fn empty() -> Self {
        Self {
            highest: FencingToken::ZERO,
        }
    }

    pub const fn new(highest: FencingToken) -> Self {
        Self { highest }
    }

    pub fn highest(&self) -> FencingToken {
        self.highest
    }

    pub fn admit(&mut self, token: FencingToken) -> Result<(), Error> {
        refuse_older(token, self.highest)?;
        self.highest = token;
        Ok(())
    }
}

/// Automatic promotion is allowed for one member, an exclusive lock across
/// members, or a witness vote. Two nodes without those are refused.
pub fn require_auto_promote(
    members: u32,
    exclusive_lock: bool,
    witness_vote: bool,
) -> Result<(), Error> {
    if members <= 1 || exclusive_lock || witness_vote {
        Ok(())
    } else {
        Err(Error::AutoPromoteRefused { members })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tokens_rise_on_takeover_and_hold_on_renew() {
        let mut slot = Slot::empty();
        let a = HolderId::new("a").unwrap();
        let b = HolderId::new("b").unwrap();
        let ttl = Duration::from_millis(10);
        let first = apply(
            &mut slot,
            Op::Acquire {
                holder: &a,
                ttl,
                now_ms: 0,
            },
        )
        .unwrap()
        .unwrap();
        assert_eq!(first.token, FencingToken::FIRST);
        apply(
            &mut slot,
            Op::Release {
                holder: &a,
                token: first.token,
            },
        )
        .unwrap();
        let second = apply(
            &mut slot,
            Op::Acquire {
                holder: &b,
                ttl,
                now_ms: 1,
            },
        )
        .unwrap()
        .unwrap();
        assert_eq!(second.token, FencingToken::from_raw(2));
    }

    #[test]
    fn paused_holder_renew_is_fence_loss() {
        let mut slot = Slot::empty();
        let a = HolderId::new("a").unwrap();
        let b = HolderId::new("b").unwrap();
        let ttl = Duration::from_millis(10);
        let first = apply(
            &mut slot,
            Op::Acquire {
                holder: &a,
                ttl,
                now_ms: 0,
            },
        )
        .unwrap()
        .unwrap();
        let second = apply(
            &mut slot,
            Op::Acquire {
                holder: &b,
                ttl,
                now_ms: 20,
            },
        )
        .unwrap()
        .unwrap();
        assert!(second.token > first.token);
        let err = apply(
            &mut slot,
            Op::Renew {
                holder: &a,
                token: first.token,
                ttl,
                now_ms: 21,
            },
        )
        .unwrap_err();
        assert!(matches!(err, Error::FenceLost { .. }));
    }

    #[test]
    fn fence_refuses_older_and_tracks_highest() {
        let mut fence = Fence::empty();
        fence.admit(FencingToken::from_raw(3)).unwrap();
        assert!(refuse_older(FencingToken::from_raw(2), fence.highest()).is_err());
        assert!(fence.admit(FencingToken::from_raw(2)).is_err());
        fence.admit(FencingToken::from_raw(3)).unwrap();
        fence.admit(FencingToken::from_raw(4)).unwrap();
        assert_eq!(fence.highest(), FencingToken::from_raw(4));
    }

    #[test]
    fn two_node_without_witness_or_lock_refuses() {
        assert!(require_auto_promote(2, false, false).is_err());
        assert!(require_auto_promote(2, true, false).is_ok());
        assert!(require_auto_promote(2, false, true).is_ok());
        assert!(require_auto_promote(1, false, false).is_ok());
        assert!(require_auto_promote(3, false, false).is_err());
    }
}
