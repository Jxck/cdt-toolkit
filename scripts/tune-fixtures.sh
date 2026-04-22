#!/usr/bin/env bash

set -euo pipefail
shopt -s nullglob

usage() {
  cat <<'EOF'
usage: tune-fixtures.sh [options]

Sweep dictionary-generation parameters against the checked-in fixture corpora,
build dictionaries, compress the same fixture files, and emit a CSV report plus
top-N summaries.

Options:
  --corpus <html|js|css|all>       Corpus to tune (default: all)
  --preset <quick|broad>           Parameter grid preset (default: quick)
  --sizes <csv>                    Dictionary sizes in bytes
  --slice-lengths <csv>            Slice lengths in bytes
  --block-lengths <csv>            Block lengths in bytes
  --min-frequencies <csv>          Minimum document frequencies
  --output-dir <dir>               Output directory (default: work/tune-fixtures)
  --top <n>                        Number of top rows to print per corpus (default: 5)
  --debug                          Use target/debug/cdt instead of target/release/cdt
  --keep-output                    Keep existing output-dir contents
  -h, --help                       Show this help

Examples:
  ./scripts/tune-fixtures.sh
  ./scripts/tune-fixtures.sh --corpus html --preset broad
  ./scripts/tune-fixtures.sh --corpus css --sizes 4096,8192 --slice-lengths 8,12
EOF
}

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root_dir=$(cd "${script_dir}/.." && pwd)
output_dir="${root_dir}/work/tune-fixtures"
corpus="all"
preset="quick"
top_n=5
profile="release"
keep_output=0
sizes_csv=""
slice_lengths_csv=""
block_lengths_csv=""
min_frequencies_csv=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --corpus)
      corpus="$2"
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
    *)
      usage >&2
      echo "error: unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

case "${corpus}" in
  html|js|css)
    corpora=("${corpus}")
    ;;
  all)
    corpora=(html js css)
    ;;
  *)
    echo "error: invalid corpus: ${corpus}" >&2
    exit 1
    ;;
esac

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

cargo_bin=$(detect_cargo) || {
  echo "error: cargo not found in PATH or ~/.cargo/bin" >&2
  exit 1
}

binary_path="${root_dir}/target/${profile}/cdt"
"${cargo_bin}" build "--${profile}" --locked >/dev/null

if [[ "${keep_output}" -eq 0 ]]; then
  rm -rf "${output_dir}"
fi
mkdir -p "${output_dir}"

summary_path="${output_dir}/summary.txt"
: > "${summary_path}"

for corpus_name in "${corpora[@]}"; do
  case "${corpus_name}" in
    html) extension="html" ;;
    js) extension="js" ;;
    css) extension="css" ;;
  esac

  inputs=("${root_dir}/tests/fixtures/${corpus_name}"/*.${extension})
  if [[ "${#inputs[@]}" -eq 0 ]]; then
    echo "error: no inputs found for corpus ${corpus_name}" >&2
    exit 1
  fi

  corpus_dir="${output_dir}/${corpus_name}"
  mkdir -p "${corpus_dir}"
  results_csv="${corpus_dir}/results.csv"
  source_total=$(sum_files "${inputs[@]}")
  printf '%s\n' "corpus,size,slice_length,block_length,min_frequency,status,source_total,dict_size,brotli_total,zstd_total,dcb_total,dcz_total,brotli_net,zstd_net,wrapped_total,combined_net,dict_path" > "${results_csv}"

  for size in "${sizes[@]}"; do
    for slice_length in "${slice_lengths[@]}"; do
      for block_length in "${block_lengths[@]}"; do
        if (( block_length < slice_length )); then
          continue
        fi
        for min_frequency in "${min_frequencies[@]}"; do
          combo_id="s${size}-l${slice_length}-b${block_length}-f${min_frequency}"
          combo_dir="${corpus_dir}/${combo_id}"
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
            "${inputs[@]}" >/dev/null 2>&1; then
            printf '%s\n' \
              "${corpus_name},${size},${slice_length},${block_length},${min_frequency},skip,${source_total},0,0,0,0,0,0,0,0,0," \
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
            "${inputs[@]}" >/dev/null

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
            "${corpus_name},${size},${slice_length},${block_length},${min_frequency},ok,${source_total},${dict_size},${brotli_total},${zstd_total},${dcb_total},${dcz_total},${brotli_net},${zstd_net},${wrapped_total},${combined_net},${dict_path}" \
            >> "${results_csv}"
        done
      done
    done
  done

  {
    printf '== %s ==\n' "${corpus_name}"
    printf 'results=%s\n' "${results_csv}"
    head -n 1 "${results_csv}"
    awk -F, 'NR == 1 || $6 == "ok"' "${results_csv}" | tail -n +2 | sort -t, -k15,15n | head -n "${top_n}"
    printf '\n'
  } | tee -a "${summary_path}"
done

printf 'summary=%s\n' "${summary_path}"
