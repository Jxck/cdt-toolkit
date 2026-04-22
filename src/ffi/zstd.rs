use std::io;

use zstd_safe::{CCtx, CParameter};

pub fn compress_with_prefix(input: &[u8], dictionary: &[u8], level: i32, window_log: u32) -> io::Result<Vec<u8>> {
  fn map_err(code: usize) -> io::Error {
    io::Error::other(format!("zstd error code: {code}"))
  }

  let mut context = CCtx::create();
  context
    .set_parameter(CParameter::CompressionLevel(level))
    .map_err(map_err)?;
  context
    .set_parameter(CParameter::WindowLog(window_log))
    .map_err(map_err)?;
  context.ref_prefix(dictionary).map_err(map_err)?;

  let bound = zstd_safe::compress_bound(input.len());
  let mut buffer = vec![0u8; bound];
  let written = context.compress2(&mut buffer[..], input).map_err(map_err)?;
  buffer.truncate(written);
  Ok(buffer)
}
