// Internal launcher: node run.mjs COMPILED_ENTRY [CLI arguments...]
import { pathToFileURL } from 'node:url';

try {
  const entry = process.argv[2];
  // Present the same argv that directly running the compiled entry would use.
  process.argv.splice(1, 1);
  await import('./runtime.mjs');
  await import(pathToFileURL(entry).href);
} catch (error) {
  process.exitCode = 2;
  process.stderr.write(`ipset: internal error: ${error instanceof Error ? error.message : String(error)}\n`);
}
