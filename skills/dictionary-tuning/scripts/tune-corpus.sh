#!/usr/bin/env bash

set -euo pipefail
shopt -s nullglob

usage() {
  cat <<'EOF'
usage: tune-corpus.sh [options] <inputs...>

Sweep cdt dictionary parameters over an arbitrary corpus, compress the same
inputs, and emit CSV plus top-N summaries.

Options:
  --name <label>                   Corpus label used in reports (default: corpus)
  --preset <quick|broad>           Parameter grid preset (default: quick)
  --sizes <csv>                    Dictionary sizes in bytes
  --slice-lengths <csv>            Slice lengths in bytes
  --block-lengths <csv>            Block lengths in bytes
  --min-frequencies <csv>          Minimum document frequencies
  --output-dir <dir>               Output directory (default: work/dictionary-tuning/<label>)
  --top <n>                        Number of top rows to print (default: 5)
  --debug                          Use target/debug/cdt instead of target/release/cdt
  --keep-output                    Keep existing output-dir contents
  -h, --help                       Show this help

Examples:
  tune-corpus.sh --name html path/to/*.html
  tune-corpus.sh --name js --preset broad assets/*.js
  tune-corpus.sh --name css --sizes 4096,8192 --slice-lengths 8,12 styles/*.css
EOF
}

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root_dir=$(cd "${script_dir}/../../.." && pwd)
name="corpus"
preset="quick"
top_n=5
profile="release"
keep_output=0
sizes_csv=""
slice_lengths_csv=""
block_lengths_csv=""
min_frequencies_csv=""
output_dir=""
inputs=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)
      name="$2"
      shift 2
      ;;
    --preset)
      preset="$2"
      shift 2
      ;;
    --sizes)
      sizes_csv="$2"
      shift 2
      ;;
    --slice-lengths)
      slice_lengths_csv="$2"
      shift 2
      ;;
    --block-lengths)
      block_lengths_csv="$2"
      shift 2
      ;;
    --min-frequencies)
      min_frequencies_csv="$2"
      shift 2
      ;;
    --output-dir)
      output_dir="$2"
      shift 2
      ;;
    --top)
      top_n="$2"
      shift 2
      ;;
    --debug)
      profile="debug"
      shift
      ;;
    --keep-output)
      keep_output=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      inputs+=("$@")
      break
      ;;
    -*)
      usage >&2
      echo "error: unknown argument: $1" >&2
      exit 1
      ;;
    *)
      inputs+=("$1")
      shift
      ;;
  esac
done

if [[ "${#inputs[@]}" -eq 0 ]]; then
  usage >&2
  echo "error: no input files provided" >&2
  exit 1
fi

case "${preset}" in
  quick)
    : "${sizes_csv:=4096,8192}"
    : "${slice_lengths_csv:=8,12}"
    : "${block_lengths_csv:=1024,4096}"
    : "${min_frequencies_csv:=2,3}"
    ;;
  broad)
    : "${sizes_csv:=4096,8192,16384}"
    : "${slice_lengths_csv:=8,12,16}"
    : "${block_lengths_csv:=1024,4096,8192}"
    : "${min_frequencies_csv:=2,3,4}"
    ;;
  *)
    echo "error: invalid preset: ${preset}" >&2
    exit 1
    ;;
esac

IFS=, read -r -a sizes <<< "${sizes_csv}"
IFS=, read -r -a slice_lengths <<< "${slice_lengths_csv}"
IFS=, read -r -a block_lengths <<< "${block_lengths_csv}"
IFS=, read -r -a min_frequencies <<< "${min_frequencies_csv}"

detect_cargo() {
  if command -v cargo >/dev/null 2>&1; then
    command -v cargo
  elif [[ -x "${HOME}/.cargo/bin/cargo" ]]; then
    printf '%s\n' "${HOME}/.cargo/bin/cargo"
  else
    return 1
  fi
}

sum_files() {
  local total=0
  local path size
  for path in "$@"; do
    size=$(wc -c < "${path}")
    total=$((total + size))
  done
  printf '%s\n' "${total}"
}

sum_by_suffix() {
  local dir="$1"
  local suffix="$2"
  local total=0
  local path size
  while IFS= read -r path; do
    size=$(wc -c < "${path}")
    total=$((total + size))
  done < <(find "${dir}" -type f -name "*.${suffix}" | sort)
  printf '%s\n' "${total}"
}

declare -a normalized_inputs=()
for input in "${inputs[@]}"; do
  if [[ ! -f "${input}" ]]; then
    echo "error: input not found or not a file: ${input}" >&2
    exit 1
  fi
  normalized_inputs+=("${input}")
done

if [[ -z "${output_dir}" ]]; then
  output_dir="${root_dir}/work/dictionary-tuning/${name}"
fi

if [[ -n "${CDT_BIN:-}" ]]; then
  binary_path="${CDT_BIN}"
else
  cargo_bin=$(detect_cargo) || {
    echo "error: cargo not found in PATH or ~/.cargo/bin" >&2
    exit 1
  }
  binary_path="${root_dir}/target/${profile}/cdt"
  "${cargo_bin}" build "--${profile}" --locked >/dev/null
fi

if [[ ! -x "${binary_path}" ]]; then
  echo "error: cdt binary not executable: ${binary_path}" >&2
  exit 1
fi

if [[ "${keep_output}" -eq 0 ]]; then
  rm -rf "${output_dir}"
fi
mkdir -p "${output_dir}"

results_csv="${output_dir}/results.csv"
summary_path="${output_dir}/summary.txt"
source_total=$(sum_files "${normalized_inputs[@]}")

printf '%s\n' "name,size,slice_length,block_length,min_frequency,status,source_total,dict_size,brotli_total,zstd_total,dcb_total,dcz_total,brotli_net,zstd_net,wrapped_total,combined_net,dict_path" > "${results_csv}"
: > "${summary_path}"

for size in "${sizes[@]}"; do
  for slice_length in "${slice_lengths[@]}"; do
    for block_length in "${block_lengths[@]}"; do
      if (( block_length < slice_length )); then
        continue
      fi
      for min_frequency in "${min_frequencies[@]}"; do
        combo_id="s${size}-l${slice_length}-b${block_length}-f${min_frequency}"
        combo_dir="${output_dir}/${combo_id}"
        out_dir="${combo_dir}/compressed"
        dict_path="${combo_dir}/dictionary.dict"

        rm -rf "${combo_dir}"
        mkdir -p "${out_dir}"

        if ! "${binary_path}" dictionary \
          -o "${dict_path}" \
          -s "${size}" \
          -l "${slice_length}" \
          -b "${block_length}" \
          -f "${min_frequency}" \
          "${normalized_inputs[@]}" >/dev/null 2>&1; then
          printf '%s\n' \
            "${name},${size},${slice_length},${block_length},${min_frequency},skip,${source_total},0,0,0,0,0,0,0,0,0," \
            >> "${results_csv}"
          continue
        fi

        "${binary_path}" compress \
          --dict "${dict_path}" \
          --output-dir "${out_dir}" \
          --raw-brotli \
          --raw-zstd \
          --delta-compression-brotli \
          --delta-compression-zstd \
          "${normalized_inputs[@]}" >/dev/null

        dict_size=$(wc -c < "${dict_path}")
        brotli_total=$(sum_by_suffix "${out_dir}" br)
        zstd_total=$(sum_by_suffix "${out_dir}" zstd)
        dcb_total=$(sum_by_suffix "${out_dir}" dcb)
        dcz_total=$(sum_by_suffix "${out_dir}" dcz)
        brotli_net=$((dict_size + brotli_total))
        zstd_net=$((dict_size + zstd_total))
        wrapped_total=$((dcb_total + dcz_total))
        combined_net=$((dict_size + dcb_total + dcz_total))

        printf '%s\n' \
          "${name},${size},${slice_length},${block_length},${min_frequency},ok,${source_total},${dict_size},${brotli_total},${zstd_total},${dcb_total},${dcz_total},${brotli_net},${zstd_net},${wrapped_total},${combined_net},${dict_path}" \
          >> "${results_csv}"
      done
    done
  done
done

{
  printf '== %s ==\n' "${name}"
  printf 'results=%s\n' "${results_csv}"
  head -n 1 "${results_csv}"
  awk -F, '$6 == "ok"' "${results_csv}" | sort -t, -k16,16n | head -n "${top_n}"
  printf '\n'
} | tee -a "${summary_path}"

printf 'summary=%s\n' "${summary_path}"
