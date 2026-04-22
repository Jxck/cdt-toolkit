use std::fs;
use std::process::Command;

#[test]
fn dictionary_and_compress_emit_outputs() {
  let dir = tempfile::tempdir().unwrap();
  let source = dir.path().join("sample.html");
  fs::write(&source, "<html><body>hello hello hello</body></html>").unwrap();

  let output = Command::new(env!("CARGO_BIN_EXE_cdt"))
    .args(["dictionary", "-o"])
    .arg(dir.path().join("dictionary.dict"))
    .args(["-s", "16", "-l", "4", "-b", "4", "-f", "1"])
    .arg(&source)
    .output()
    .expect("failed to run cdt dictionary");
  assert!(output.status.success());

  let compress = Command::new(env!("CARGO_BIN_EXE_cdt"))
    .args(["compress", "--dict"])
    .arg(dir.path().join("dictionary.dict"))
    .args(["--output-dir"])
    .arg(dir.path())
    .args(["-dcb", "-dcz"])
    .arg(&source)
    .output()
    .expect("failed to run cdt compress");
  assert!(compress.status.success());

  assert!(dir.path().join("sample.html.dcb").exists());
  assert!(dir.path().join("sample.html.dcz").exists());
}

#[test]
fn compress_falls_back_to_basename_for_inputs_outside_cwd() {
  let dir = tempfile::tempdir().unwrap();
  let source_dir = tempfile::tempdir().unwrap();
  let source = source_dir.path().join("sample.html");
  fs::write(&source, "<html><body>hello hello hello</body></html>").unwrap();

  let output = Command::new(env!("CARGO_BIN_EXE_cdt"))
    .args(["dictionary", "-o"])
    .arg(dir.path().join("dictionary.dict"))
    .args(["-s", "16", "-l", "4", "-b", "4", "-f", "1"])
    .arg(&source)
    .output()
    .expect("failed to run cdt dictionary");
  assert!(output.status.success());

  let out_dir = dir.path().join("out");
  let compress = Command::new(env!("CARGO_BIN_EXE_cdt"))
    .args(["compress", "--dict"])
    .arg(dir.path().join("dictionary.dict"))
    .args(["--output-dir"])
    .arg(&out_dir)
    .args(["-dcb"])
    .arg(&source)
    .output()
    .expect("failed to run cdt compress");
  assert!(compress.status.success(), "{}", String::from_utf8_lossy(&compress.stderr));

  assert!(out_dir.join("sample.html.dcb").exists());
}
