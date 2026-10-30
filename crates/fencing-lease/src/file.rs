use std::fs::{File, OpenOptions};
use std::io::{Read, Seek, SeekFrom, Write};
use std::os::unix::io::AsRawFd;
use std::path::PathBuf;
use std::time::Duration;

use crate::error::Error;
use crate::ids::{FencingToken, HolderId, Lease, LeaseName};
use crate::protocol::{Op, Slot, apply, grant};
use crate::store::LeaseStore;

/// One JSON file per lease name, exclusive-locked for each mutation.
///
/// Single node, no external dependency. Tokens persist in the file so a
/// restart cannot reissue a granted generation.
#[derive(Debug, Clone)]
pub struct FileStore {
    dir: PathBuf,
}

impl FileStore {
    pub fn new(dir: impl Into<PathBuf>) -> Result<Self, Error> {
        let dir = dir.into();
        std::fs::create_dir_all(&dir)?;
        Ok(Self { dir })
    }

    fn path(&self, name: &LeaseName) -> PathBuf {
        self.dir.join(format!("{}.lease", name.as_str()))
    }

    fn with_slot<T>(
        &self,
        name: &LeaseName,
        f: impl FnOnce(&mut Slot) -> Result<T, Error>,
    ) -> Result<T, Error> {
        let path = self.path(name);
        let mut file = OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .truncate(false)
            .open(&path)?;
        flock_ex(&file)?;
        let mut slot = read_slot(&mut file)?;
        let out = f(&mut slot)?;
        write_slot(&mut file, &slot)?;
        drop(file);
        File::open(&self.dir)?.sync_all()?;
        Ok(out)
    }
}

impl LeaseStore for FileStore {
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

fn flock_ex(file: &File) -> Result<(), Error> {
    // SAFETY: `file` stays open for this call; flock does not take ownership of the fd.
    let rc = unsafe { libc::flock(file.as_raw_fd(), libc::LOCK_EX) };
    if rc == 0 {
        Ok(())
    } else {
        Err(Error::from(std::io::Error::last_os_error()))
    }
}

fn read_slot(file: &mut File) -> Result<Slot, Error> {
    file.seek(SeekFrom::Start(0))?;
    let mut buf = String::new();
    file.read_to_string(&mut buf)?;
    let trimmed = buf.trim();
    if trimmed.is_empty() {
        return Ok(Slot::empty());
    }
    serde_json::from_str(trimmed).map_err(Error::unavailable)
}

fn write_slot(file: &mut File, slot: &Slot) -> Result<(), Error> {
    let bytes = serde_json::to_vec(slot).map_err(Error::unavailable)?;
    file.seek(SeekFrom::Start(0))?;
    file.write_all(&bytes)?;
    file.set_len(bytes.len() as u64)?;
    file.sync_all()?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::protocol::Fence;
    use std::sync::atomic::{AtomicU64, Ordering};

    fn unique_dir() -> PathBuf {
        static NEXT: AtomicU64 = AtomicU64::new(0);
        let dir = std::env::temp_dir().join(format!(
            "fencing-lease-file-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn restart_does_not_reissue_token() {
        let dir = unique_dir();
        let name = LeaseName::new("engine").unwrap();
        let a = HolderId::new("a").unwrap();
        let b = HolderId::new("b").unwrap();
        let ttl = Duration::from_millis(1000);
        {
            let store = FileStore::new(&dir).unwrap();
            let lease = store.acquire(&name, &a, ttl, 0).unwrap();
            assert_eq!(lease.token, FencingToken::FIRST);
            store.release(&lease).unwrap();
        }
        let store = FileStore::new(&dir).unwrap();
        let lease = store.acquire(&name, &b, ttl, 10).unwrap();
        assert_eq!(lease.token, FencingToken::from_raw(2));
        let mut fence = Fence::new(lease.token);
        assert!(fence.admit(FencingToken::FIRST).is_err());
        let _ = std::fs::remove_dir_all(&dir);
    }
}
