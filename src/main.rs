mod cli;
mod compress;
mod dictionary;
mod error;
mod ffi;
mod io;

use clap::Parser;

use crate::cli::{Cli, Command};
use crate::error::Result;

fn main() {
  if let Err(err) = run() {
    eprintln!("error: {err}");
    std::process::exit(1);
  }
}

fn run() -> Result<()> {
  let cli = Cli::parse_from(normalized_args());
  match cli.command {
    Command::Dictionary(args) => dictionary::run(args),
    Command::Compress(args) => compress::run(args),
  }
}

fn normalized_args() -> Vec<String> {
  std::env::args()
    .map(|arg| match arg.as_str() {
      "-br" => "--raw-brotli".to_string(),
      "-zstd" => "--raw-zstd".to_string(),
      "-dcb" => "--delta-compression-brotli".to_string(),
      "-dcz" => "--delta-compression-zstd".to_string(),
      _ => arg,
    })
    .collect()
}
