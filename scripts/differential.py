#!/usr/bin/env python3
"""Differential checks for the Moon IPSet JSON-lines CLI (Python 3.10+).

Example:
  python3 scripts/differential.py --command './moon-ipset' --report report.json

The command is split into an argv vector; it is never executed through a shell.
One process receives all requests. Stdout must contain one JSON object per request.
The oracle uses Python's ipaddress library, with a separate bounded point-set
oracle for small-space cases. It does not implement the production interval
algorithm. No network access or third-party Python packages are required.
"""

from __future__ import annotations

import argparse
from collections import Counter
from dataclasses import dataclass
import ipaddress
import json
from pathlib import Path
import platform
import random
import re
import shlex
import subprocess
import sys
import time
from typing import Any, Iterable

Address = ipaddress.IPv4Address | ipaddress.IPv6Address
Network = ipaddress.IPv4Network | ipaddress.IPv6Network
DEFAULT_SEED = 0x6D6F6F6E20261026


def format_address(address: Address, *, expanded: bool = False) -> str:
    """Format IPv6 as pure hex, independent of Python's mapped-address policy.

    Python releases may choose mixed dotted output in str()/compressed. The
    project contract deliberately chooses RFC 5952 section 4 hex formatting,
    including for mapped addresses, so derive the text from the numeric value.
    """
    if address.version == 4:
        return str(address)
    value = int(address)
    groups = [(value >> shift) & 0xFFFF for shift in range(112, -1, -16)]
    if expanded:
        return ":".join(f"{group:04x}" for group in groups)
    best_start, best_size = -1, 0
    index = 0
    while index < 8:
        if groups[index] != 0:
            index += 1
            continue
        end = index
        while end < 8 and groups[end] == 0:
            end += 1
        if end - index >= 2 and end - index > best_size:
            best_start, best_size = index, end - index
        index = end
    text = [f"{group:x}" for group in groups]
    if best_start < 0:
        return ":".join(text)
    return ":".join(text[:best_start]) + "::" + ":".join(text[best_start + best_size:])


def format_network(network: Network) -> str:
    return f"{format_address(network.network_address)}/{network.prefixlen}"


def check_text_formatter() -> None:
    examples = {
        "::": "::",
        "::1": "::1",
        "::ffff:192.0.2.1": "::ffff:c000:201",
        "::ffff:0.0.0.0": "::ffff:0:0",
        "::ffff:255.255.255.255": "::ffff:ffff:ffff",
        "1:0:0:2:0:0:3:4": "1::2:0:0:3:4",
        "1:2:3:4:5:6:0:8": "1:2:3:4:5:6:0:8",
    }
    for source, expected in examples.items():
        actual = format_address(ipaddress.ip_address(source))
        if actual != expected:
            raise AssertionError(f"hex formatter: {source}: expected {expected}, got {actual}")
    mapped_network = ipaddress.ip_network("::ffff:192.0.2.129/120", strict=False)
    if format_network(mapped_network) != "::ffff:c000:200/120":
        raise AssertionError("mapped network formatter differs")


@dataclass(frozen=True)
class Case:
    category: str
    request: dict[str, Any]
    expected: dict[str, Any]


def parse_address(text: str) -> Address:
    if not isinstance(text, str) or not text or "%" in text:
        raise ValueError("invalid address")
    if any(char.isspace() for char in text):
        raise ValueError("whitespace is not permitted")
    return ipaddress.ip_address(text)


def parse_network(text: str, strict: bool = False) -> Network:
    if not isinstance(text, str) or text.count("/") != 1:
        raise ValueError("CIDR requires one slash")
    address, prefix = text.split("/")
    parse_address(address)
    if re.fullmatch(r"[0-9]+", prefix) is None:
        raise ValueError("prefix must use decimal digits")
    if len(prefix) > 1 and prefix[0] == "0":
        raise ValueError("prefix must not have leading zeros")
    return ipaddress.ip_network(text, strict=strict)


