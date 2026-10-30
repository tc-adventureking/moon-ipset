#!/usr/bin/env bash
# Verify the official source ZIP and consume only its extracted library.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
for tool in moon node unzip; do
  command -v "$tool" >/dev/null || { printf 'Missing tool: %s\n' "$tool" >&2; exit 1; }
done
scratch=$(mktemp -d "${TMPDIR:-/tmp}/moon-ipset-package.XXXXXXXX")
trap 'rm -rf -- "$scratch"' EXIT
scratch=$(realpath "$scratch")
if [[ "$scratch" == "$repo/"* ]]; then
  printf 'TMPDIR must be outside the source repository.\n' >&2
  exit 1
fi
export MOON_WORK=off
cd "$repo"

# Some Moon versions use _build/publish even with --target-dir. Use the
# package command's reported path, never a pre-existing ZIP found by globbing.
if ! moon package --target-dir "$scratch/build" > "$scratch/package.log" 2>&1; then
  cat "$scratch/package.log" >&2
  exit 1
fi
cat "$scratch/package.log"
mapfile -t archives < <(sed -n 's/^Package to //p' "$scratch/package.log")
if [[ ${#archives[@]} -ne 1 ]]; then
  printf 'Expected exactly one archive path from moon package.\n' >&2
  exit 1
fi
archive=$(realpath "${archives[0]}")
case "$archive" in
  "$scratch"/*|"$repo/_build/"*) ;;
  *) printf 'Unexpected package output path.\n' >&2; exit 1 ;;
esac
unzip -tq "$archive"
unzip -Z1 "$archive" > "$scratch/members.txt"

# Reject development files before extraction; inspect only the freshly
# generated archive. License files under third_party/python are required.
node --input-type=module - "$scratch/members.txt" <<'NODE'
import { readFileSync } from 'node:fs';
const names = readFileSync(process.argv[2], 'utf8').trimEnd().split('\n');
if (new Set(names).size !== names.length) throw new Error('Duplicate ZIP members');
const excluded = new Set(['work', '_build', 'target', 'scripts', 'cmd', 'bin',
  'bench', 'examples', 'node_modules', '__pycache__', 'moon.work']);
for (const name of names) {
  const parts = name.split('/');
  if (name.startsWith('/') || /[\\:\r]/.test(name) ||
      parts.some(p => p.startsWith('.') || excluded.has(p)) ||
      /\.(?:py|pyi|pyc|ipynb|pem|key|core)$/i.test(name) ||
      /^docs\/(?:ai\/|verification\/|AI_COLLABORATION\.md$)/.test(name)) {
    throw new Error(`Unexpected library ZIP member: ${name}`);
  }
}
NODE
unzip -q "$archive" -d "$scratch/library"

node --input-type=module - "$repo" "$scratch/library" <<'NODE'
import { readFileSync, readdirSync, lstatSync } from 'node:fs';
import { join, dirname, resolve } from 'node:path';
const [repo, library] = process.argv.slice(2);
const required = ['moon.mod', 'moon.pkg', 'README.md', 'LICENSE',
  'third_party/python/LICENSE', 'docs/PROVENANCE.md', 'docs/COMPATIBILITY.md',
  ...readdirSync(repo).filter(name => /\.(?:mbt|mbti)$/.test(name))];
for (const name of required) {
  if (!readFileSync(join(repo, name)).equals(readFileSync(join(library, name)))) {
    throw new Error(`Packaged source or license differs: ${name}`);
  }
}
function inspect(directory) {
  for (const name of readdirSync(directory)) {
    const path = join(directory, name);
    const stat = lstatSync(path);
    if (stat.isSymbolicLink()) throw new Error(`ZIP contains a symlink: ${path}`);
    if (stat.isDirectory()) inspect(path);
    else if (name.endsWith('.md')) {
      const markdown = readFileSync(path, 'utf8');
      for (const [, href] of markdown.matchAll(/\[[^\]]*\]\(([^)]+)\)/g)) {
        if (/^[a-z][a-z\d+.-]*:/i.test(href) || href.startsWith('#')) continue;
        const target = resolve(dirname(path), href.split('#')[0]);
        if (!target.startsWith(library + '/')) throw new Error(`Link leaves package: ${href}`);
        lstatSync(target); // Fail if documentation points at an excluded file.
      }
    }
  }
}
inspect(library);
console.log('Packaged source, licenses, exclusions and documentation links passed.');
NODE

# Compile without the repository workspace, then reuse all checked-in consumer
# scenarios in a new workspace containing only the extracted library.
moon -C "$scratch/library" check --target all --deny-warn --frozen
mkdir "$scratch/consumer"
cp "$repo/examples/consumer/"*.mbt "$repo/examples/consumer/moon.mod" \
   "$repo/examples/consumer/moon.pkg" "$scratch/consumer/"
printf '%s\n' 'members = ["library", "consumer"]' > "$scratch/moon.work"
export MOON_WORK="$scratch/moon.work"
moon -C "$scratch/consumer" test . --target all --deny-warn --frozen
moon -C "$scratch/consumer" run . --target wasm-gc --frozen
printf '%s\n' 'Official library ZIP and independent consumer passed on all four targets.'
