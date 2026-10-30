use std::fmt;
use std::time::{SystemTime, UNIX_EPOCH};

use crate::error::Error;

/// A lease key. Letters, digits, `.`, `_`, `-`; 1..=200 characters.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct LeaseName(String);

impl LeaseName {
    pub fn new(name: impl Into<String>) -> Result<Self, Error> {
        let name = name.into();
        if name.is_empty()
            || name.len() > 200
            || name == "."
            || name == ".."
            || !name
                .bytes()
                .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'.' | b'_' | b'-'))
        {
            return Err(Error::InvalidName);
        }
        Ok(Self(name))
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl fmt::Display for LeaseName {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

/// Who holds a lease. One non-empty line, no control characters, 1..=200.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct HolderId(String);

impl HolderId {
    pub fn new(id: impl Into<String>) -> Result<Self, Error> {
        let id = id.into();
        if id.is_empty()
            || id.len() > 200
            || id.chars().any(|c| c.is_control() || c == '\n' || c == '\r')
        {
            return Err(Error::InvalidHolder);
        }
        Ok(Self(id))
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl fmt::Display for HolderId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

/// Monotonic generation of a named lease. Zero means none has been granted.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct FencingToken(u64);

impl FencingToken {
    pub const ZERO: Self = Self(0);
    pub const FIRST: Self = Self(1);

    pub const fn from_raw(raw: u64) -> Self {
        Self(raw)
    }

    pub const fn get(self) -> u64 {
        self.0
    }

    pub(crate) fn next(self) -> Result<Self, Error> {
        self.0
            .checked_add(1)
            .map(Self)
            .ok_or_else(|| Error::unavailable("fencing token overflow"))
    }
}

impl fmt::Display for FencingToken {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.0)
    }
}

/// One grant of a named lease.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Lease {
    pub name: LeaseName,
    pub holder: HolderId,
    pub token: FencingToken,
    pub expires_at_ms: u64,
}

impl Lease {
    pub fn expired(&self, now_ms: u64) -> bool {
        self.expires_at_ms <= now_ms
    }
}

/// Wall-clock milliseconds since the Unix epoch.
pub fn unix_now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|elapsed| elapsed.as_millis() as u64)
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn lease_name_rejects_path_and_empty() {
        assert!(LeaseName::new("").is_err());
        assert!(LeaseName::new("..").is_err());
        assert!(LeaseName::new("a/b").is_err());
        assert!(LeaseName::new("ok.lease-1").is_ok());
    }

    #[test]
    fn holder_rejects_newlines() {
        assert!(HolderId::new("a\nb").is_err());
        assert!(HolderId::new("coord-1").is_ok());
    }
}
