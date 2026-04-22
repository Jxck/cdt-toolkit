#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
usage: rehearse-release.sh [--target <triple>] [--version <tag>] [--keep-work]

Create a scratch copy of this package, run cargo test/build there, assemble the
release archive, extract it, and verify that the packaged binary starts.
EOF
}

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root_dir=$(cd "${script_dir}/.." && pwd)
keep_work=0
target=""
version="v0.0.0-rehearsal.0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      target="$2"
      shift 2
      ;;
    --version)
      version="$2"
      shift 2
      ;;
    --keep-work)
      keep_work=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      echo "error: unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "${target}" ]]; then
  target=$(rustc -vV | sed -n 's/^host: //p')
fi

scratch_dir=$(mktemp -d "${TMPDIR:-/tmp}/cdt-rehearsal.XXXXXX")

cleanup() {
  if [[ "${keep_work}" -eq 0 ]]; then
    rm -rf "${scratch_dir}"
  fi
}
trap cleanup EXIT

(
  cd "${root_dir}"
  tar \
    --exclude='./.git' \
    --exclude='./target' \
    --exclude='./work' \
    -cf - .
) | tar -xf - -C "${scratch_dir}"

(
  cd "${scratch_dir}"
  git init -q
  git config user.name "cdt rehearsal"
  git config user.email "cdt-rehearsal@example.invalid"
  git add .
  git commit -q -m "Rehearsal snapshot"
  cargo test --locked
  cargo build --release --target "${target}" --locked
  ./scripts/package-release.sh --root "${scratch_dir}" --target "${target}" --version "${version}" >/dev/null

  archive="${scratch_dir}/cdt-${version}-${target}.tar.gz"
  extract_dir="${scratch_dir}/extract"
  mkdir -p "${extract_dir}"
  tar -xzf "${archive}" -C "${extract_dir}"

  packaged_root="${extract_dir}/cdt-${version}-${target}"
  "${packaged_root}/cdt" --help >/dev/null
  "${packaged_root}/cdt" dictionary --help >/dev/null
  "${packaged_root}/cdt" compress --help >/dev/null

  if [[ "${keep_work}" -eq 1 ]]; then
    echo "scratch=${scratch_dir}"
    echo "archive=${archive}"
    echo "checksum=${archive}.sha256"
  else
    echo "verified=cdt-${version}-${target}.tar.gz"
  fi
)
