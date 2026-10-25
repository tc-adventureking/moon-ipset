#!/usr/bin/env python3
"""Run and validate the standard-library MoonBit native/release microbenchmarks.

No performance threshold is asserted. --smoke validates the executable and result
schema on five small cases; omit it to measure the full 60-case matrix.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import subprocess
import sys
import time


ROOT = Path(__file__).resolve().parents[1]
SOURCE_FILES = ["address.mbt", "cidr.mbt", "set.mbt", "bench/main.mbt", "bench/moon.pkg"]
OPERATIONS = {"parse_normalize", "union", "difference", "cidrs_of_difference", "contains_batch"}
PROFILES = {"overlap", "discrete", "fragmented", "mixed"}


def fingerprints() -> dict[str, str]:
    return {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in SOURCE_FILES}


def command_output(command: list[str]) -> str:
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, check=True)
    return result.stdout.strip()


def environment() -> dict[str, object]:
    cpu = "unavailable"
    cpuinfo = Path("/proc/cpuinfo")
    if cpuinfo.exists():
        for line in cpuinfo.read_text().splitlines():
            if line.startswith("model name"):
                cpu = line.split(":", 1)[1].strip()
                break
    operating_system = platform.system()
    release_file = Path("/etc/os-release")
    if release_file.exists():
        for line in release_file.read_text().splitlines():
            if line.startswith("PRETTY_NAME="):
                operating_system = line.split("=", 1)[1].strip('"')
                break
    # `moon version --all` includes installation paths; retain version text only.
    versions = [line.split(" /", 1)[0] for line in command_output(["moon", "version", "--all"]).splitlines()
                if line.startswith(("moon ", "moonc ", "moonrun "))]
    compiler = command_output([os.environ.get("MOON_CC", "cc"), "--version"]).splitlines()[0]
    return {
        "os": operating_system,
        "kernel": platform.release(),
        "architecture": platform.machine(),
        "cpu_model": cpu,
        "python": platform.python_version(),
        "moonbit": versions,
        "c_compiler": compiler,
        "backend": "native",
        "build": "release",
    }


def validate(rows: list[dict[str, object]], smoke: bool) -> None:
    sizes = {100} if smoke else {100, 1000, 10000}
    profiles = {"mixed"} if smoke else PROFILES
    expected = {(profile, size, op) for profile in profiles for size in sizes for op in OPERATIONS}
    seen = set()
    for row in rows:
        key = (row["profile"], row["input_count_per_operand"], row["operation"])
        if key not in expected or key in seen:
            raise ValueError(f"unexpected or repeated benchmark: {key}")
        seen.add(key)
        if row["seed"] != 0x5EED2026 or row["unit"] != "microseconds_per_iteration":
            raise ValueError(f"invalid seed or unit: {key}")
        n = row["input_count_per_operand"]
        expected_intervals = 16 if row["profile"] == "overlap" else n
        if row["left_intervals"] != expected_intervals or row["right_intervals"] != expected_intervals:
            raise ValueError(f"unexpected fixture interval count: {key}")
        if row["operation"] == "contains_batch":
            if row["queries_per_iteration"] != (128 if smoke else 1024):
                raise ValueError(f"wrong query batch size: {key}")
            if not 0 <= row["hits"] <= row["queries_per_iteration"]:
                raise ValueError(f"invalid membership result: {key}")
            if row["output_intervals"] is not None or row["output_cidrs"] is not None:
                raise ValueError(f"membership is not a set result: {key}")
        else:
            output_intervals = expected_intervals
            if row["operation"] == "union" and row["profile"] == "discrete":
                output_intervals = n * 2
            elif row["operation"] in {"difference", "cidrs_of_difference"} and row["profile"] in {"fragmented", "mixed"}:
                output_intervals = n * 2
            if row["output_intervals"] != output_intervals or row["output_cidrs"] != output_intervals:
                raise ValueError(f"unexpected benchmark output shape: {key}")
        summaries = row["summaries"]
        if len(summaries) != 1:
            raise ValueError(f"expected exactly one summary: {key}")
        summary = summaries[0]
        if summary["runs"] != (2 if smoke else 5) or summary["batch_size"] < 1:
            raise ValueError(f"invalid sampling metadata: {key}")
        for name in ("min", "max", "mean", "median", "std_dev"):
            value = summary[name]
            if not isinstance(value, (int, float)) or not math.isfinite(value) or value < 0:
                raise ValueError(f"invalid {name}: {key}")
        if not summary["min"] <= summary["median"] <= summary["max"]:
            raise ValueError(f"inconsistent timing distribution: {key}")
    if seen != expected:
        raise ValueError(f"missing cases: {sorted(expected - seen)}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--smoke", action="store_true")
    parser.add_argument("--target-dir", default="_build/bench")
    parser.add_argument("--output", type=Path, default=Path("bench/results/native.json"))
    args = parser.parse_args()
    before = fingerprints()
    metadata = environment()
    command = ["moon", "run", "bench", "--target", "native", "--release", "--deny-warn",
               "--target-dir", args.target_dir]
    if args.smoke:
        command += ["--", "--smoke"]
    started = time.monotonic()
    run = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, timeout=300)
    if run.returncode:
        sys.stderr.write(run.stderr)
        return run.returncode
    rows = [json.loads(line) for line in run.stdout.splitlines() if line.strip()]
    validate(rows, args.smoke)
    after = fingerprints()
    if before != after:
        raise RuntimeError("benchmark sources changed during the run; do not publish these timings")
    report = {
        "schema_version": 1,
        "measured_at_utc": datetime.now(timezone.utc).isoformat(),
        "mode": "smoke" if args.smoke else "full",
        "environment": metadata,
        "source_sha256": before,
        "method": {
            "runner": "moonbitlang/core/bench.Bench",
            "samples_per_case": 2 if args.smoke else 5,
            "fixture_seed": 0x5EED2026,
            "benchmark_calls": len(rows),
            "unit": "microseconds per iteration; contains iteration is one query batch",
            "scope": "single-host synthetic microbenchmarks; no cross-library comparison",
        },
        "elapsed_seconds_including_build": round(time.monotonic() - started, 3),
        "cases": rows,
    }
    output = args.output if args.output.is_absolute() else ROOT / args.output
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps({"status": "ok", "mode": report["mode"], "cases": len(rows)}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"benchmark failed: {error}", file=sys.stderr)
        raise SystemExit(1)
