use std::io;
use std::ptr;

use brotlic_sys::{
  BROTLI_TRUE, BrotliEncoderAttachPreparedDictionary, BrotliEncoderCompressStream,
  BrotliEncoderCreateInstance, BrotliEncoderDestroyInstance, BrotliEncoderDestroyPreparedDictionary,
  BrotliEncoderIsFinished,
  BrotliEncoderOperation_BROTLI_OPERATION_FINISH, BrotliEncoderOperation_BROTLI_OPERATION_PROCESS,
  BrotliEncoderParameter_BROTLI_PARAM_LGWIN, BrotliEncoderParameter_BROTLI_PARAM_QUALITY,
  BrotliEncoderPrepareDictionary, BrotliEncoderSetParameter,
  BrotliSharedDictionaryType_BROTLI_SHARED_DICTIONARY_RAW,
  BrotliEncoderPreparedDictionary,
};

pub fn compress_with_dictionary(input: &[u8], dictionary: &[u8], quality: u32, window: u32) -> io::Result<Vec<u8>> {
  unsafe {
    let state = BrotliEncoderCreateInstance(None, None, ptr::null_mut());
    if state.is_null() {
      return Err(io::Error::other("failed to allocate brotli encoder"));
    }

    let prepared: *mut BrotliEncoderPreparedDictionary = BrotliEncoderPrepareDictionary(
      BrotliSharedDictionaryType_BROTLI_SHARED_DICTIONARY_RAW,
      dictionary.len(),
      dictionary.as_ptr(),
      quality as i32,
      None,
      None,
      ptr::null_mut(),
    );
    if prepared.is_null() {
      BrotliEncoderDestroyInstance(state);
      return Err(io::Error::other("failed to prepare brotli dictionary"));
    }

    if BrotliEncoderSetParameter(state, BrotliEncoderParameter_BROTLI_PARAM_QUALITY, quality) != BROTLI_TRUE
      || BrotliEncoderSetParameter(state, BrotliEncoderParameter_BROTLI_PARAM_LGWIN, window) != BROTLI_TRUE
      || BrotliEncoderAttachPreparedDictionary(state, prepared) != BROTLI_TRUE
    {
      BrotliEncoderDestroyPreparedDictionary(prepared);
      BrotliEncoderDestroyInstance(state);
      return Err(io::Error::other("failed to configure brotli encoder"));
    }

    let mut output = Vec::new();
    let mut available_in = input.len();
    let mut next_in = input.as_ptr();
    let mut scratch = vec![0u8; 64 * 1024];

    loop {
      let mut available_out = scratch.len();
      let mut next_out = scratch.as_mut_ptr();
      let op = if available_in == 0 {
        BrotliEncoderOperation_BROTLI_OPERATION_FINISH
      } else {
        BrotliEncoderOperation_BROTLI_OPERATION_PROCESS
      };
      let ok = BrotliEncoderCompressStream(
        state,
        op,
        &mut available_in,
        &mut next_in,
        &mut available_out,
        &mut next_out,
        ptr::null_mut(),
      );
      if ok != BROTLI_TRUE {
        BrotliEncoderDestroyPreparedDictionary(prepared);
        BrotliEncoderDestroyInstance(state);
        return Err(io::Error::other("brotli compression failed"));
      }

      let written = scratch.len() - available_out;
      output.extend_from_slice(&scratch[..written]);

      if BrotliEncoderIsFinished(state) == BROTLI_TRUE {
        break;
      }
    }

    BrotliEncoderDestroyPreparedDictionary(prepared);
    BrotliEncoderDestroyInstance(state);
    Ok(output)
  }
}
