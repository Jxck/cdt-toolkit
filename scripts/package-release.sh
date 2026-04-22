#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
usage: package-release.sh --version <tag> --target <triple> [--root <dir>] [--output-dir <dir>]
EOF
}

root_dir=$(pwd)
output_dir=""
target=""
version=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      root_dir="$2"
      shift 2
      ;;
    --output-dir)
      output_dir="$2"
      shift 2
      ;;
    --target)
      target="$2"
      shift 2
      ;;
    --version)
      version="$2"
      shift 2
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

if [[ -z "${version}" || -z "${target}" ]]; then
  usage >&2
  echo "error: --version and --target are required" >&2
  exit 1
fi

if [[ -z "${output_dir}" ]]; then
  output_dir="${root_dir}"
fi

binary_path="${root_dir}/target/${target}/release/cdt"
if [[ ! -x "${binary_path}" ]]; then
  echo "error: missing built binary: ${binary_path}" >&2
  exit 1
fi

staging_name="cdt-${version}-${target}"
staging_dir="${output_dir}/${staging_name}"
archive_path="${output_dir}/${staging_name}.tar.gz"
checksum_path="${archive_path}.sha256"

rm -rf "${staging_dir}"
mkdir -p "${staging_dir}"

cp "${binary_path}" "${staging_dir}/"
cp "${root_dir}/LICENSE" "${root_dir}/NOTICE" "${root_dir}/README.md" "${staging_dir}/"
cp -R "${root_dir}/THIRD_PARTY_LICENSES" "${staging_dir}/"

tar -C "${output_dir}" -czf "${archive_path}" "${staging_name}"
rm -rf "${staging_dir}"

if command -v shasum >/dev/null 2>&1; then
  (
    cd "${output_dir}"
    shasum -a 256 "${staging_name}.tar.gz" > "${staging_name}.tar.gz.sha256"
  )
else
  (
    cd "${output_dir}"
    sha256sum "${staging_name}.tar.gz" > "${staging_name}.tar.gz.sha256"
  )
fi

echo "archive=${archive_path}"
echo "checksum=${checksum_path}"
