#!/usr/bin/env bash
# Public checks require MoonBit, Node.js, unzip and a C toolchain; no Python.
set -euo pipefail
cd "$(dirname "$0")/.."
# Include both independent example modules even if the caller disables workspaces.
export MOON_WORK="$PWD/moon.work"
moon version --all
node scripts/check-conformance.mjs
node scripts/check-cloud-snapshot.mjs
moon fmt --check
moon check --deny-warn --target all
moon test --deny-warn --target all
node scripts/check-conformance-mutations.mjs
moon info
git diff --exit-code -- '*.mbti'
moon run cmd/demo --target wasm-gc
moon -C examples/consumer run . --target wasm-gc
moon -C examples/cloud-policy run cmd --target wasm-gc
moon build --deny-warn --release --target all
status=0
actual=$(node bin/ipset.mjs diff examples/policies/old.txt examples/policies/new.txt --json) || status=$?
test "${status:-0}" -eq 1
expected=$(cat examples/policies/expected-diff.json)
test "$actual" = "$expected"
printf '%s\n' 'MoonBit checks, examples and file CLI passed.'
bash scripts/verify-package.sh
