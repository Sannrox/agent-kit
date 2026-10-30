use std::time::Duration;

use crate::error::Error;
use crate::ids::{FencingToken, HolderId, Lease, LeaseName};

/// Named lease store. Implementations serialize each name independently.
pub trait LeaseStore {
    fn acquire(
        &self,
        name: &LeaseName,
        holder: &HolderId,
        ttl: Duration,
        now_ms: u64,
    ) -> Result<Lease, Error>;

    fn renew(&self, lease: &Lease, ttl: Duration, now_ms: u64) -> Result<Lease, Error>;

    fn release(&self, lease: &Lease) -> Result<(), Error>;

    fn held(&self, name: &LeaseName, now_ms: u64) -> Result<Option<Lease>, Error>;

    fn last_token(&self, name: &LeaseName) -> Result<FencingToken, Error>;
}

impl<T: LeaseStore + ?Sized> LeaseStore for std::sync::Arc<T> {
    fn acquire(
        &self,
        name: &LeaseName,
        holder: &HolderId,
        ttl: Duration,
        now_ms: u64,
    ) -> Result<Lease, Error> {
        (**self).acquire(name, holder, ttl, now_ms)
    }

    fn renew(&self, lease: &Lease, ttl: Duration, now_ms: u64) -> Result<Lease, Error> {
        (**self).renew(lease, ttl, now_ms)
    }

    fn release(&self, lease: &Lease) -> Result<(), Error> {
        (**self).release(lease)
    }

    fn held(&self, name: &LeaseName, now_ms: u64) -> Result<Option<Lease>, Error> {
        (**self).held(name, now_ms)
    }

    fn last_token(&self, name: &LeaseName) -> Result<FencingToken, Error> {
        (**self).last_token(name)
    }
}
