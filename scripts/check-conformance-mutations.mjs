// Run only in disposable copies: the source worktree is never mutated.
import { mkdtempSync, readdirSync, readFileSync, writeFileSync, copyFileSync, cpSync, rmSync } from 'node:fs';
import { join, resolve, dirname, basename } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const repo = fileURLToPath(new URL('../', import.meta.url));
const scratch = mkdtempSync(join(tmpdir(), 'ipset-conformance-'));
const env = { ...process.env, MOON_WORK: 'off' };
const report = [];
const mutations = [
  { name: 'accept-host-bits', file: 'cidr.mbt', before: 'if strict && network != address {', after: 'if strict && prefix == 0 && network != address {', expectedTest: 'pinned CPython strict vectors' },
  { name: 'lose-scope-on-expansion', file: 'address_api.mbt', before: 'pub fn IpAddress::exploded(self : IpAddress) -> String {', after: 'pub fn IpAddress::exploded(self : IpAddress) -> String {\n  if self.scope_ is Some(_) { return self.unscoped().exploded() }', expectedTest: 'declared adaptations remain separate from strict comparisons' },
];
function run(args, label, expectedPass, expectedTest) {
  const result = spawnSync('moon', args, { cwd: scratch, env, encoding: 'utf8', timeout: 180_000, maxBuffer: 8 * 1024 * 1024 });
  const output = `${result.stdout ?? ''}\n${result.stderr ?? ''}`;
  if (result.error || result.signal) throw new Error(`${label}: process failure ${result.error ?? result.signal}`);
  const summary = [...output.matchAll(/Total tests: (\d+), passed: (\d+), failed: (\d+)/g)];
  const failed = summary.reduce((n, m) => n + Number(m[3]), 0);
  // A compile/transport failure is never evidence that a mutation was killed.
  if (expectedPass ? result.status !== 0 : result.status === 0 || failed === 0) {
    throw new Error(`${label}: unexpected test outcome\n${output}`);
  }
  if (!summary.length) throw new Error(`${label}: missing executed-test summary\n${output}`);
  const detectedBy = [...output.matchAll(/\("([^"]+)"\) failed:/g)].map(match => match[1]);
  if (!expectedPass && !detectedBy.includes(expectedTest)) throw new Error(`${label}: expected test did not detect the mutation\n${output}`);
  report.push({ name: label, status: expectedPass ? 'passed' : 'detected', failed_tests: failed, detected_by: detectedBy });
}
try {
  for (const name of readdirSync(repo)) {
    if (/\.(?:mbt|mbti)$/.test(name) || ['moon.mod', 'moon.pkg'].includes(name)) copyFileSync(join(repo, name), join(scratch, name));
  }
  cpSync(join(repo, 'conformance'), join(scratch, 'conformance'), { recursive: true });
  run(['test', 'conformance', '--target', 'js', '--deny-warn'], 'baseline', true);
  for (const mutation of mutations) {
    const path = join(scratch, mutation.file);
    const original = readFileSync(path, 'utf8');
    if (original.split(mutation.before).length !== 2) throw new Error(`Mutation anchor changed: ${mutation.name}`);
    writeFileSync(path, original.replace(mutation.before, mutation.after));
    try { run(['test', 'conformance', '--target', 'js', '--deny-warn'], mutation.name, false, mutation.expectedTest); }
    finally { writeFileSync(path, original); }
  }
  console.log(JSON.stringify({ backend: 'js', mutations: report }));
} finally {
  if (dirname(resolve(scratch)) !== resolve(tmpdir()) || !basename(scratch).startsWith('ipset-conformance-')) throw new Error('Unexpected temporary path');
  rmSync(scratch, { recursive: true, force: true });
}
