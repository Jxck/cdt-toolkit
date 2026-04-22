use std::path::PathBuf;

use clap::{ArgAction, Parser, Subcommand};

#[derive(Debug, Parser)]
#[command(name = "cdt")]
#[command(about = "Compression Dictionary Transport toolkit")]
pub struct Cli {
  #[command(subcommand)]
  pub command: Command,
}

#[derive(Debug, Subcommand)]
pub enum Command {
  Dictionary(DictionaryArgs),
  Compress(CompressArgs),
}

#[derive(Debug, clap::Args)]
pub struct DictionaryArgs {
  #[arg(short = 'o', long = "output")]
  pub output: Option<PathBuf>,
  #[arg(short = 'd', long = "output-dir")]
  pub output_dir: Option<PathBuf>,
  #[arg(short = 's', long = "size", default_value_t = 256 * 1024)]
  pub size: usize,
  #[arg(short = 'l', long = "slice-length", default_value_t = 12)]
  pub slice_length: usize,
  #[arg(short = 'b', long = "block-length", default_value_t = 4096)]
  pub block_length: usize,
  #[arg(short = 'f', long = "min-frequency", default_value_t = 3)]
  pub min_frequency: usize,
  #[arg(short = 'v', long = "verbose", action = ArgAction::SetTrue)]
  pub verbose: bool,
  #[arg(required = true)]
  pub inputs: Vec<PathBuf>,
}

#[derive(Debug, clap::Args)]
pub struct CompressArgs {
  #[arg(short = 'd', long = "dict")]
  pub dict: PathBuf,
  #[arg(short = 'o', long = "output-dir", default_value = "./work/compressed")]
  pub output_dir: PathBuf,
  #[arg(long = "raw-brotli", short = 'b', action = ArgAction::SetTrue)]
  pub raw_brotli: bool,
  #[arg(long = "raw-zstd", short = 'z', action = ArgAction::SetTrue)]
  pub raw_zstd: bool,
  #[arg(long = "delta-compression-brotli", action = ArgAction::SetTrue)]
  pub dcb: bool,
  #[arg(long = "delta-compression-zstd", action = ArgAction::SetTrue)]
  pub dcz: bool,
  #[arg(short = 'v', long = "verbose", action = ArgAction::SetTrue)]
  pub verbose: bool,
  #[arg(required = true)]
  pub inputs: Vec<PathBuf>,
}

