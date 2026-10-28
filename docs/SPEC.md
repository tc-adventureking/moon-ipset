# Legacy set API and CLI specification

This document describes the legacy `Address`, `Cidr`, `IpSet` and file/JSONL
CLI behavior. The general `IpAddress`, `IpNetwork` and `IpInterface` API is
described in [COMPATIBILITY.md](COMPATIBILITY.md); its parsing defaults and
scoped-address support intentionally differ from the legacy API.

Test results and release status are
reported separately; the specification itself is not proof of implementation.

## Scope

- IPv4 and IPv6 parsing, canonical formatting, and CIDR normalization.
- Immutable address sets represented by normalized, disjoint intervals.
- Union, intersection, difference, symmetric difference, containment, and minimal
  CIDR cover output without enumerating individual addresses.
- IPv4 and IPv6 remain distinct families. Mapped IPv6 addresses remain IPv6.
- A set may contain both families. Output orders IPv4 before IPv6, then ascending
  network address and prefix length.

## Text semantics

- IPv4: exactly four decimal octets, 0 through 255, no leading zeros except `0`.
- IPv6: eight hexadecimal groups or one valid `::` compression, with an optional
  IPv4 dotted suffix consuming two groups. Accept uppercase input. Reject zone
  identifiers, brackets, whitespace, signs, repeated compression, and overflow.
- IPv6 formatting: lowercase hex, no leading zeros, compress the first longest
  run of at least two zero groups. Mapped addresses use hex output.
- CIDR: a slash followed by decimal digits, no leading zeros except `0`, range
  0..32 or 0..128. Default parsing clears host bits; strict parsing rejects them.
- Address ranges are inclusive, require equal families, and require start <= end.
- `/0`, singleton `/32` and `/128`, and both maximum addresses are supported.
  Successor/predecessor must report absence at domain limits rather than wrap.

## JSON Lines protocol

Each nonempty input line is a JSON object with an `op` string. Each response is one
JSON object. Successful results contain `ok: true`; errors contain `ok: false`
and an explanatory `error` string. Diagnostics must not pollute stdout. The
process continues after a malformed request.

One UTF-8 BOM at the start of the complete input is ignored. A BOM on a later
line or a second BOM is part of that request and is not silently stripped.

| op | input fields | result fields |
| --- | --- | --- |
| `parse` | `address` string | `address` canonical string, `family` 4 or 6 |
| `network` | `cidr` string, optional `strict` boolean (default false) | `cidr` canonical string |
| `normalize` | `cidrs` array of strings | `cidrs` minimal canonical array |
| `union` | `left`, `right` CIDR arrays | `cidrs` |
| `intersection` | `left`, `right` CIDR arrays | `cidrs` |
| `difference` | `left`, `right` CIDR arrays | `cidrs` (left minus right) |
| `symmetric_difference` | `left`, `right` CIDR arrays | `cidrs` |
| `range` | `start`, `end` address strings | `cidrs` |
| `contains` | `cidrs` array, `address` string | `value` boolean |

Empty sets are valid. Missing/wrongly typed required fields and unknown
operations are errors. An invalid item rejects its whole request; partial
success is not returned. Parsing does not silently coerce numbers to strings.

## CIDR file CLI

`node bin/ipset.mjs` is the stable source entry. It locates the repository,
incrementally builds the JS CLI, and retains the caller's working directory and
stdin. Build output goes to stderr. `--help` does not require a build.

- `normalize FILE [--strict] [--json]`: emit a minimal CIDR cover, one CIDR per
  line, or JSON `{"cidrs":[...]}`.
- `diff OLD NEW [--strict] [--json]`: emit addresses added (`NEW - OLD`) and
  removed (`OLD - NEW`). JSON is `{"added":[...],"removed":[...]}`; text always
  contains `Added:` and `Removed:` headings followed by their CIDRs.
- No arguments or `jsonl` preserves the JSON Lines protocol above.
- `--` ends option parsing. `-` reads stdin and may occur at most once. Help
  before `--` takes precedence over other arguments; after it, `--help` is a
  literal filename.

File inputs are UTF-8, with an optional initial BOM. Lines may end in LF or CRLF;
surrounding whitespace, blank lines and text after `#` are ignored. Each remaining
line must contain exactly one address or CIDR. Bare addresses are singleton
`/32` or `/128` blocks. Both modes reject invalid addresses, leading-zero IPv4,
zone identifiers and malformed UTF-8. Strict mode additionally rejects CIDR
host bits; the default clears them, so different spellings can compare equal.
UTF-16 input with a BOM is rejected with an instruction to save it as UTF-8.

All inputs are validated before normal output. Only the first error is reported.
Address and encoding errors include the filename and physical line number;
filesystem failures include the filename and cause. Input and parsing failures
leave stdout empty. Output errors return `2`, except an expected closed downstream
pipe (`EPIPE`), which remains quiet and preserves the operation's status. A failing
output device may already have received partial bytes, so consumers must check
the exit status.
Successful output uses LF, IPv4 first, then increasing address order. Empty sets
are valid and equivalent rules compare equal regardless of order or duplication.

Exit status: normalize succeeds with `0`; diff uses `0` for equal sets and `1`
for changes. Usage, input, build, launch and internal failures use `2`. A CI check
must distinguish `1` (valid changes to review) from `2` (unable to compare).
The original JSONL mode retains per-request `ok:false` responses and continues.
File operations only read and compare address sets; they do not apply system rules.

## Validation obligations

- MoonBit unit and public-API tests cover syntax, boundaries, set algebra and
  invariant preservation. A fresh consumer must import and use the package.
- Python `ipaddress` provides an independent reference for parsing, CIDRs,
  collapse, exclusion, and interval summarization.
- Small address universes are explicitly expanded into Python sets for an
  independent model of union/intersection/difference.
- Random cases have fixed seeds and include full-width IPv6, all prefix lengths,
  adjacency, repeated networks, nested networks, empty sets, and family isolation.
- Tests must run on the claimed compiler targets. Unsupported targets must not
  be advertised as verified.
