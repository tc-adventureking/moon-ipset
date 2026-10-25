#!/usr/bin/env node
import { spawnSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const args = process.argv.slice(2);
const optionEnd = args.indexOf('--');
const options = optionEnd < 0 ? args : args.slice(0, optionEnd);
const help = `Usage: ipset [jsonl]
       ipset normalize [--strict] [--json] [--] FILE
       ipset diff [--strict] [--json] [--] OLD NEW
       ipset --help

FILE is a UTF-8 list with one IP or CIDR per line; '-' reads stdin once.
Blank lines, surrounding whitespace, and # comments are ignored.
CRLF and an initial UTF-8 BOM are supported. Bare IPs mean /32 or /128.
--strict rejects CIDRs with host bits set; the default masks host bits.
--json emits {cidrs:[...]} for normalize or {added:[...],removed:[...]} for diff.
-- ends options, allowing filenames that begin with '-'.
Without arguments (or with jsonl), read JSON requests from stdin, one per line.
Exit codes: 0 success/no changes, 1 diff has changes, 2 input/usage error.
`;

if (options.includes('--help') || options.includes('-h')) {
  process.stdout.write(help);
} else {
  const root = dirname(dirname(fileURLToPath(import.meta.url)));
  // Build every invocation so a changed source can never run a stale artifact.
  // Build output belongs to stderr; stdin is reserved for the requested command.
  const build = spawnSync('moon', [
    'build', 'cmd/ipset', '--release', '--target', 'js',
  ], { cwd: root, stdio: ['ignore', process.stderr, process.stderr] });
  if (build.error || build.signal || build.status !== 0) {
    if (build.error) process.stderr.write(`ipset: cannot run moon: ${build.error.message}\n`);
    else if (build.signal) process.stderr.write(`ipset: build terminated by ${build.signal}\n`);
    process.exitCode = 2;
  } else {
    const entry = join(root, '_build', 'js', 'release', 'build', 'tc-adventureking', 'ipset', 'cmd', 'ipset', 'ipset.js');
    if (!existsSync(entry)) {
      process.stderr.write('ipset: build succeeded without producing the CLI entry\n');
      process.exitCode = 2;
    } else {
      const bootstrap = join(root, 'bin', 'run.mjs');
      if (!existsSync(bootstrap)) {
        process.stderr.write('ipset: missing CLI bootstrap bin/run.mjs\n');
        process.exitCode = 2;
      } else {
        const run = spawnSync(process.execPath, [bootstrap, entry, ...args], { stdio: 'inherit' });
        if (run.error || run.signal) {
          process.stderr.write(`ipset: ${run.error?.message ?? `terminated by ${run.signal}`}\n`);
          process.exitCode = 2;
        } else {
          process.exitCode = run.status ?? 2;
        }
      }
    }
  }
}
