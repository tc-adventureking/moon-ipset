// Check the frozen corpus independently of MoonBit's test runner.
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';

const root = fileURLToPath(new URL('../conformance/', import.meta.url));
const manifest = JSON.parse(readFileSync(join(root, 'manifest.json'), 'utf8'));
function requireThat(condition, message) {
  if (!condition) throw new Error(message);
}
requireThat(manifest.schema === 1, 'Unsupported corpus schema');
requireThat(manifest.reference.sha256 === 'fd268e3a43df6f428868b3c4c865f510380b49058a796bcc30763788e0a74686', 'Unexpected reference');
const declared = new Set(manifest.adaptation_names.map(name => `adaptation.${name}`));
requireThat(declared.size === 11, 'Missing adaptation categories');
for (const suite of ['strict', 'adaptations']) {
  const entry = manifest[suite];
  const bytes = readFileSync(join(root, entry.file));
  requireThat(createHash('sha256').update(bytes).digest('hex') === entry.sha256, `Corpus changed without manifest update: ${suite}`);
  const rows = bytes.toString('utf8').split('\n').filter(line => line.startsWith('  #|')).map(line => JSON.parse(line.slice(4)));
  requireThat(rows.length > 0 && rows.length === entry.cases, `Wrong ${suite} count`);
  const counts = {};
  for (const row of rows) {
    requireThat(typeof row.category === 'string' && typeof row.request?.op === 'string', 'Malformed fixture request');
    requireThat(typeof row.expected?.ok === 'boolean', 'Malformed expected result');
    requireThat(row.expected.ok === Object.hasOwn(row.expected, 'value'), 'Wrong result envelope');
    if (suite === 'strict') {
      requireThat(!row.category.startsWith('adaptation.') && !Object.hasOwn(row, 'cpython_result'), 'Adaptation in strict count');
    } else {
      requireThat(declared.has(row.category), `Undeclared adaptation: ${row.category}`);
      requireThat(typeof row.cpython_result?.ok === 'boolean', 'Missing original Python result');
      requireThat(JSON.stringify(row.cpython_result) !== JSON.stringify(row.expected), 'Adaptation must actually differ');
    }
    counts[row.category] = (counts[row.category] ?? 0) + 1;
  }
  requireThat(JSON.stringify(Object.fromEntries(Object.entries(counts).sort())) === JSON.stringify(entry.categories), `Category counts changed: ${suite}`);
  if (suite === 'adaptations') requireThat(Object.keys(counts).length === declared.size, 'Uncovered adaptation');
  console.log(`${suite}: ${rows.length} frozen vectors in ${Object.keys(counts).length} categories; reference pin declared, corpus hash checked`);
}
const protocol = manifest.protocol_rejections;
const protocolBytes = readFileSync(join(root, protocol.file));
requireThat(createHash('sha256').update(protocolBytes).digest('hex') === protocol.sha256, 'Protocol fixture hash changed');
const protocolRows = protocolBytes.toString('utf8').split('\n').filter(line => line.startsWith('  #|')).map(line => JSON.parse(line.slice(4)));
requireThat(protocolRows.length === protocol.cases && protocol.cases === manifest.excluded_protocol_inputs.out_of_range_byte_values, 'Protocol rejection count differs');
requireThat(protocolRows.every(row => Array.isArray(row.bytes) && row.bytes.some(v => !Number.isInteger(v) || v < 0 || v > 255)), 'Unexpected protocol rejection');
console.log(`protocol: ${protocolRows.length} unrepresentable Byte inputs checked separately`);
