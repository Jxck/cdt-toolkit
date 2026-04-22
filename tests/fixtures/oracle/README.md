# Oracle fixtures

`entries.dict` is a reference dictionary emitted by the separately maintained
reference implementation for parity testing. The Rust implementation must
produce a byte-identical output from the same inputs and options.

## Regeneration command

If the algorithm or fixture corpus changes, regenerate the oracle with the
reference implementation under an equivalent working tree and replace the file:

```sh
<reference-implementation> dictionary \
  -o tests/fixtures/oracle/entries.dict \
  -s 8192 \
  -l 12 \
  -b 4096 \
  -f 2 \
  tests/fixtures/entries/*.html
```

The invocation must run from this package's root so that the file list
canonicalizes to the same sort order the Rust test uses.
