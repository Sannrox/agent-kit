use std::time::Duration;

use postgres::{NoTls, Transaction};

use crate::error::Error;
use crate::ids::{FencingToken, HolderId, Lease, LeaseName};
use crate::protocol::{Op, Slot, apply, grant};
use crate::store::LeaseStore;

const SCHEMA: &str = "
CREATE TABLE IF NOT EXISTS fencing_leases (
    name TEXT PRIMARY KEY,
    last_token BIGINT NOT NULL,
    holder TEXT,
    token BIGINT,
    expires_at_ms BIGINT
)
";

/// PostgreSQL backend. Each call opens a connection and takes `FOR UPDATE`
/// on the named row. Enable the `postgres` feature to compile this type.
pub struct PostgresStore {
    config: postgres::Config,
}

impl PostgresStore {
    pub fn from_url(url: &str) -> Result<Self, Error> {
        let config = url.parse().map_err(Error::unavailable)?;
        Ok(Self { config })
    }

    pub fn from_config(config: postgres::Config) -> Self {
        Self { config }
    }

    fn with_slot<T>(
        &self,
        name: &LeaseName,
        f: impl FnOnce(&mut Slot) -> Result<T, Error>,
    ) -> Result<T, Error> {
        let mut client = self.config.connect(NoTls).map_err(Error::unavailable)?;
        client.batch_execute(SCHEMA).map_err(Error::unavailable)?;
        let mut tx = client.transaction().map_err(Error::unavailable)?;
        let mut slot = load(&mut tx, name)?;
        let out = f(&mut slot)?;
        save(&mut tx, name, &slot)?;
        tx.commit().map_err(Error::unavailable)?;
        Ok(out)
    }
}

impl LeaseStore for PostgresStore {
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

fn load(tx: &mut Transaction<'_>, name: &LeaseName) -> Result<Slot, Error> {
    // Insert an empty row first so concurrent first acquires serialize on
    // FOR UPDATE instead of both seeing no row and both writing token 1.
    tx.execute(
        "INSERT INTO fencing_leases (name, last_token) VALUES ($1, 0)
         ON CONFLICT (name) DO NOTHING",
        &[&name.as_str()],
    )
    .map_err(Error::unavailable)?;
    let row = tx
        .query_one(
            "SELECT last_token, holder, token, expires_at_ms
             FROM fencing_leases WHERE name = $1 FOR UPDATE",
            &[&name.as_str()],
        )
        .map_err(Error::unavailable)?;
    let last_token: i64 = row.get(0);
    let holder: Option<String> = row.get(1);
    let token: Option<i64> = row.get(2);
    let expires_at_ms: Option<i64> = row.get(3);
    Ok(Slot {
        last_token: u64_from_sql(last_token)?,
        holder,
        token: token.map(u64_from_sql).transpose()?,
        expires_at_ms: expires_at_ms.map(u64_from_sql).transpose()?,
    })
}

fn save(tx: &mut Transaction<'_>, name: &LeaseName, slot: &Slot) -> Result<(), Error> {
    let last_token = i64_from_u64(slot.last_token)?;
    let token = slot.token.map(i64_from_u64).transpose()?;
    let expires_at_ms = slot.expires_at_ms.map(i64_from_u64).transpose()?;
    let updated = tx
        .execute(
            "UPDATE fencing_leases
             SET last_token = $2, holder = $3, token = $4, expires_at_ms = $5
             WHERE name = $1",
            &[
                &name.as_str(),
                &last_token,
                &slot.holder,
                &token,
                &expires_at_ms,
            ],
        )
        .map_err(Error::unavailable)?;
    if updated != 1 {
        return Err(Error::unavailable("fencing lease row missing after lock"));
    }
    Ok(())
}

fn u64_from_sql(value: i64) -> Result<u64, Error> {
    u64::try_from(value).map_err(Error::unavailable)
}

fn i64_from_u64(value: u64) -> Result<i64, Error> {
    i64::try_from(value).map_err(Error::unavailable)
}
