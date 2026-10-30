use std::sync::atomic::{AtomicU64, Ordering};
use std::time::Duration;

use crate::error::Error;
use crate::ids::{FencingToken, HolderId, LeaseName};
use crate::memory::MemoryStore;
use crate::protocol::{Fence, require_auto_promote};
use crate::store::LeaseStore;

fn run(store: &impl LeaseStore) {
    let name = LeaseName::new("engine").unwrap();
    let a = HolderId::new("a").unwrap();
    let b = HolderId::new("b").unwrap();
    let ttl = Duration::from_millis(1_000);
    let now = AtomicU64::new(1_000);

    let first = store
        .acquire(&name, &a, ttl, now.load(Ordering::SeqCst))
        .unwrap();
    assert_eq!(first.token, FencingToken::FIRST);

    let contended = store
        .acquire(&name, &b, ttl, now.load(Ordering::SeqCst))
        .unwrap_err();
    assert!(matches!(contended, Error::Contended { .. }));

    let renewed = store
        .renew(&first, ttl, now.load(Ordering::SeqCst))
        .unwrap();
    assert_eq!(renewed.token, first.token);

    now.fetch_add(2_000, Ordering::SeqCst);
    let second = store
        .acquire(&name, &b, ttl, now.load(Ordering::SeqCst))
        .unwrap();
    assert!(second.token > first.token);

    let lost = store
        .renew(&first, ttl, now.load(Ordering::SeqCst))
        .unwrap_err();
    assert!(matches!(lost, Error::FenceLost { .. }));

    let mut fence = Fence::new(second.token);
    assert!(fence.admit(first.token).is_err());
    fence.admit(second.token).unwrap();

    store.release(&second).unwrap();
    assert_eq!(store.last_token(&name).unwrap(), second.token);
    let third = store
        .acquire(&name, &a, ttl, now.load(Ordering::SeqCst))
        .unwrap();
    assert!(third.token > second.token);

    assert!(require_auto_promote(2, false, false).is_err());
    assert!(require_auto_promote(2, true, false).is_ok());
    assert!(require_auto_promote(2, false, true).is_ok());
}

#[test]
fn memory_backend() {
    run(&MemoryStore::new());
}

#[cfg(unix)]
#[test]
fn file_backend() {
    use crate::file::FileStore;
    static NEXT: AtomicU64 = AtomicU64::new(0);
    let dir = std::env::temp_dir().join(format!(
        "fencing-lease-conform-{}-{}",
        std::process::id(),
        NEXT.fetch_add(1, Ordering::Relaxed)
    ));
    std::fs::create_dir_all(&dir).unwrap();
    run(&FileStore::new(&dir).unwrap());
    let _ = std::fs::remove_dir_all(&dir);
}

#[cfg(feature = "kubernetes")]
#[test]
fn kubernetes_memory_api_backend() {
    run(&crate::kubernetes::KubernetesStore::memory("ns"));
}

#[cfg(feature = "postgres")]
#[test]
#[ignore = "set FENCING_LEASE_POSTGRES_URL"]
fn postgres_backend() {
    let url = std::env::var("FENCING_LEASE_POSTGRES_URL").expect("FENCING_LEASE_POSTGRES_URL");
    run(&crate::postgres::PostgresStore::from_url(&url).unwrap());
}