def collapsed(networks: Iterable[Network]) -> list[Network]:
    items = list(networks)
    result: list[Network] = []
    for version in (4, 6):
        result.extend(
            ipaddress.collapse_addresses(net for net in items if net.version == version)
        )
    return sorted(result, key=lambda net: (net.version, int(net.network_address), net.prefixlen))


def canonical(networks: Iterable[Network]) -> list[str]:
    return [format_network(net) for net in collapsed(networks)]


def intersection(left: list[Network], right: list[Network]) -> list[Network]:
    # CIDR blocks of the same family either do not overlap or one contains the other.
    return collapsed(
        a if a.prefixlen >= b.prefixlen else b
        for a in left
        for b in right
        if a.version == b.version and a.overlaps(b)
    )


def difference(left: list[Network], right: list[Network]) -> list[Network]:
    remaining = collapsed(left)
    for excluded in collapsed(right):
        next_remaining: list[Network] = []
        for net in remaining:
            if net.version != excluded.version or not net.overlaps(excluded):
                next_remaining.append(net)
            elif net.subnet_of(excluded):
                continue
            else:
                next_remaining.extend(net.address_exclude(excluded))
        remaining = next_remaining
    return collapsed(remaining)


def oracle(request: dict[str, Any]) -> dict[str, Any]:
    try:
        op = request["op"]
        if op == "parse":
            addr = parse_address(request["address"])
            return {"ok": True, "address": format_address(addr), "family": addr.version}
        if op == "network":
            strict = request.get("strict", False)
            if not isinstance(strict, bool):
                raise ValueError("strict must be boolean")
            return {"ok": True, "cidr": format_network(parse_network(request["cidr"], strict))}
        if op == "range":
            start = parse_address(request["start"])
            end = parse_address(request["end"])
            return {"ok": True, "cidrs": canonical(ipaddress.summarize_address_range(start, end))}
        if op in ("normalize", "contains"):
            values = request["cidrs"]
            if not isinstance(values, list):
                raise ValueError("cidrs must be an array")
            nets = [parse_network(value) for value in values]
            if op == "normalize":
                return {"ok": True, "cidrs": canonical(nets)}
            addr = parse_address(request["address"])
            return {"ok": True, "value": any(addr.version == net.version and addr in net for net in nets)}
        if op in ("union", "intersection", "difference", "symmetric_difference"):
            if not isinstance(request["left"], list) or not isinstance(request["right"], list):
                raise ValueError("operands must be arrays")
            left = [parse_network(value) for value in request["left"]]
            right = [parse_network(value) for value in request["right"]]
            if op == "union":
                result = collapsed(left + right)
            elif op == "intersection":
                result = intersection(left, right)
            elif op == "difference":
                result = difference(left, right)
            else:
                result = collapsed(difference(left, right) + difference(right, left))
            return {"ok": True, "cidrs": canonical(result)}
        raise ValueError("unknown operation")
    except (KeyError, TypeError, ValueError, AttributeError):
        # Error wording is deliberately not part of the conformance contract.
        return {"ok": False}


