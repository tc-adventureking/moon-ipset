# Behavioral specification

This is the intended public behavior. Test results and release status are
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
