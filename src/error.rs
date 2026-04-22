use std::fmt::{self, Display};
use std::io;

#[derive(Debug)]
pub enum Error {
  Io(io::Error),
  Message(String),
}

impl Error {
  pub fn message(message: impl Into<String>) -> Self {
    Self::Message(message.into())
  }
}

impl Display for Error {
  fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
    match self {
      Self::Io(err) => err.fmt(f),
      Self::Message(message) => f.write_str(message),
    }
  }
}

impl std::error::Error for Error {}

impl From<io::Error> for Error {
  fn from(value: io::Error) -> Self {
    Self::Io(value)
  }
}

pub type Result<T> = std::result::Result<T, Error>;

