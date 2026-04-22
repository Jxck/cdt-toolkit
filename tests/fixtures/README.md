# Test fixtures

This directory contains the checked-in corpus used by dictionary regression
tests and the baseline dictionary generated from that corpus.

## Corpus

- `html/`: RFC HTML documents used as stable text-heavy fixture inputs.
- `js/`: checked-in JavaScript distributions sourced from upstream package
  tarballs.
- `css/`: checked-in CSS distributions sourced from upstream package tarballs.
- `oracle/html.dict`: the reference output of `cdt dictionary` over the HTML
  corpus.
- `oracle/js.dict`: the reference output of `cdt dictionary` over the
  JavaScript corpus.
- `oracle/css.dict`: the reference output of `cdt dictionary` over the CSS
  corpus.

### JavaScript fixtures

These files are redistributed verbatim so the corpus stays realistic and the
source, version, and license are explicit.

| File                       | Package     | Version | Source                                                       | License |
| -------------------------- | ----------- | ------- | ------------------------------------------------------------ | ------- |
| `js/vue.global.js`         | `vue`       | 3.5.33  | https://registry.npmjs.org/vue/-/vue-3.5.33.tgz             | MIT     |
| `js/react-dom.development.js` | `react-dom` | 19.2.5  | https://registry.npmjs.org/react-dom/-/react-dom-19.2.5.tgz | MIT     |
| `js/lodash.js`             | `lodash`    | 4.18.1  | https://registry.npmjs.org/lodash/-/lodash-4.18.1.tgz       | MIT     |

### JavaScript notes

- `js/vue.global.js` is the package's browser global build.
- `js/react-dom.development.js` is the unminified development build from the
  package `cjs/` directory.
- `js/lodash.js` is the package root unminified distribution file.

### CSS fixtures

These files are redistributed verbatim so the corpus stays realistic and the
source, version, and license are explicit.

| File                          | Package         | Version | Source                                                          | License |
| ----------------------------- | --------------- | ------- | --------------------------------------------------------------- | ------- |
| `css/bootstrap-reboot.css`    | `bootstrap`     | 5.3.8   | https://registry.npmjs.org/bootstrap/-/bootstrap-5.3.8.tgz      | MIT     |
| `css/tailwind-preflight.css`  | `tailwindcss`   | 4.2.4   | https://registry.npmjs.org/tailwindcss/-/tailwindcss-4.2.4.tgz  | MIT     |
| `css/normalize.css`           | `normalize.css` | 8.0.1   | https://registry.npmjs.org/normalize.css/-/normalize.css-8.0.1.tgz | MIT  |

### CSS notes

- `css/bootstrap-reboot.css` is Bootstrap's compiled reboot/base stylesheet.
- `css/tailwind-preflight.css` is Tailwind CSS's distributed `preflight.css`
  reset layer.
- `css/normalize.css` is the package root unminified distribution file.

## Baseline dictionaries

`oracle/html.dict` is the reference output of `cdt dictionary` over
`tests/fixtures/html/*.html`.

`oracle/js.dict` is the reference output of `cdt dictionary` over
`tests/fixtures/js/*.js`.

`oracle/css.dict` is the reference output of `cdt dictionary` over
`tests/fixtures/css/*.css`.

Changes to the algorithm or any corpus must be matched by an intentional
regeneration of the corresponding baseline.

## Regeneration

```sh
~/.cargo/bin/cargo run --release -- dictionary \
  -o tests/fixtures/oracle/html.dict \
  -s 8192 \
  -l 12 \
  -b 4096 \
  -f 2 \
  tests/fixtures/html/*.html

~/.cargo/bin/cargo run --release -- dictionary \
  -o tests/fixtures/oracle/js.dict \
  -s 8192 \
  -l 12 \
  -b 4096 \
  -f 2 \
  tests/fixtures/js/*.js

~/.cargo/bin/cargo run --release -- dictionary \
  -o tests/fixtures/oracle/css.dict \
  -s 8192 \
  -l 12 \
  -b 4096 \
  -f 2 \
  tests/fixtures/css/*.css
```

Run from the package root so the input ordering matches what the test expects.
