# cdt-toolkit Architecture

## Overview

`cdt-toolkit` is a CLI for Compression Dictionary Transport: it builds shared dictionaries and uses them to emit Brotli / Zstandard compressed payloads.

Two commands:

- `cdt dictionary`: build a raw shared dictionary
- `cdt compress`: use a shared dictionary to emit `.br` / `.zstd` / `.dcb` / `.dcz`

The core problem this project solves: extract substrings that appear across multiple files and, within a fixed dictionary-size budget, stably pick the bytes that compress well.

## Layout

Main modules:

- `src/main.rs`
  CLI entry point. Normalizes arguments and dispatches subcommands.
- `src/cli.rs`
  `clap`-based argument definitions.
- `src/dictionary/mod.rs`
  Dictionary generation. The core of this project.
- `src/compress/mod.rs`
  Compression using a built dictionary.
- `src/ffi/brotli.rs`
  Brotli raw-dictionary compression via FFI.
- `src/ffi/zstd.rs`
  Zstandard prefix-dictionary compression.
- `src/io.rs`
  Shared helpers: path canonicalization, parent-directory creation.
- `tests/dictionary_parity.rs`
  Verifies determinism and byte-for-byte match against the checked-in baseline dictionary.
- `tests/compress_parity.rs`
  Verifies compression output and output-path handling.

## Flow

### 1. Dictionary generation

`cdt dictionary` finds shared fragments across the input files and assembles the dictionary bytes from them.

Rough flow:

1. Canonicalize inputs, sort by relative path, dedupe.
2. Read each file and enumerate slices of length `slice_length`.
3. For each slice, count document frequency (how many files it appears in).
4. Keep only slices whose frequency is at least `min_frequency`.
5. For each file, find the window of length `block_length` containing the most unclaimed valid slices.
6. Trim the unused prefix/suffix of that block, subtract any overlap with already-selected ranges, and add it as a dictionary candidate.
7. Slices covered by the accepted block have their reuse value dropped to 0.
8. Repeat until the size budget is hit or no valid candidates remain.
9. Concatenate the selected ranges in file order / position order and emit the dictionary.

### 2. Compression

`cdt compress` reads the dictionary file and, for each input, produces:

- raw Brotli (`.br`)
- raw Zstandard (`.zstd`)
- CDT-framed Brotli (`.dcb`)
- CDT-framed Zstandard (`.dcz`)

`.dcb` and `.dcz` prepend CDT magic bytes and the dictionary SHA-256 to the raw compressed data.

## Dictionary generation

### The idea

This is not just "pick the most frequent fragments."

What matters:

- The fragment appears across multiple files.
- Fragments already covered by an accepted block aren't picked again.
- The dictionary-size budget is respected.
- The same inputs and parameters always yield the same dictionary.

To get there, `slice` and `block` are treated separately.

- `slice`: the unit of evaluation, length `slice_length`.
- `block`: the unit actually placed into the dictionary, length up to `block_length`.

Short `slice`s measure shareability; `block`s that contain many valuable `slice`s get accepted into the dictionary.

### Main data structures

#### `InputFile`

Per input file:

- `data`: the file content.
- `slice_ids`: at each byte position, the ID of the candidate slice at that position, if any.
- `selected_ranges`: byte ranges already committed to the dictionary from this file.

#### `active_scores`

The current value of each slice. Initialized to its document frequency.

- Slices that appear in more files are worth more.
- Once a block containing a slice is accepted, the slice's score drops to 0.

The table therefore holds residual value — shared fragments that haven't been covered yet.

#### `Candidate` and `MaxHeap`

Each file contributes at most one "currently best block candidate" to a max-heap.

A `Candidate` carries:

- `file_index`: which file.
- `score`: the block's value.
- `position`: where the block starts.
- `generation`: a rescoring version tag.

`generation` is how stale scores are discarded. Every accepted block mutates `active_scores`, which invalidates previously computed candidates.

### Step 1: Count document frequency

For each file, enumerate every slice of length `slice_length`. A slice occurring multiple times inside the same file still counts once for that file.

So this is counting "how many files contain it," not total occurrences.

