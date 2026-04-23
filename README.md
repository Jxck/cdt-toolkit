# Compression Dictionary Transport Toolkit

`cdt` is a CLI for building shared compression dictionaries and dictionary-compressed payloads for Brotli and Zstandard, following [RFC 9842](https://www.rfc-editor.org/rfc/rfc9842).

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

Installs `cdt` into `$CARGO_HOME/bin` (usually `~/.cargo/bin`); make sure it is on your `PATH`. Requires Rust 1.85 or newer.

### Prebuilt binary

Grab a `.tar.gz` for your platform from GitHub Releases, verify the `.sha256`, and drop `cdt` onto your `PATH`.

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

## Options

### dictionary

Builds a raw shared dictionary from the input corpus. Inputs are canonicalized, sorted, and deduplicated before processing so repeated runs are deterministic.

```sh
$ cdt dictionary -h
Usage: cdt dictionary [OPTIONS] <INPUTS>...

Arguments:
  <INPUTS>...

Options:
  -o, --output <OUTPUT>
  -d, --output-dir <OUTPUT_DIR>
  -s, --size <SIZE>                    [default: 262144]
  -l, --slice-length <SLICE_LENGTH>    [default: 12]
  -b, --block-length <BLOCK_LENGTH>    [default: 4096]
  -f, --min-frequency <MIN_FREQUENCY>  [default: 3]
  -v, --verbose
  -h, --help                           Print help
```

- `-o, --output <PATH>`
  - write the dictionary to an explicit file path
- `-d, --output-dir <DIR>`
  - write the dictionary under `<DIR>/<sha256>.dict`; mutually exclusive with `--output`
- `-s, --size <BYTES>`
  - cap the emitted dictionary size; default `262144` (`256 KiB`)
- `-l, --slice-length <BYTES>`
  - byte length of the cross-file fragments used to score reuse; default `12`
- `-b, --block-length <BYTES>`
  - maximum byte length copied into the dictionary when a good region is selected; default `4096`
- `-f, --min-frequency <N>`
  - minimum document frequency for a slice to stay in play; default `3`
- `-v, --verbose`
  - print progress, selected block counts, output path, and the dictionary hash

`--size`, `--slice-length`, `--block-length`, and `--min-frequency` must all be positive, and `--block-length` must be greater than or equal to `--slice-length`.

### compress

Compresses each input with an existing dictionary and writes one or more output formats under an output directory. Relative input paths are preserved where possible.

```sh
$ cdt compress -h
Usage: cdt compress [OPTIONS] --dict <DICT> <INPUTS>...

Arguments:
  <INPUTS>...

Options:
  -d, --dict <DICT>
  -o, --output-dir <OUTPUT_DIR> [default: ./work/compressed]
  -b, --raw-brotli
  -z, --raw-zstd
      --delta-compression-brotli
      --delta-compression-zstd
  -v, --verbose
  -h, --help Print help
```

- `-d, --dict <PATH>`
  - path to the raw dictionary file to use; required
- `-o, --output-dir <DIR>`
  - destination directory for compressed files; default `./work/compressed`
- `-b, --raw-brotli`
  - emit raw Brotli payloads as `.br`
- `-z, --raw-zstd`
  - emit raw Zstandard payloads as `.zstd`
- `--delta-compression-brotli`
  - emit CDT-wrapped Brotli payloads as `.dcb`
- `--delta-compression-zstd`
  - emit CDT-wrapped Zstandard payloads as `.dcz`
- `-v, --verbose`
  - print each input as it is compressed

If no output-format flags are given, `cdt compress` defaults to the CDT wrapper formats and emits both `.dcb` and `.dcz`.

### Output Formats

- `.br`
  - raw Brotli payload compressed with the shared dictionary
- `.zstd`
  - raw Zstandard payload compressed with the shared dictionary
- `.dcb`
  - CDT-wrapped Brotli payload
- `.dcz`
  - CDT-wrapped Zstandard payload

## Agent Skill

For arbitrary local corpora, this repo also includes the agent skill [`dictionary-tuning`](./skills/dictionary-tuning/SKILL.md). Use it when you want an AI agent to tune `cdt dictionary` parameters for your own files, choose a dictionary size, and recommend a final command. It bundles [`tune-corpus.sh`](./skills/dictionary-tuning/scripts/tune-corpus.sh) for repeatable parameter sweeps over user-provided inputs.

## Development

```sh
cargo test
cargo run -- --help
./scripts/tune-fixtures.sh
./scripts/rehearse-release.sh
mise run publish
```

Integration tests cover:

- determinism (two runs produce identical bytes)
- regression against checked-in baseline dictionaries built from the HTML, JavaScript, and CSS corpora under `tests/fixtures/`

## Release Package

For a normal release:

1. Run one of:

- `mise run patch`
- `mise run minor`
- `mise run major`

2. Review the created version bump commit and tag.
3. Run `mise run publish`.

If you only want to verify the release archive locally, use:

```sh
./scripts/rehearse-release.sh
```

### Scripts

- `./scripts/bump-version.sh`
  - bump the package semver in `Cargo.toml`, commit it as `v<version>`, and create the matching git tag
- `./scripts/validate-dictionary-algorithm.sh`
  - run focused algorithm checks against small synthetic inputs to validate document frequency, trimming, overlap handling, size caps, and determinism
- `./scripts/tune-fixtures.sh`
  - sweep `cdt dictionary` parameters against the checked-in HTML, JS, and CSS fixture corpora and write CSV summaries under `work/tune-fixtures/`
- `./scripts/package-release.sh`
  - assemble a release tarball plus `.sha256` from an already-built release binary for a target triple
- `./scripts/rehearse-release.sh`
  - run the release flow in a scratch copy, including test, release build, packaging, extract, and packaged-binary smoke checks
- `./scripts/publish.sh`
  - run the full release workflow used by `mise run publish`, including test, dry-run publish, rehearsal, tag, push, and final publish

These scripts are also registered as `mise` tasks.

### Tuning

Use the checked-in fixture corpora to sweep dictionary parameters and compare net compressed size:

```sh
./scripts/tune-fixtures.sh
```

The script writes per-corpus CSV reports and a `summary.txt` under `work/tune-fixtures/`. Each row records the parameter tuple, dictionary size, raw Brotli / Zstandard totals, wrapped `dcb` / `dcz` totals, and net bytes including the dictionary.

## License

MIT. See `LICENSE`. Third-party notices are in `NOTICE` and `THIRD_PARTY_LICENSES/`.
