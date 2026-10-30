use std::fmt;

use crate::ids::{FencingToken, HolderId};

/// Failures a lease store or fence can return.
#[derive(Debug, thiserror::Error)]
pub enum Error {
    /// Another holder still owns an unexpired lease.
    #[error("lease contended by {holder} token {token}")]
    Contended {
        holder: HolderId,
        token: FencingToken,
    },
    /// The presented token is not the current generation.
    #[error("fence lost: held {held}, presented {presented}")]
    FenceLost {
        held: FencingToken,
        presented: FencingToken,
    },
    /// The backing store could not complete the operation.
    #[error("lease store unavailable: {0}")]
    Unavailable(String),
    /// Two or more members, no exclusive lock, no witness vote.
    #[error(
        "automatic promotion refused for {members} members without a witness or exclusive lock"
    )]
    AutoPromoteRefused { members: u32 },
    #[error("invalid lease name")]
    InvalidName,
    #[error("invalid holder id")]
    InvalidHolder,
}

impl Error {
    pub(crate) fn unavailable(err: impl fmt::Display) -> Self {
        Self::Unavailable(err.to_string())
    }
}

impl From<std::io::Error> for Error {
    fn from(err: std::io::Error) -> Self {
        Self::unavailable(err)
    }
}
