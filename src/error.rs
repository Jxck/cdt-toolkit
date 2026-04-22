use std::fmt::{self, Display};
use std::io;

#[derive(Debug)]
pub enum Error {
    // Preserve io::Error for callers that want OS-level failure details.
    Io(io::Error),
    // Use a lightweight string variant for domain validation failures.
    Message(String),
}

impl Error {
    // Build a domain error from a displayable message.
    pub fn message(message: impl Into<String>) -> Self {
        Self::Message(message.into())
    }
}

impl Display for Error {
    // Render both IO and domain errors through the same user-facing interface.
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Io(err) => err.fmt(f),
            Self::Message(message) => f.write_str(message),
        }
    }
}

impl std::error::Error for Error {}

impl From<io::Error> for Error {
    // Promote raw IO failures into the crate-wide error type.
    fn from(value: io::Error) -> Self {
        Self::Io(value)
    }
}

pub type Result<T> = std::result::Result<T, Error>;
