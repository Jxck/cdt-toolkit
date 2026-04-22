# Baseline dictionary

`html.dict` is the reference output of `cdt dictionary` over
`tests/fixtures/html/*.html` with the parameters below. It acts as a
regression baseline: changes to the algorithm or the corpus must be matched by
an intentional regeneration of this file.

## Regeneration

```sh
cargo run --release -- dictionary \
  -o tests/fixtures/oracle/html.dict \
  -s 8192 \
  -l 12 \
  -b 4096 \
  -f 2 \
  tests/fixtures/html/*.html
```

Run from the package root so the input ordering matches what the test expects.
