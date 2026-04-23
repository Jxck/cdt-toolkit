#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
usage: release.sh [--version <semver>] [--target <triple>] [--skip-rehearsal] [--dry-run]

Run the full release workflow for this repo:
  1. verify the git worktree is clean
  2. run cargo test --locked
  3. run cargo publish --dry-run --locked
  4. optionally run scripts/rehearse-release.sh
  5. create git tag v<version>
  6. git push
  7. git push --tags
  8. op run -- cargo publish --locked
EOF
}

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root_dir=$(cd "${script_dir}/.." && pwd)
version=""
target=""
skip_rehearsal=0
dry_run=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      version="$2"
      shift 2
      ;;
    --target)
      target="$2"
      shift 2
      ;;
    --skip-rehearsal)
      skip_rehearsal=1
      shift
      ;;
    --dry-run)
      dry_run=1
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

run_cmd() {
  echo "+ $*"
  if [[ "${dry_run}" -eq 0 ]]; then
    "$@"
  fi
}

cd "${root_dir}"

if [[ -z "${version}" ]]; then
  version=$(sed -n 's/^version = "\(.*\)"/\1/p' Cargo.toml | head -n 1)
fi

if [[ -z "${version}" ]]; then
  echo "error: failed to determine package version from Cargo.toml" >&2
  exit 1
fi

tag="v${version}"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "error: git worktree is not clean; commit or stash changes before release" >&2
  exit 1
fi

if git rev-parse -q --verify "refs/tags/${tag}" >/dev/null; then
  echo "error: git tag already exists: ${tag}" >&2
  exit 1
fi

if git ls-remote --exit-code --tags origin "refs/tags/${tag}" >/dev/null 2>&1; then
  echo "error: remote git tag already exists: ${tag}" >&2
  exit 1
fi

run_cmd cargo test --locked
run_cmd cargo publish --dry-run --locked

if [[ "${skip_rehearsal}" -eq 0 ]]; then
  rehearse_cmd=("${script_dir}/rehearse-release.sh" "--version" "${tag}")
  if [[ -n "${target}" ]]; then
    rehearse_cmd+=("--target" "${target}")
  fi
  run_cmd "${rehearse_cmd[@]}"
fi

run_cmd git tag "${tag}"
run_cmd git push
run_cmd git push --tags
run_cmd op run -- cargo publish --locked