That prevents a single noisy file from dominating the selection, and favors fragments that are genuinely shareable.

Slices below `min_frequency` are dropped.

### Step 2: Turn each file into a sequence of `slice_id`s

Assign a numeric ID to each surviving slice. For each file, record at each position whether the slice there matches one of the surviving IDs; if so, store the ID, otherwise `None`.

After this, block scoring only touches integers instead of raw bytes.

### Step 3: Find the best block per file

A block of length `block_length` covers `window_span = block_length - slice_length + 1` slice positions.

For each file we run a sliding window and score it as "the sum of `active_scores` for the unique valid slices inside the window."

Key points:

- A slice appearing multiple times in the same window is counted once.
- Because scores are document-frequency based, highly-shared slices dominate.
- Only the top-scoring window per file goes onto the heap.

At this stage each file offers its current best block — one entry into the heap.

### Step 4: Pick the single best block across files

Pop the top of the max-heap. That block is the globally best next pick.

The tie-break is fixed:

- higher `score`,
- lower `file_index`,
- lower `position`.

With this tie-break the selection order is deterministic for identical inputs.

### Step 5: Trim the block

The edges of a selected block may carry worthless bytes.

`trim_block` shaves positions at the left and right edge that are either:

- not a candidate slice, or
- have `active_scores == 0` (already covered).

What's left is the meaningful interior.

The returned right bound is `right + slice_length` so the full rightmost valid slice is included.

### Step 6: Subtract overlap with already-selected ranges

When multiple blocks come from the same file, naive appending can duplicate bytes in the dictionary.

`subtract_ranges` and `add_range` handle that.

- `selected_ranges` is kept sorted and merged.
- The new block has its overlap with existing ranges subtracted out.
- Only the non-overlapping leftovers are added.

Even when high-value blocks overlap, the dictionary stays non-redundant.

### Step 7: Zero out covered slices

After a block is accepted, every slice inside it is treated as "already represented by the dictionary" and its `active_scores` is set to 0.

This is the key step.

Without it, similar blocks containing the same shared fragment would keep being picked and the dictionary would fill up with redundancy. `cover_block` makes sure later picks prefer fragments that still aren't covered.

### Step 8: Rescore lazily and repeat

Every accepted block shifts `active_scores`, which shifts candidate scores.

Rather than rescoring every file every round, each heap entry carries the generation number it was scored at. A stale entry is only rescored when it reaches the top.

This keeps the implementation simple while avoiding needless work.

### Step 9: Assemble the dictionary bytes

Walk each `InputFile.selected_ranges` in file order and range order, concatenate the bytes, and cap at `args.size`.

Then compute the SHA-256 of the full dictionary.

- With `--output-dir`, the file is `<sha256>.dict`.
- Otherwise it is `--output` or the default `dictionary.dict`.

## Determinism

Determinism is enforced deliberately:

- Input paths are canonicalized and sorted.
- Duplicate inputs are removed.
- Surviving slices are sorted by byte content.
- Block-candidate tie-break is fixed.
- Selected ranges are merged and kept in a stable order.

Identical inputs with identical parameters always produce identical dictionaries. Tests assert this.

`tests/dictionary_parity.rs` also verifies that a freshly-generated dictionary matches the checked-in baseline (`tests/fixtures/oracle/html.dict`) byte for byte.

## Compression

Compared to dictionary generation, `compress` is straightforward:

1. Load the dictionary.
2. Compute its hash.
3. Read each input in turn.
4. Compress with Brotli / Zstd using the dictionary.
5. When emitting `.dcb` / `.dcz`, prepend the CDT magic bytes and dictionary hash.
6. Save under the original filename with the added extension.

Output paths preserve the relative path when the input lives under the current directory, and fall back to basename otherwise.

## Test strategy

The verification checklist is short:

- The CLI starts.
- Dictionary generation is deterministic.
- Dictionary bytes match the checked-in baseline.
- Compression output is produced as expected.
- Output-path resolution doesn't drift.

The dictionary-generation algorithm is complex, but two guarantees — "it produces the same result every time" and "it won't silently drift from the baseline" — are both covered by tests.
