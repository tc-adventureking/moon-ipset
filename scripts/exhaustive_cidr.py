#!/usr/bin/env python3
"""Exhaustively verify minimal CIDR covers in a bounded aligned universe.

Default: all 65,536 subsets of 16 addresses, in each of IPv4 and IPv6.
Each request normalizes the subset's individual /32 or /128 host routes.
The independent oracle recursively partitions a binary prefix tree: a fully
present block becomes one prefix; a partial block is split into its children.
It does not use the production greedy interval algorithm or collapse_addresses.

Examples:
  python3 scripts/exhaustive_cidr.py --command './json-cli' --report exhaustive.json
  python3 scripts/exhaustive_cidr.py --self-check --bits 3

Python ipaddress is used only for formatting; --self-check additionally compares
the tree oracle against collapse_addresses, without invoking the project CLI.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import ipaddress
import json
from pathlib import Path
import platform
import shlex
import subprocess
import sys
import time
from typing import Any


def format_address(address: ipaddress.IPv4Address | ipaddress.IPv6Address) -> str:
    """Use the project's pure-hex policy even if Python str() chooses mixed form."""
    if address.version == 4:
        return str(address)
    value = int(address)
    groups = [(value >> shift) & 0xFFFF for shift in range(112, -1, -16)]
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


def check_text_formatter() -> None:
    for source, expected in {
        "::": "::", "::1": "::1",
        "::ffff:192.0.2.1": "::ffff:c000:201",
        "::ffff:0.0.0.0": "::ffff:0:0",
        "::ffff:255.255.255.255": "::ffff:ffff:ffff",
        "1:0:0:2:0:0:3:4": "1::2:0:0:3:4",
        "1:2:3:4:5:6:0:8": "1:2:3:4:5:6:0:8",
    }.items():
        actual = format_address(ipaddress.ip_address(source))
        if actual != expected:
            raise AssertionError(f"hex formatter: {source}: expected {expected}, got {actual}")


def address_type(family: int) -> type[ipaddress.IPv4Address] | type[ipaddress.IPv6Address]:
    return ipaddress.IPv4Address if family == 4 else ipaddress.IPv6Address


def universe_base(family: int, bits: int) -> int:
    # Use the final aligned block, exercising high-bit and maximum-address cases.
    width = 32 if family == 4 else 128
    return (1 << width) - (1 << bits)


def singleton_inputs(mask: int, family: int, bits: int) -> list[str]:
    width = 32 if family == 4 else 128
    cls = address_type(family)
    base = universe_base(family, bits)
    return [f"{format_address(cls(base + offset))}/{width}" for offset in range(1 << bits) if mask & (1 << offset)]


def trie_cover(mask: int, family: int, bits: int) -> list[str]:
    """Return the unique smallest CIDR partition by recursive full-block tests.

    Nodes are aligned dyadic address blocks. If every leaf under a node is
    present, that node's prefix is sufficient and no smaller cover is possible.
    If some leaves are absent, no covering prefix may span both children;
    consequently the two recursive optimal covers form the optimal cover.
    Left-first traversal gives increasing network-address order.
    """
    width = 32 if family == 4 else 128
    cls = address_type(family)
    base = universe_base(family, bits)
    result: list[str] = []

    def visit(offset: int, log_size: int) -> None:
        leaf_count = 1 << log_size
        block_mask = ((1 << leaf_count) - 1) << offset
        selected = mask & block_mask
        if selected == 0:
            return
        if selected == block_mask:
            result.append(f"{format_address(cls(base + offset))}/{width - log_size}")
            return
        half = leaf_count // 2
        visit(offset, log_size - 1)
        visit(offset + half, log_size - 1)

    visit(0, bits)
    return result


def emit_report(report: dict[str, Any], destination: str | None, started: float) -> None:
    report["elapsed_seconds"] = round(time.monotonic() - started, 3)
    rendered = json.dumps(report, ensure_ascii=False, indent=2)
    if destination:
        path = Path(destination)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(rendered + "\n", encoding="utf-8")
    print(rendered)


