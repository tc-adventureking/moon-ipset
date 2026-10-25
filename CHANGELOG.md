# Changelog

## 0.2.1 — 2026-10-26

- Make subset queries stop at the first uncovered interval and use constant
  auxiliary space instead of constructing a complete difference.
- Map source launcher output failures to exit 2, including the help path.
- Diagnose UTF-16 input, accept an initial JSONL BOM and preserve non-encoding
  decoder errors; pass successful file text directly across the JS boundary.
- Preserve the selected MoonBit core LICENSE and NOTICE in portable CLI archives.
- Require clean, unchanged source for release packaging by default and check
  the portable archive on the minimum supported Node version in CI.

## 0.2.0 — 2026-10-26

- Add CIDR file normalization and semantic diff with strict mode, JSON output,
  source-line diagnostics and CI-friendly exit statuses.
- Add stable source and portable Node CLI entry points; preserve JSONL behavior.
- Add deterministic native benchmarks and a lightweight CI smoke check.
- Exclude development workspace configuration from library archives and verify
  archived code through a separate consumer before release.

## 0.1.0 — 2026-10-26

- Implement IPv4/IPv6 addresses, CIDRs and canonical interval set operations.
- Add JSONL CLI, public API examples and independent correctness checks.
