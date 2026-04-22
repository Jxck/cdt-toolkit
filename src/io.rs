use std::fs;
use std::path::{Path, PathBuf};

use crate::error::{Error, Result};

pub fn relative_path(path: &Path, cwd: &Path) -> String {
  match path.strip_prefix(cwd) {
    Ok(relative) => relative.to_string_lossy().into_owned(),
    Err(_) => path.to_string_lossy().into_owned(),
  }
}

pub fn canonicalized_inputs(inputs: &[PathBuf], cwd: &Path) -> Result<Vec<PathBuf>> {
  let mut paths = Vec::with_capacity(inputs.len());
  for input in inputs {
    let path = fs::canonicalize(input)
      .map_err(|err| Error::message(format!("failed to canonicalize {}: {err}", input.display())))?;
    paths.push(path);
  }
  paths.sort_by_key(|path| relative_path(path, cwd));
  paths.dedup();
  Ok(paths)
}

pub fn ensure_parent(path: &Path) -> Result<()> {
  if let Some(parent) = path.parent() {
    fs::create_dir_all(parent)?;
  }
  Ok(())
}

