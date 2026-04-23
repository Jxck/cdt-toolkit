---
name: dictionary-tuning
description: Tune `cdt dictionary` parameters against a representative local corpus and recommend a production command. Use when an AI agent needs to find or compare `--size`, `--slice-length`, `--block-length`, and `--min-frequency` for files a user wants to compress, especially when preparing a corpus-specific dictionary, evaluating Brotli/Zstandard net size, or turning ad hoc file globs into repeatable tuning runs.
---

# Dictionary Tuning

Tune on the same kind of files that will actually share one dictionary in
production. Optimize for net bytes, not raw payload size alone.

## Workflow

1. Prepare a representative corpus.
   - Use files that will share a dictionary at runtime.
   - Split very different asset classes into separate runs. Do not mix HTML,
     JS, and CSS unless that is really how the dictionary will be deployed.
   - Keep a small holdout set when possible so the final choice is not judged
     only on the training corpus.

2. Run a coarse sweep with the bundled script.
   - From the repo root, run
     `skills/dictionary-tuning/scripts/tune-corpus.sh --name <label> <inputs...>`.
   - Start with the default `quick` preset unless the user already knows the
     search space is too narrow.
   - The script writes `results.csv` and `summary.txt` under
     `work/dictionary-tuning/<label>/` by default.

3. Narrow the search around the best rows.
   - Re-run with smaller ranges near the top `combined_net` rows.
   - Favor the metric that matches the deployment format:
     `brotli_net`, `zstd_net`, or `combined_net` for wrapped `dcb` + `dcz`.

4. Validate the winner on holdout files.
   - Re-run the best 1-3 parameter sets on files not used for the first sweep.
   - Recommend a parameter set only if it still wins or is statistically close
     while being simpler or smaller.

5. Report the result as an exact `cdt dictionary` command.
   - Include the chosen `-s`, `-l`, `-b`, and `-f`.
   - State which metric was optimized and whether the result came from training
     only or also cleared a holdout check.

## Parameter Heuristics

- `--size`: Dictionary byte budget. Sweep this broadly first because it sets
  the overall ceiling on benefit and cost.
- `--slice-length`: Minimum fragment size used to score cross-file reuse.
  Lower values are more permissive; higher values demand longer exact matches.
- `--block-length`: Maximum contiguous region copied into the dictionary when a
  good area is selected. Raise it when useful shared structure tends to appear
  in larger chunks; lower it when surrounding bytes are mostly file-specific.
- `--min-frequency`: Minimum document frequency, not raw occurrence count.
  Never set it above the number of input files. On small or heterogeneous
  corpora, start low.

## Script Usage

Use the bundled script for repeatable sweeps:

```sh
skills/dictionary-tuning/scripts/tune-corpus.sh \
  --name blog-html \
  --sizes 4096,8192,16384 \
  --slice-lengths 8,12 \
  --block-lengths 1024,2048 \
  --min-frequencies 2,3 \
  path/to/files/*.html
```

The script:

- builds the local `cdt` binary from this repo
- generates a dictionary for each parameter tuple
- compresses the same corpus into `.br`, `.zstd`, `.dcb`, and `.dcz`
- records dictionary size, payload totals, and net totals in CSV
- prints the top rows sorted by `combined_net`

Set `CDT_BIN=/path/to/cdt` to use an already-built binary instead of building
from the repo.

## Deliverable

When finishing the task, provide:

- the winning parameter tuple
- the metric used to pick it
- the exact command to regenerate the dictionary
- any caveats about corpus size, heterogeneity, or missing holdout validation