def build_cases(seed: int, rounds: int) -> list[Case]:
    check_text_formatter()
    rng = random.Random(seed)
    cases: list[Case] = []

    def add(category: str, op: str, **arguments: Any) -> None:
        request = {"op": op, **arguments}
        cases.append(Case(category, request, oracle(request)))

    valid_addresses = [
        "0.0.0.0", "0.0.0.1", "127.255.255.255", "128.0.0.0",
        "192.0.2.1", "255.255.255.254", "255.255.255.255",
        "::", "::1", "::ffff", "1::", "2001:db8::1", "2001:DB8:0:0:1:0:0:1",
        "0:0:0:0:0:0:0:0", "1:0:0:2:0:0:3:4", "1:2:3:4:5:6:7:8",
        "ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff", "::ffff:192.0.2.1",
        "1:2:3:4:5:6:192.0.2.1", "::192.0.2.1", "2001:db8::192.0.2.1",
    ]
    invalid_addresses = [
        "", " ", " 192.0.2.1", "192.0.2.1 ", "192.0.2.1\n", "192.0.2.\t1",
        "01.2.3.4", "1.02.3.4", "1.2.3.004", "256.0.0.1", "-1.0.0.1",
        "+1.0.0.1", "1.2.3", "1.2.3.4.5", "1..3.4", "1.2.3.4/32", "0x7f000001",
        "localhost", "192.0.2.1:80", "[::1]", "[::1]:80", "fe80::1%eth0", "::1%1",
        ":", ":::1", "1:::2", "1::2::3", "1:2:3:4:5:6:7", "1:2:3:4:5:6:7:8:9",
        "1:2:3:4:5:6:7:8::", "::1:2:3:4:5:6:7:8", "12345::", "g::", "+1::",
        "1_0::", "::ffff:192.168.001.1", "::ffff:256.0.0.1", "1.2.3.4::",
        "1:2:3:4:5:192.0.2.1", "1:2:3:4:5:6:7:192.0.2.1", "::\n", "\u00a0::1",
    ]
    for value in valid_addresses:
        add("parse.fixed.valid", "parse", address=value)
    for value in invalid_addresses:
        add("parse.fixed.invalid", "parse", address=value)

    for version, width, cls in ((4, 32, ipaddress.IPv4Address), (6, 128, ipaddress.IPv6Address)):
        maximum = (1 << width) - 1
        for prefix in range(width + 1):
            address = cls(rng.getrandbits(width))
            raw = f"{format_address(address)}/{prefix}"
            normalized = format_network(ipaddress.ip_network(raw, strict=False))
            add("network.every_prefix.default", "network", cidr=raw)
            add("network.every_prefix.strict", "network", cidr=raw, strict=True)
            add("network.every_prefix.canonical", "network", cidr=normalized, strict=True)
            add("network.every_prefix.maximum", "network", cidr=f"{format_address(cls(maximum))}/{prefix}", strict=False)
        add("range.full_space", "range", start=format_address(cls(0)), end=format_address(cls(maximum)))
        add("range.maximum_singleton", "range", start=format_address(cls(maximum)), end=format_address(cls(maximum)))
        add("range.maximum_pair", "range", start=format_address(cls(maximum - 1)), end=format_address(cls(maximum)))
        add("range.reversed", "range", start=format_address(cls(maximum)), end=format_address(cls(0)))
        add("difference.full_minus_max", "difference", left=[f"{format_address(cls(0))}/0"], right=[f"{format_address(cls(maximum))}/{width}"])
        add("difference.full_minus_zero", "difference", left=[f"{format_address(cls(0))}/0"], right=[f"{format_address(cls(0))}/{width}"])
        add("difference.full_minus_full", "difference", left=[f"{format_address(cls(0))}/0"], right=[f"{format_address(cls(0))}/0"])

    invalid_cidrs = [
        "192.0.2.1", "192.0.2.1/", "192.0.2.1/33", "192.0.2.1/-1", "192.0.2.1/+24",
        "192.0.2.1/024", "192.0.2.1/00", "192.0.2.1/ 24", "192.0.2.1/24 ",
        "192.0.2.1/255.255.255.0", "192.0.2.1/0.0.0.255", "192.0.2.1/24/24",
        "256.0.0.0/24", "::/129", "::/-1", "::/+64", "::/064", "::/000", "::/",
        "::/64\n", "::/６４", "fe80::1%eth0/64", "1::2::3/64", "[::1]/128",
    ]
    for value in invalid_cidrs:
        add("network.fixed.invalid", "network", cidr=value)
        add("normalize.invalid_member", "normalize", cidrs=["192.0.2.0/24", value])
    for value in ("192.0.2.1/24", "2001:db8::1/64"):
        add("network.strict_host_bits", "network", cidr=value, strict=True)
        add("network.loose_host_bits", "network", cidr=value, strict=False)
    add("range.family_mismatch", "range", start="0.0.0.0", end="::1")
    add("range.invalid_endpoint", "range", start="::", end="::1%eth0")

    fixed_sets = [
        [], ["0.0.0.0/0"], ["::/0"], ["0.0.0.0/0", "::/0"],
        ["192.0.2.0/25", "192.0.2.128/25"],
        ["255.255.255.255/32", "128.0.0.0/1", "0.0.0.0/1"],
        ["::/1", "8000::/1", "::1/128"],
        ["2001:db8::1/64", "2001:db8::/65", "2001:DB8::/64", "192.0.2.1/24"],
        ["::ffff:192.0.2.0/120", "192.0.2.0/24"],
    ]
    operations = ("union", "intersection", "difference", "symmetric_difference")
    for left in fixed_sets:
        add("normalize.fixed", "normalize", cidrs=left)
        for address in ("0.0.0.0", "255.255.255.255", "192.0.2.1", "::", "::ffff:192.0.2.1"):
            add("contains.fixed", "contains", cidrs=left, address=address)
        for right in fixed_sets:
            for op in operations:
                add("algebra.fixed", op, left=left, right=right)

    def random_network() -> str:
        width, cls = rng.choice(((32, ipaddress.IPv4Address), (128, ipaddress.IPv6Address)))
        return f"{format_address(cls(rng.getrandbits(width)))}/{rng.randrange(width + 1)}"

    for _ in range(rounds):
        left = [random_network() for _ in range(rng.randrange(7))]
        right = [random_network() for _ in range(rng.randrange(7))]
        add("normalize.random_full_width", "normalize", cidrs=left + left[:1])
        for op in operations:
            add("algebra.random_full_width", op, left=left, right=right)
        for width, cls in ((32, ipaddress.IPv4Address), (128, ipaddress.IPv6Address)):
            value = rng.getrandbits(width)
            add("parse.random_full_width", "parse", address=format_address(cls(value)))
            if width == 128:
                add("parse.random_expanded", "parse", address=format_address(cls(value), expanded=True).upper())
            add("contains.random_full_width", "contains", cidrs=left, address=format_address(cls(value)))
            lo, hi = sorted((rng.getrandbits(width), rng.getrandbits(width)))
            add("range.random_full_width", "range", start=format_address(cls(lo)), end=format_address(cls(hi)))

    # Separate oracle: explicit membership within a 64-address block. This is
    # bounded irrespective of address family, so an IPv6 /0 is never expanded.
    for _ in range(max(12, rounds // 2)):
        for width, cls in ((32, ipaddress.IPv4Address), (128, ipaddress.IPv6Address)):
            base = (rng.getrandbits(width) >> 6) << 6
            left_points = {offset for offset in range(64) if rng.randrange(3) == 0}
            right_points = {offset for offset in range(64) if rng.randrange(3) == 0}

            def point_cidrs(points: set[int]) -> list[str]:
                return canonical(ipaddress.ip_network(f"{format_address(cls(base + point))}/{width}") for point in sorted(points))

            left = point_cidrs(left_points)
            right = point_cidrs(right_points)
            # Duplicate and reorder inputs to check normalization separately.
            shuffled = left + left[:2]
            rng.shuffle(shuffled)
            add("normalize.small_space", "normalize", cidrs=shuffled)
            results = {
                "union": left_points | right_points,
                "intersection": left_points & right_points,
                "difference": left_points - right_points,
                "symmetric_difference": left_points ^ right_points,
            }
            for op, points in results.items():
                request = {"op": op, "left": left, "right": right}
                expected = {"ok": True, "cidrs": point_cidrs(points)}
                # Verify the library-backed oracle against independent point sets
                # before relying on either to check production output.
                if oracle(request) != expected:
                    raise AssertionError(f"Python oracle disagreement: {request!r}")
                cases.append(Case("algebra.small_space", request, expected))
            for offset in (0, 63, rng.randrange(64)):
                cases.append(Case(
                    "contains.small_space",
                    {"op": "contains", "cidrs": left, "address": format_address(cls(base + offset))},
                    {"ok": True, "value": offset in left_points},
                ))
    return cases


def compare_response(expected: dict[str, Any], actual: Any) -> str | None:
    if not isinstance(actual, dict):
        return "response must be a JSON object"
    if actual.get("ok") is not expected["ok"]:
        return "ok flag differs"
    if not expected["ok"]:
        if not isinstance(actual.get("error"), str) or not actual["error"]:
            return "failure response requires a non-empty error string"
        return None
    for key, value in expected.items():
        if key not in actual or type(actual[key]) is not type(value) or actual[key] != value:
            return f"field {key!r} differs"
    return None


def write_report(report: dict[str, Any], destination: str | None) -> None:
    rendered = json.dumps(report, ensure_ascii=False, indent=2)
    if destination:
        path = Path(destination)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(rendered + "\n", encoding="utf-8")
    print(rendered)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--command", required=True, help="CLI launch command, e.g. './moon-ipset' or 'node app.js'")
    parser.add_argument("--report", help="write the same JSON summary to this file")
    parser.add_argument("--seed", type=lambda text: int(text, 0), default=DEFAULT_SEED)
    parser.add_argument("--rounds", type=int, default=120, help="full-width random rounds (default: 120, maximum: 500)")
    parser.add_argument("--timeout", type=float, default=120.0, help="whole-process timeout in seconds")
    args = parser.parse_args()
    if not 1 <= args.rounds <= 500:
        parser.error("--rounds must be in 1..500")
    if not 0 < args.timeout <= 3600:
        parser.error("--timeout must be in (0, 3600]")
    command = shlex.split(args.command)
    if not command:
        parser.error("--command must not be empty")
    started = time.monotonic()
    cases = build_cases(args.seed, args.rounds)
    payload = "".join(json.dumps(case.request, separators=(",", ":")) + "\n" for case in cases)
    report: dict[str, Any] = {
        "status": "failed",
        "python": platform.python_version(),
        "seed": args.seed,
        "rounds": args.rounds,
        "requests": len(cases),
        "categories": dict(sorted(Counter(case.category for case in cases).items())),
        "checked": 0,
    }
    try:
        result = subprocess.run(
            command, input=payload, text=True, encoding="utf-8", errors="strict",
            capture_output=True, timeout=args.timeout, check=False,
        )
    except (OSError, subprocess.TimeoutExpired, UnicodeError) as exc:
        report["failure"] = {"reason": type(exc).__name__, "message": str(exc)[:2000]}
        report["elapsed_seconds"] = round(time.monotonic() - started, 3)
        write_report(report, args.report)
        return 1
    report["returncode"] = result.returncode
    if result.stderr:
        report["stderr_excerpt"] = result.stderr[:2000]
    lines = result.stdout.splitlines()
    report["responses"] = len(lines)
    for index, (case, line) in enumerate(zip(cases, lines)):
        try:
            actual = json.loads(line)
        except json.JSONDecodeError as exc:
            report["failure"] = {
                "index": index, "category": case.category, "request": case.request,
                "expected": case.expected, "actual_line": line[:2000], "reason": str(exc),
            }
            break
        reason = compare_response(case.expected, actual)
        if reason is not None:
            report["failure"] = {
                "index": index, "category": case.category, "request": case.request,
                "expected": case.expected, "actual": actual, "reason": reason,
            }
            break
        report["checked"] += 1
    if "failure" not in report and len(lines) != len(cases):
        report["failure"] = {"reason": "response count differs", "expected": len(cases), "actual": len(lines)}
    if "failure" not in report and result.returncode != 0:
        report["failure"] = {"reason": "CLI exited unsuccessfully", "returncode": result.returncode}
    if "failure" not in report:
        report["status"] = "passed"
    report["elapsed_seconds"] = round(time.monotonic() - started, 3)
    write_report(report, args.report)
    return 0 if report["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