def main() -> int:
    check_text_formatter()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--command", help="CLI argv as a quoted string; no shell expansion")
    parser.add_argument("--report", help="write the JSON result to this path")
    parser.add_argument("--bits", type=int, default=4, help="log2 of universe size, 0..4 (default: 4)")
    parser.add_argument("--family", choices=("both", "4", "6"), default="both")
    parser.add_argument("--batch-size", type=int, default=2048, help="requests per subprocess, 1..8192")
    parser.add_argument("--timeout", type=float, default=60.0, help="timeout for each subprocess in seconds")
    parser.add_argument("--self-check", action="store_true", help="check only the trie oracle against Python collapse_addresses")
    args = parser.parse_args()
    if not 0 <= args.bits <= 4:
        parser.error("--bits must be in 0..4; larger exhaustive universes are intentionally prohibited")
    if not 1 <= args.batch_size <= 8192:
        parser.error("--batch-size must be in 1..8192")
    if not 0 < args.timeout <= 3600:
        parser.error("--timeout must be in (0, 3600]")
    if not args.self_check and not args.command:
        parser.error("--command is required unless --self-check is selected")
    command = shlex.split(args.command) if args.command else []
    if not args.self_check and not command:
        parser.error("--command must not be empty")
    families = (4, 6) if args.family == "both" else (int(args.family),)
    subset_count = 1 << (1 << args.bits)
    started = time.monotonic()
    report: dict[str, Any] = {
        "status": "failed",
        "mode": "oracle_self_check" if args.self_check else "cli_exhaustive",
        "oracle": "recursive binary prefix tree",
        "environment": {
            "python": platform.python_version(),
            "platform": platform.platform(),
            "started_utc": datetime.now(timezone.utc).isoformat(),
        },
        "bits": args.bits,
        "addresses_per_universe": 1 << args.bits,
        "families": list(families),
        "subsets_per_family": subset_count,
        "planned_checks": subset_count * len(families),
        "checked": 0,
        "checked_by_family": {str(family): 0 for family in families},
        "subprocesses": 0,
        "batch_size": args.batch_size,
    }

    def fail(details: dict[str, Any]) -> int:
        report["failure"] = details
        emit_report(report, args.report, started)
        return 1

    for family in families:
        if args.self_check:
            for mask in range(subset_count):
                inputs = singleton_inputs(mask, family, args.bits)
                expected = trie_cover(mask, family, args.bits)
                reference = [f"{format_address(net.network_address)}/{net.prefixlen}"
                             for net in ipaddress.collapse_addresses(ipaddress.ip_network(text) for text in inputs)]
                if reference != expected:
                    return fail({"family": family, "mask": mask, "input": inputs,
                                 "expected_trie": expected, "actual_python": reference})
                report["checked"] += 1
                report["checked_by_family"][str(family)] += 1
            continue

        for first in range(0, subset_count, args.batch_size):
            stop = min(first + args.batch_size, subset_count)
            inputs = [singleton_inputs(mask, family, args.bits) for mask in range(first, stop)]
            payload = "".join(json.dumps({"op": "normalize", "cidrs": item}, separators=(",", ":")) + "\n" for item in inputs)
            report["subprocesses"] += 1
            try:
                result = subprocess.run(command, input=payload, text=True, encoding="utf-8",
                                        errors="strict", capture_output=True, timeout=args.timeout, check=False)
            except (OSError, subprocess.TimeoutExpired, UnicodeError) as exc:
                return fail({"family": family, "batch_start_mask": first,
                             "reason": type(exc).__name__, "message": str(exc)[:2000]})
            lines = result.stdout.splitlines()
            for offset, line in enumerate(lines[:len(inputs)]):
                mask = first + offset
                expected = trie_cover(mask, family, args.bits)
                try:
                    actual = json.loads(line)
                except json.JSONDecodeError as exc:
                    return fail({"family": family, "mask": mask, "input": inputs[offset],
                                 "expected": {"ok": True, "cidrs": expected},
                                 "actual_line": line[:2000], "reason": str(exc)})
                if not isinstance(actual, dict) or actual.get("ok") is not True or actual.get("cidrs") != expected:
                    return fail({"family": family, "mask": mask, "input": inputs[offset],
                                 "expected": {"ok": True, "cidrs": expected}, "actual": actual,
                                 "reason": "minimal canonical CIDR cover differs"})
                report["checked"] += 1
                report["checked_by_family"][str(family)] += 1
            if len(lines) != len(inputs):
                missing = first + min(len(lines), len(inputs) - 1)
                return fail({"family": family, "batch_start_mask": first,
                             "mask": missing, "input": singleton_inputs(missing, family, args.bits),
                             "expected": {"ok": True, "cidrs": trie_cover(missing, family, args.bits)},
                             "expected_response_count": len(inputs), "actual_response_count": len(lines),
                             "reason": "one response is required for each request",
                             "stderr_excerpt": result.stderr[:2000]})
            if result.returncode != 0:
                return fail({"family": family, "batch_start_mask": first,
                             "reason": "CLI exited unsuccessfully", "returncode": result.returncode,
                             "stderr_excerpt": result.stderr[:2000]})

    report["status"] = "oracle_self_check_passed" if args.self_check else "passed"
    emit_report(report, args.report, started)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
