// An unexpected Node/FFI failure must never look like a valid diff (exit 1).
// Preloading preserves process.argv and the caller's working directory.
function fail(error) {
  process.exitCode = 2;
  process.stderr.write(`ipset: internal error: ${error instanceof Error ? error.message : String(error)}\n`);
}

process.on('uncaughtException', fail);
process.on('unhandledRejection', fail);
process.stderr.on('error', () => { process.exitCode = 2; });
process.stdout.on('error', (error) => {
  // A downstream pipe may close after receiving the lines it needs.
  if (error.code !== 'EPIPE') fail(error);
});
