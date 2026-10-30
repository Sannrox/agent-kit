//! Named fencing leases for standalone engines.
//!
//! The lock store decides who may write. Engine data stays in the engine.
//! See `docs/decisions/0001-standalone-engine-ha.md` in this repository.

mod error;
#[cfg(unix)]
mod file;
mod ids;
#[cfg(feature = "kubernetes")]
mod kubernetes;
mod memory;
#[cfg(feature = "postgres")]
mod postgres;
mod protocol;
mod store;

pub use error::Error;
#[cfg(unix)]
pub use file::FileStore;
pub use ids::{FencingToken, HolderId, Lease, LeaseName, unix_now_ms};
#[cfg(feature = "kubernetes")]
pub use kubernetes::{HttpApi, KubernetesStore, MemoryApi};
pub use memory::MemoryStore;
#[cfg(feature = "postgres")]
pub use postgres::PostgresStore;
pub use protocol::{Fence, refuse_older, require_auto_promote};
pub use store::LeaseStore;

#[cfg(test)]
mod conformance;
