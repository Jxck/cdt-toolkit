use std::fs;
use std::path::PathBuf;
use std::process::Command;

#[test]
// Smoke-test that the compiled CLI starts and clap can render help text.
fn cli_help_works() {
    let output = Command::new(env!("CARGO_BIN_EXE_cdt"))
        .arg("--help")
        .output()
        .expect("failed to run cdt --help");
    assert!(output.status.success());
}

#[test]
// Ensure dictionary generation is byte-stable for identical inputs and parameters.
fn dictionary_generation_is_deterministic() {
    let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let dir = tempfile::tempdir().unwrap();
    let first = dir.path().join("first.dict");
    let second = dir.path().join("second.dict");
    let fixture_a = manifest_dir.join("tests/fixtures/html/rfc9842.html");
    let fixture_b = manifest_dir.join("tests/fixtures/html/rfc9111.html");

    for output in [&first, &second] {
        // Two identical runs over the same corpus should produce byte-identical dictionaries.
        let status = Command::new(env!("CARGO_BIN_EXE_cdt"))
            .args(["dictionary", "-o"])
            .arg(output)
            .args(["-s", "128", "-l", "8", "-b", "64", "-f", "1"])
            .arg(&fixture_a)
            .arg(&fixture_b)
            .status()
            .expect("failed to run cdt dictionary");
        assert!(status.success());
    }

    assert_eq!(fs::read(first).unwrap(), fs::read(second).unwrap());
}

#[test]
// Regression guard: dictionary output must match the checked-in baseline byte-for-byte.
fn dictionary_matches_baseline() {
    let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let fixtures_dir = manifest_dir.join("tests/fixtures/html");
    let baseline = manifest_dir.join("tests/fixtures/oracle/html.dict");

    // Keep fixture ordering explicit so the parity check stays stable across filesystems.
    let mut inputs: Vec<PathBuf> = fs::read_dir(&fixtures_dir)
        .expect("failed to read fixture dir")
        .filter_map(|entry| entry.ok())
        .map(|entry| entry.path())
        .filter(|path| path.extension().is_some_and(|ext| ext == "html"))
        .collect();
    inputs.sort();

    let dir = tempfile::tempdir().unwrap();
    let out_path = dir.path().join("candidate.dict");

    let mut command = Command::new(env!("CARGO_BIN_EXE_cdt"));
    command
        .current_dir(&manifest_dir)
        .args(["dictionary", "-o"])
        .arg(&out_path)
        .args(["-s", "8192", "-l", "12", "-b", "4096", "-f", "2"])
        .args(&inputs);
    let status = command.status().expect("failed to run cdt dictionary");
    assert!(status.success());

    let candidate = fs::read(&out_path).unwrap();
    let expected = fs::read(&baseline).expect(
        "baseline dictionary missing; see tests/fixtures/oracle/README.md for how to regenerate",
    );
    // Strict byte equality, not just a shape check.
    assert_eq!(
        candidate.len(),
        expected.len(),
        "dictionary byte length differs from baseline"
    );
    assert_eq!(candidate, expected, "dictionary body differs from baseline");
}
