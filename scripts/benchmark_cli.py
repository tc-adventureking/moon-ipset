#!/usr/bin/env python3
"""Measure a built Node CLI on deterministic duplicate-heavy dual-stack files.

Each timed sample starts a fresh process and includes input reads, parsing,
normalization/diff, JSON serialization, stdout pipe transfer, and process exit.
Fixture generation and Python oracle validation are outside the timed interval.
No performance threshold is asserted and no compiler is invoked.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import ipaddress
import json
from pathlib import Path
import platform
import random
import shlex
import shutil
import statistics
import subprocess
import sys
import tempfile
import time


SEED = 20261026


def bank(offset: int) -> list[str]:
    entries = []
    for version, origin, width in [(4, '10.64.0.0', 32), (6, '2001:db8::', 128)]:
        base = int(ipaddress.ip_address(origin))
        address_type = ipaddress.IPv4Address if version == 4 else ipaddress.IPv6Address
        for index in range(offset, offset + 1024):
            prefix = width if index % 3 == 0 else width - 1
            value = base + index * 4
            if index % 5 == 0:
                text = str(address_type(value))
            else:
                if prefix != width and index % 7 == 0:
                    value += 1  # Exercise default host-bit masking as well.
                text = f'{address_type(value)}/{prefix}'
            entries.append(text.upper() if version == 6 and index % 2 == 0 else text)
    random.Random(SEED + offset).shuffle(entries)
    return entries


def point_sets(entries: list[str]) -> dict[int, set[int]]:
    result: dict[int, set[int]] = {4: set(), 6: set()}
    for entry in entries:
        network = ipaddress.ip_network(entry, strict=False)
        result[network.version].update(int(address) for address in network)
    return result


def cover(points: dict[int, set[int]]) -> list[str]:
    result = []
    for version, address_type in [(4, ipaddress.IPv4Address), (6, ipaddress.IPv6Address)]:
        result.extend(str(network) for network in ipaddress.collapse_addresses(
            address_type(value) for value in sorted(points[version])))
    return result


def write_fixture(path: Path, entries: list[str], rows: int) -> dict[str, object]:
    cycles, remainder = divmod(rows, len(entries))
    content = (('\n'.join(entries) + '\n') * cycles +
               ''.join(entry + '\n' for entry in entries[:remainder])).encode()
    path.write_bytes(content)
    return {'rows': rows, 'bytes': len(content), 'sha256': hashlib.sha256(content).hexdigest()}


def summarize(values: list[float | int]) -> dict[str, object]:
    median = statistics.median(values)
    return {'samples': values, 'median': median, 'min': min(values), 'max': max(values),
            'population_stdev': statistics.pstdev(values),
            'relative_range_percent': (max(values) - min(values)) / median * 100 if median else 0}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--command', required=True, help='built CLI command, e.g. "node /path/to/ipset.mjs"')
    parser.add_argument('--label', default='baseline')
    parser.add_argument('--sizes', nargs='+', type=int, default=[10000, 100000, 1000000])
    parser.add_argument('--operations', nargs='+', choices=['normalize', 'diff'], default=['normalize', 'diff'])
    parser.add_argument('--runs', type=int, default=5)
    parser.add_argument('--warmup', type=int, default=1)
    parser.add_argument('--timeout', type=float, default=120)
    parser.add_argument('--fixtures', type=Path)
    parser.add_argument('--output', type=Path, default=Path('work/cli-benchmark.json'))
    args = parser.parse_args()
    if min(args.sizes) < 2048 or args.runs < 1 or args.warmup < 0 or args.timeout <= 0:
        parser.error('sizes must be >= 2048; runs/timeout positive; warmup nonnegative')
    command = shlex.split(args.command)
    if not command:
        parser.error('empty --command')
    command[0] = shutil.which(command[0]) or str(Path(command[0]).resolve())
    for index in range(1, len(command)):
        if Path(command[index]).is_file():
            command[index] = str(Path(command[index]).resolve())
    args.output.parent.mkdir(parents=True, exist_ok=True)
    gnu_time = Path('/usr/bin/time') if platform.system() == 'Linux' else None
    if gnu_time is not None and not gnu_time.is_file():
        gnu_time = None
    fingerprint_paths = [Path(item) for item in command[1:] if Path(item).is_file()]
    for entry in fingerprint_paths.copy():
        for name in ['ipset.js', 'runtime.mjs', 'package.json']:
            sibling = entry.parent / name
            if sibling.is_file() and sibling not in fingerprint_paths:
                fingerprint_paths.append(sibling)
    cpu = 'unavailable'
    if Path('/proc/cpuinfo').is_file():
        cpu = next((line.split(':', 1)[1].strip() for line in Path('/proc/cpuinfo').read_text().splitlines()
                    if line.startswith('model name')), cpu)
    report: dict[str, object] = {
        'status': 'running', 'label': args.label, 'timestamp_utc': datetime.now(timezone.utc).isoformat(),
        'environment': {'system': platform.system(), 'kernel': platform.release(),
                        'architecture': platform.machine(), 'cpu': cpu,
                        'node': subprocess.run([command[0], '--version'], capture_output=True, text=True, check=True).stdout.strip()},
        'fingerprints': {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in fingerprint_paths},
        'method': {'runs': args.runs, 'warmup_runs_per_case': args.warmup, 'timeout_seconds': args.timeout,
                   'fresh_process_per_sample': True, 'clock': 'Python perf_counter wall time',
                   'includes': 'process start/exit, file reads, all CLI work, stdout pipe transfer',
                   'excludes': 'fixture generation, compiler, Python result validation',
                   'rss': 'GNU time %M KiB, separate invocation for every child' if gnu_time else 'unavailable',
                   'fixture': 'seeded shuffled bank of 2048 separated dual-stack entries, repeated to requested rows',
                   'seed': SEED, 'output': 'JSON; semantic set size remains bounded as duplicate rows increase'},
        'cases': [],
    }
    old_entries, new_entries = bank(0), bank(512)
    old_points, new_points = point_sets(old_entries), point_sets(new_entries)
    expected = {
        'normalize': {'cidrs': cover(new_points)},
        'diff': {'added': cover({family: new_points[family] - old_points[family] for family in [4, 6]}),
                 'removed': cover({family: old_points[family] - new_points[family] for family in [4, 6]})},
    }

    def save() -> None:
        args.output.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')

    with tempfile.TemporaryDirectory(prefix='ipset-cli-benchmark-') as temporary:
        fixture_dir = args.fixtures.resolve() if args.fixtures else Path(temporary)
        fixture_dir.mkdir(parents=True, exist_ok=True)
        rss_file = Path(temporary) / 'rss.txt'
        try:
            for rows in args.sizes:
                old, new = fixture_dir / f'old-{rows}.txt', fixture_dir / f'new-{rows}.txt'
                old_meta = write_fixture(old, old_entries, rows)
                new_meta = write_fixture(new, new_entries, rows)
                for operation in args.operations:
                    argv = ['normalize', str(new), '--json'] if operation == 'normalize' else ['diff', str(old), str(new), '--json']
                    actual_command = command + argv
                    if gnu_time:
                        actual_command = [str(gnu_time), '-q', '-f', '%M', '-o', str(rss_file)] + actual_command
                    times, memory = [], []
                    output_bytes = None
                    for iteration in range(args.warmup + args.runs):
                        start = time.perf_counter()
                        result = subprocess.run(actual_command, stdin=subprocess.DEVNULL,
                                                capture_output=True, timeout=args.timeout, check=False)
                        elapsed = (time.perf_counter() - start) * 1000
                        if result.returncode != (0 if operation == 'normalize' else 1):
                            raise RuntimeError(f'{rows}/{operation}: exit {result.returncode}: {result.stderr[:1200]!r}')
                        if result.stderr or json.loads(result.stdout) != expected[operation]:
                            raise RuntimeError(f'{rows}/{operation}: output differs from independent oracle')
                        output_bytes = len(result.stdout)
                        if iteration >= args.warmup:
                            times.append(round(elapsed, 3))
                            if gnu_time:
                                memory.append(int(rss_file.read_text().strip()))
                        print(f'[cli-benchmark] {args.label} {rows} {operation} '
                              f'{"warmup" if iteration < args.warmup else "sample"} {elapsed:.3f} ms', file=sys.stderr, flush=True)
                    case = {'rows_per_input': rows, 'operation': operation,
                            'input_files': {'new': new_meta} if operation == 'normalize' else {'old': old_meta, 'new': new_meta},
                            'stdout_bytes': output_bytes, 'exit_status': 0 if operation == 'normalize' else 1,
                            'wall_ms': summarize(times), 'max_rss_kib': summarize(memory) if memory else None}
                    report['cases'].append(case)
                    save()
            report['status'] = 'passed'
        except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
            report['status'] = 'failed'
            report['failure'] = str(error)
        save()
    print(json.dumps({'status': report['status'], 'cases': len(report['cases']), 'output': str(args.output)}))
    return 0 if report['status'] == 'passed' else 1


if __name__ == '__main__':
    raise SystemExit(main())
