# Changelog

## 0.3.1 — 2026-10-31

- Add `IpInterface::from_address_mask` for separately supplied typed addresses
  and masks, reusing network mask validation while retaining host bits and scope.
- Convert packed IPv4/IPv6 addresses directly in network byte order, avoiding
  intermediate BigInt work. Add byte-position regressions and a native benchmark.
- Verify the official library ZIP in public CI without Python, including
  retained licenses, source equality, excluded development files, package-local
  documentation links and independent consumers on all four targets.
- Keep the usage example link accessible from the installed library package.

## 0.3.0 — 2026-10-29

- Add general `IpAddress`, `IpNetwork` and `IpInterface` APIs, using CPython
  3.13.2 ipaddress as a fixed behavior reference with documented adaptations.
- Support address classification, scope identifiers, bytes/BigInt conversion,
  formatting, checked arithmetic, mapped IPv6, 6to4 and Teredo.
- Add strict network parsing, netmask/hostmask input, lazy hosts/subnets,
  supernets, exact counts and indexes, exclusion, collapse and range summaries.
- Preserve configured interface hosts and prefixes; retain legacy set APIs and CLI.
- Add three general consumer scenarios and MoonBit regression tests. Move
  Python validation tools and generated reports out of the published source.

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
