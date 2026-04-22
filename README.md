# Compression Dictionary Transport Toolkit

`cdt` is a CLI for building shared compression dictionaries and
dictionary-compressed payloads for Brotli and Zstandard, following
[RFC 9842](https://www.rfc-editor.org/rfc/rfc9842).

## Commands

- `cdt dictionary`: build a shared dictionary from inputs
- `cdt compress`: compress inputs into `.br` / `.zstd` / `.dcb` / `.dcz`

## Installation

### From crates.io

```sh
cargo install cdt-toolkit
```

Installs the `cdt` binary into `$CARGO_HOME/bin` (usually `~/.cargo/bin`).
Requires Rust 1.85 or newer.

### From source

```sh
cargo install --path .
```

Installs `cdt` into `$CARGO_HOME/bin` (usually `~/.cargo/bin`); make sure it
is on your `PATH`. Requires Rust 1.85 or newer.

### Prebuilt binary

Grab a `.tar.gz` for your platform from GitHub Releases, verify the `.sha256`,
and drop `cdt` onto your `PATH`.

## Quick Start

Build a shared dictionary from a corpus:

```sh
cdt dictionary \
  --output dictionary.dict \
  tests/fixtures/html/*.html
```

Compress files with that dictionary and emit CDT wrapper payloads:

```sh
cdt compress \
  --dict dictionary.dict \
  --output-dir ./work/compressed \
  tests/fixtures/html/*.html
```

If you also want raw codec payloads, pass `--raw-brotli` and/or `--raw-zstd`.

## Output Formats

- `.br`: raw Brotli payload compressed with the shared dictionary
- `.zstd`: raw Zstandard payload compressed with the shared dictionary
- `.dcb`: CDT-wrapped Brotli payload
- `.dcz`: CDT-wrapped Zstandard payload

## Development

```sh
cargo test
cargo run -- --help
./scripts/rehearse-release.sh
```

Integration tests cover:

- determinism (two runs produce identical bytes)
- regression against a checked-in baseline dictionary built from the RFC
  corpus under `tests/fixtures/html/`

`scripts/rehearse-release.sh` walks the release flow end-to-end in a scratch
repo — test, release build, tarball, extract, and a smoke check that the
packaged `cdt` starts.

## License

MIT. See `LICENSE`. Third-party notices are in `NOTICE` and
`THIRD_PARTY_LICENSES/`.
