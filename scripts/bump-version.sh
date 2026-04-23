#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
usage: bump-version.sh <patch|minor|major> [--dry-run]

Bump the package version in Cargo.toml, commit it as v<version>, and create the
matching git tag.
EOF
}

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root_dir=$(cd "${script_dir}/.." && pwd)
level=""
dry_run=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    patch|minor|major)
      if [[ -n "${level}" ]]; then
        usage >&2
        echo "error: bump level specified more than once" >&2
        exit 1
      fi
      level="$1"
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

if [[ -z "${level}" ]]; then
  usage >&2
  echo "error: bump level is required" >&2
  exit 1
fi

run_cmd() {
  echo "+ $*"
  if [[ "${dry_run}" -eq 0 ]]; then
    "$@"
  fi
}

cd "${root_dir}"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "error: git worktree is not clean; commit or stash changes before bumping version" >&2
  exit 1
fi

current_version=$(awk '
  $0 == "[package]" { in_package=1; next }
  /^\[/ && $0 != "[package]" { in_package=0 }
  in_package && /^version = "/ {
    match($0, /"([^"]+)"/)
    print substr($0, RSTART + 1, RLENGTH - 2)
    exit
  }
' Cargo.toml)

if [[ -z "${current_version}" ]]; then
  echo "error: failed to determine current package version from Cargo.toml" >&2
  exit 1
fi

IFS=. read -r major minor patch <<< "${current_version}"
if [[ -z "${major:-}" || -z "${minor:-}" || -z "${patch:-}" ]]; then
  echo "error: only simple semver versions are supported: ${current_version}" >&2
  exit 1
fi

case "${level}" in
  patch)
    patch=$((patch + 1))
    ;;
  minor)
    minor=$((minor + 1))
    patch=0
    ;;
  major)
    major=$((major + 1))
    minor=0
    patch=0
    ;;
esac

next_version="${major}.${minor}.${patch}"
tag="v${next_version}"

if git rev-parse -q --verify "refs/tags/${tag}" >/dev/null; then
  echo "error: git tag already exists: ${tag}" >&2
  exit 1
fi

if git ls-remote --exit-code --tags origin "refs/tags/${tag}" >/dev/null 2>&1; then
  echo "error: remote git tag already exists: ${tag}" >&2
  exit 1
fi

echo "+ update Cargo.toml version ${current_version} -> ${next_version}"
if [[ "${dry_run}" -eq 0 ]]; then
  awk -v next_version="${next_version}" '
    $0 == "[package]" { in_package=1; print; next }
    /^\[/ && $0 != "[package]" { in_package=0 }
    in_package && !done && /^version = "/ {
      print "version = \"" next_version "\""
      done=1
      next
    }
    { print }
  ' Cargo.toml > Cargo.toml.tmp
  mv Cargo.toml.tmp Cargo.toml
fi

run_cmd git add Cargo.toml
run_cmd git commit -m "${tag}"
run_cmd git tag "${tag}"
