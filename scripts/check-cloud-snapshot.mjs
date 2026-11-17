import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';

const root = fileURLToPath(new URL('../examples/cloud-policy/', import.meta.url));
const manifest = JSON.parse(readFileSync(join(root, 'snapshot.json'), 'utf8'));
const sha = bytes => createHash('sha256').update(bytes).digest('hex');
function check(ok, message) { if (!ok) throw new Error(message); }
function embedded(name) {
  const content = readFileSync(join(root, name), 'utf8');
  return content.split('\n').filter(line => line.startsWith('  #|')).map(line => line.slice(4)).join('\n');
}
check(manifest.schema === 1, 'Unexpected snapshot schema');
const bytes = readFileSync(join(root, 'aws-ip-ranges.json'));
check(sha(bytes) === manifest.source.sha256, 'Raw AWS snapshot changed');
const source = JSON.parse(bytes);
check(source.createDate === manifest.source.createDate && source.syncToken === manifest.source.syncToken, 'Snapshot metadata mismatch');
for (const [name, expectedHash] of Object.entries(manifest.files)) check(sha(readFileSync(join(root, name))) === expectedHash, `Changed derived file: ${name}`);
const rows = [...source.prefixes, ...source.ipv6_prefixes].filter(row => row.service === 'EC2');
const prefixes = rows.map(row => row.ip_prefix ?? row.ipv6_prefix);
const exceptions = rows.filter(row => row.region === 'us-east-1').map(row => row.ip_prefix ?? row.ipv6_prefix);
check(prefixes.join('\n') === embedded('source_prefixes.mbt'), 'EC2 extraction differs from raw snapshot');
check(exceptions.join('\n') === embedded('exception_prefixes.mbt'), 'Exclusion extraction differs from raw snapshot');
const queries = embedded('query_addresses.mbt').split('\n');
check(prefixes.length === manifest.selection.source_count && exceptions.length === manifest.selection.exception_count && queries.length === manifest.selection.query_count, 'Input counts differ');
const expected = JSON.parse(embedded('expected_wbtest.mbt'));
check(expected.source_prefixes === prefixes.length && expected.exception_prefixes === exceptions.length, 'Expected result describes different inputs');
check(expected.normalized.length === manifest.expected.normalized_count && expected.allowed.length === manifest.expected.allowed_count && expected.exceptions.length === manifest.expected.exception_count, 'Expected CIDR counts differ');
check(expected.members.length === queries.length && expected.members.every(x => typeof x === 'boolean'), 'Expected membership answers differ');
check(expected.members.filter(Boolean).length === manifest.expected.matched_queries, 'Expected membership count differs');
for (const key of ['ipv4_addresses', 'ipv6_addresses']) check(expected[key] === manifest.expected[key], `Expected cardinality differs: ${key}`);
console.log(`AWS snapshot verified: ${prefixes.length} EC2 entries, ${exceptions.length} exclusions, ${queries.length} queries; source and derived hashes match`);
