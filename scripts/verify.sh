#!/usr/bin/env bash
# Reproduce the release checks from the repository root. Uses only local tools.
set -euo pipefail
cd "$(dirname "$0")/.."
report_dir="${1:-work/verification}"
mkdir -p "$report_dir"
moon version --all | tee "$report_dir/toolchain.txt"
node --version | tee -a "$report_dir/toolchain.txt"
python3 --version | tee -a "$report_dir/toolchain.txt"
"${MOON_CC:-cc}" --version | tee -a "$report_dir/toolchain.txt"
moon fmt --check
moon check --deny-warn --target all
moon test --deny-warn --target all | tee "$report_dir/moon-tests.txt"
moon info
if [ -n "$(git status --porcelain --untracked-files=all -- '*.mbti')" ]; then
  git status --short -- '*.mbti'
  echo 'Generated public interfaces differ from the committed API. Run moon info and review the changes.' >&2
  exit 1
fi
moon run cmd/demo --target wasm-gc | tee "$report_dir/demo.txt"
moon -C examples/consumer run . --target wasm-gc | tee "$report_dir/consumer.txt"
moon build --deny-warn --release --target js
cli_path="_build/js/release/build/tc-adventureking/ipset/cmd/ipset/ipset.js"
test -f "$cli_path"
node "$cli_path" < examples/requests.jsonl > "$report_dir/requests.jsonl"
python3 scripts/check_protocol.py --command "node $cli_path" --report "$report_dir/protocol.json"
python3 scripts/check_files.py --command "node $cli_path" --launcher "node bin/ipset.mjs" --report "$report_dir/file-cli.json"
python3 scripts/differential.py --command "node $cli_path" --report "$report_dir/differential.json"
python3 scripts/exhaustive_cidr.py --command "node $cli_path" --report "$report_dir/exhaustive-cidr.json"
python3 scripts/benchmark.py --smoke --output "$report_dir/benchmark-smoke.json"
python3 scripts/package_release.py --output _build/release
mkdir -p "$report_dir/release"
cp _build/release/* "$report_dir/release/"
