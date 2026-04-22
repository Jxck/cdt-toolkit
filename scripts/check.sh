#!/usr/bin/env zsh

set -euo pipefail
setopt null_glob

SCRIPT_DIR=${0:A:h}
ROOT=${SCRIPT_DIR:h}
WORK_DIR=${ROOT}/work/check
GENERATOR=${ROOT}/target/debug/cdt

mkdir -p "${WORK_DIR}"
rm -rf "${WORK_DIR}"/*

fail() {
  print -u2 -- "error: $1"
  exit 1
}

expect_equal_file() {
  local actual_path="$1"
  local expected="$2"
  local message="$3"
  local actual
  actual=$(printf '%s' "$(<"${actual_path}")")
  [[ "${actual}" == "${expected}" ]] || fail "${message}: expected '${expected}', got '${actual}'"
}

expect_equal_files() {
  local a="$1"
  local b="$2"
  local message="$3"
  cmp -s "${a}" "${b}" || fail "${message}"
}

run_generator() {
  "${GENERATOR}" dictionary "$@"
}

mkdir -p "${WORK_DIR}/docfreq"
printf 'aaaaaaaaaaaa\n' > "${WORK_DIR}/docfreq/a.txt"
printf 'WXYZbbbbbbbb\n' > "${WORK_DIR}/docfreq/b.txt"
printf 'WXYZcccccccc\n' > "${WORK_DIR}/docfreq/c.txt"
run_generator -o "${WORK_DIR}/docfreq/out.dict" -s 4 -l 4 -b 4 -f 2 "${WORK_DIR}/docfreq/"*.txt >/dev/null
expect_equal_file "${WORK_DIR}/docfreq/out.dict" "WXYZ" "document frequency should prefer shared block"

# slices must not cross file boundaries
mkdir -p "${WORK_DIR}/boundary"
printf 'abcde\n' > "${WORK_DIR}/boundary/a.txt"
printf 'fgij\n' > "${WORK_DIR}/boundary/b.txt"
printf 'defg\n' > "${WORK_DIR}/boundary/c.txt"
if run_generator \
  -o "${WORK_DIR}/boundary/out.dict" \
  -s 4 \
  -l 4 \
  -b 4 \
  -f 2 \
  "${WORK_DIR}/boundary/"*.txt >/dev/null 2>&1; then
  fail "generator should not find boundary-crossing slices"
fi

# trim should drop low-value head and tail
mkdir -p "${WORK_DIR}/trim"
printf 'xxxxCOMMONyyyy\n' > "${WORK_DIR}/trim/a.txt"
printf 'zzzzCOMMONwwww\n' > "${WORK_DIR}/trim/b.txt"
run_generator \
  -o "${WORK_DIR}/trim/out.dict" \
  -s 6 \
  -l 6 \
  -b 10 \
  -f 2 \
  "${WORK_DIR}/trim/"*.txt >/dev/null
expect_equal_file "${WORK_DIR}/trim/out.dict" "COMMON" "trim should keep only active bytes"

# overlap subtraction should avoid duplicated bytes
mkdir -p "${WORK_DIR}/overlap"
printf 'ABCDEFGHIJKL\n' > "${WORK_DIR}/overlap/a.txt"
printf 'ABCDEFGHIJKL\n' > "${WORK_DIR}/overlap/b.txt"
run_generator \
  -o "${WORK_DIR}/overlap/out.dict" \
  -s 12 \
  -l 4 \
  -b 8 \
  -f 2 \
  "${WORK_DIR}/overlap/"*.txt >/dev/null
expect_equal_file "${WORK_DIR}/overlap/out.dict" "ABCDEFGHIJKL" "overlap subtraction should avoid duplicate bytes"

# size cap and determinism
mkdir -p "${WORK_DIR}/deterministic"
printf 'prefixCOMMONsuffix\n' > "${WORK_DIR}/deterministic/a.txt"
printf 'otherCOMMONvalue\n' > "${WORK_DIR}/deterministic/b.txt"
run_generator \
  -o "${WORK_DIR}/deterministic/first.dict" \
  -s 5 \
  -l 3 \
  -b 8 \
  -f 2 \
  "${WORK_DIR}/deterministic/"*.txt >/dev/null
run_generator \
  -o "${WORK_DIR}/deterministic/second.dict" \
  -s 5 \
  -l 3 \
  -b 8 \
  -f 2 \
  "${WORK_DIR}/deterministic/"*.txt >/dev/null
expect_equal_files "${WORK_DIR}/deterministic/first.dict" "${WORK_DIR}/deterministic/second.dict" "generator should be deterministic"
[[ $(wc -c < "${WORK_DIR}/deterministic/first.dict") -le 5 ]] || fail "dictionary must respect size cap"

print -- "ok"
