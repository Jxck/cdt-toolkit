use std::ffi::OsString;
use std::fs;
use std::path::{Path, PathBuf};

use crate::cli::CompressArgs;
use crate::dictionary::dictionary_hash;
use crate::error::{Error, Result};
use crate::ffi::{brotli, zstd};
use crate::io::{canonicalized_inputs, ensure_parent};

const BROTLI_QUALITY: u32 = 11;
const BROTLI_WINDOW: u32 = 24;
const ZSTD_LEVEL: i32 = 22;
const ZSTD_WINDOW_LOG: u32 = 23;
const DCB_MAGIC: [u8; 4] = [0xff, 0x44, 0x43, 0x42];
const DCZ_MAGIC: [u8; 8] = [0x5e, 0x2a, 0x4d, 0x18, 0x20, 0x00, 0x00, 0x00];

// Read a dictionary and emit the requested compressed payload variants for each input.
pub fn run(mut args: CompressArgs) -> Result<()> {
    // Default to the CDT wrapper formats so the command is useful without extra flags.
    if !args.raw_brotli && !args.raw_zstd && !args.dcb && !args.dcz {
        args.dcb = true;
        args.dcz = true;
    }

    let cwd = std::env::current_dir()?;
    let dict = fs::read(&args.dict)?;
    let dict_hash_bytes = dictionary_hash(&dict);

    fs::create_dir_all(&args.output_dir)?;
    let out_dir = fs::canonicalize(&args.output_dir)?;

    let inputs = canonicalized_inputs(&args.inputs, &cwd)?;
    for input in inputs {
        let data = fs::read(&input)?;
        // Preserve relative structure when possible, but fall back to the basename for external inputs.
        let rel = relative_to_anchor(&input, &cwd, &out_dir)?;
        let out_base = out_dir.join(rel);
        ensure_parent(&out_base)?;

        if args.verbose {
            eprintln!("compressing {}", input.display());
        }

        if args.raw_brotli {
            let output =
                brotli::compress_with_dictionary(&data, &dict, BROTLI_QUALITY, BROTLI_WINDOW)?;
            fs::write(with_suffix(&out_base, "br"), output)?;
        }
        if args.raw_zstd {
            let output = zstd::compress_with_prefix(&data, &dict, ZSTD_LEVEL, ZSTD_WINDOW_LOG)?;
            fs::write(with_suffix(&out_base, "zstd"), output)?;
        }
        if args.dcb {
            let raw =
                brotli::compress_with_dictionary(&data, &dict, BROTLI_QUALITY, BROTLI_WINDOW)?;
            let payload = wrap_payload(&DCB_MAGIC, &dict_hash_bytes, &raw);
            fs::write(with_suffix(&out_base, "dcb"), payload)?;
        }
        if args.dcz {
            let raw = zstd::compress_with_prefix(&data, &dict, ZSTD_LEVEL, ZSTD_WINDOW_LOG)?;
            let payload = wrap_payload(&DCZ_MAGIC, &dict_hash_bytes, &raw);
            fs::write(with_suffix(&out_base, "dcz"), payload)?;
        }
    }
    Ok(())
}

// Choose an output-relative path while avoiding duplicated roots and unusable absolute trees.
fn relative_to_anchor(path: &Path, cwd: &Path, out_dir: &Path) -> Result<PathBuf> {
    // Avoid re-embedding the output root if a caller points compress at files already under output_dir.
    if let Ok(relative) = path.strip_prefix(out_dir) {
        return Ok(relative.to_path_buf());
    }
    if let Ok(relative) = path.strip_prefix(cwd) {
        return Ok(relative.to_path_buf());
    }

    path.file_name()
        .map(PathBuf::from)
        .ok_or_else(|| Error::message(format!("input {} has no file name", path.display())))
}

// Wrap a raw compressed payload in the CDT wire prefix.
fn wrap_payload(magic: &[u8], hash: &[u8], payload: &[u8]) -> Vec<u8> {
    // CDT payloads are just magic + dictionary hash + raw codec bytes.
    let mut output = Vec::with_capacity(magic.len() + hash.len() + payload.len());
    output.extend_from_slice(magic);
    output.extend_from_slice(hash);
    output.extend_from_slice(payload);
    output
}

// Append a new extension without disturbing the original filename.
fn with_suffix(path: &Path, suffix: &str) -> PathBuf {
    let mut buf = OsString::from(path);
    buf.push(".");
    buf.push(suffix);
    PathBuf::from(buf)
}
