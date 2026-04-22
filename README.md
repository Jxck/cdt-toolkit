# cdt-toolkit

`cdt` is a command-line toolkit for building shared compression dictionaries
and producing dictionary-compressed payloads for Brotli and Zstandard-based
Compression Dictionary Transport workflows.

## Commands

- `cdt dictionary`: generate a raw shared dictionary
- `cdt compress`: compress files with a raw dictionary and emit `.br`, `.zstd`,
  `.dcb`, and `.dcz`

## Installation

### From source

```sh
cargo install --path .
```

This installs the `cdt` binary into `$CARGO_HOME/bin` (typically
`~/.cargo/bin`). Ensure that directory is on your `PATH`.

The package requires Rust 1.85 or newer.

### Prebuilt binary (release distribution)

Download a `.tar.gz` archive for your platform from the GitHub Releases page,
verify the accompanying `.sha256` checksum, and place the `cdt` binary on your
`PATH`.

## Development

```sh
cargo test
cargo run -- --help
./scripts/rehearse-release.sh
```

Integration tests verify:

- determinism (two runs produce identical bytes)
- byte parity with the Ruby reference implementation on the fixture corpus
  under `tests/fixtures/entries/`

`scripts/rehearse-release.sh` performs a local post-extract rehearsal: it copies
the package into a scratch git repository, runs `cargo test`, builds a release
binary, assembles the `.tar.gz` artifact, extracts it, and verifies the packaged
`cdt` binary starts successfully.

## License

MIT. See `LICENSE`. Third-party license notices are in `NOTICE` and
`THIRD_PARTY_LICENSES/`.
