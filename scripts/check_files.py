#!/usr/bin/env python3
"""Exercise the real file CLI, exit statuses, diagnostics, and stable launcher."""
from __future__ import annotations

import argparse
import ipaddress
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile


def absolute_command(text: str) -> list[str]:
    args = shlex.split(text)
    if not args:
        raise ValueError('empty command')
    args[0] = shutil.which(args[0]) or str(Path(args[0]).resolve())
    for index in range(1, len(args)):
        if Path(args[index]).is_file():
            args[index] = str(Path(args[index]).resolve())
    return args


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--command', required=True)
    parser.add_argument('--launcher', help='optional stable source launcher command')
    parser.add_argument('--report')
    args = parser.parse_args()
    repo = Path(__file__).resolve().parent.parent
    command = absolute_command(args.command)
    passed: list[str] = []

    def run(argv: list[str], *, status: int, data: str | None = None,
            cwd: Path | None = None, program: list[str] | None = None,
            env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
        result = subprocess.run((program or command) + argv, input=data,
                                text=True, encoding='utf-8', capture_output=True,
                                cwd=cwd, env=env, timeout=90, check=False)
        if result.returncode != status:
            raise AssertionError(f'{argv}: exit {result.returncode}, expected {status}; stderr={result.stderr[:1500]}')
        if status == 2 and (result.stdout or not result.stderr.strip()):
            raise AssertionError(f'{argv}: errors require empty stdout and nonempty stderr')
        return result

    def check_json(result: subprocess.CompletedProcess[str], expected: object) -> None:
        actual = json.loads(result.stdout)
        if actual != expected:
            raise AssertionError(f'expected {str(expected)[:500]}, received {str(actual)[:500]}')

    report: dict[str, object] = {'status': 'failed', 'checks': passed}
    try:
        fixtures = repo / 'examples' / 'policies'
        expected = json.loads((fixtures / 'expected-diff.json').read_text())
        old = str(fixtures / 'old.txt')
        new = str(fixtures / 'new.txt')
        check_json(run(['diff', old, new, '--json'], status=1), expected)
        passed.append('documented dual-stack policy diff fixture')
        text = run(['diff', old, new], status=1).stdout
        if text != 'Added:\n' + '\n'.join(expected['added']) + '\nRemoved:\n' + '\n'.join(expected['removed']) + '\n':
            raise AssertionError(f'unexpected text diff format: {text!r}')
        passed.append('complete deterministic text diff')
        check_json(run(['diff', new, old, '--json'], status=1),
                   {'added': expected['removed'], 'removed': expected['added']})
        passed.append('reversing operands exchanges added and removed')

        with tempfile.TemporaryDirectory(prefix='ipset file test ') as directory:
            temp = Path(directory)
            def write(name: str, text: str) -> str:
                path = temp / name
                path.write_text(text, encoding='utf-8', newline='')
                return str(path)

            equivalent = write('等价 清单.txt', '\ufeff# comment\r\n2001:db8::2/127\r\n10.0.0.128/25\r\n\r\n10.0.0.0/25 # inline\r\n2001:db8::/127\r\n10.0.0.0/24\r\n')
            check_json(run(['diff', old, equivalent, '--json'], status=0), {'added': [], 'removed': []})
            passed.append('semantic equality despite order, duplicates, splits, BOM, CRLF, comments and Unicode paths')
            check_json(run(['normalize', equivalent, '--json'], status=0),
                       {'cidrs': ['10.0.0.0/24', '2001:db8::/126']})
            passed.append('normalization yields minimal dual-stack CIDRs')
            empty = write('empty.txt', '\n# only comment\n')
            check_json(run(['diff', empty, empty, '--json'], status=0), {'added': [], 'removed': []})
            check_json(run(['normalize', empty, '--json'], status=0), {'cidrs': []})
            passed.append('empty files and empty results')
            hosts = write('hosts.txt', '255.255.255.255\n::\nffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff\n::ffff:192.0.2.1\n')
            host_result = {'cidrs': ['255.255.255.255/32', '::/128', '::ffff:c000:201/128', 'ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff/128']}
            check_json(run(['normalize', hosts, '--strict', '--json'], status=0), host_result)
            passed.append('bare hosts, mapped IPv6, maximum and zero addresses')
            loose = write('host-bits.txt', '# line one\n10.0.0.1/24\n')
            check_json(run(['normalize', loose, '--json'], status=0), {'cidrs': ['10.0.0.0/24']})
            strict = run(['normalize', loose, '--strict'], status=2)
            if 'host-bits.txt:2' not in strict.stderr:
                raise AssertionError(f'strict error must identify file and line: {strict.stderr}')
            passed.append('strict host bits rejection with source location')
            broken = write('broken.txt', '10.0.0.0/24\n# second line\n2001:db8::zz\n')
            for argv in [['normalize', broken], ['diff', old, broken, '--json']]:
                result = run(argv, status=2)
                if 'broken.txt:3' not in result.stderr:
                    raise AssertionError(f'error must retain source line: {result.stderr}')
            passed.append('invalid later input yields no partial normal or diff output')
            missing = str(temp / 'missing.txt')
            if 'missing.txt' not in run(['diff', old, missing], status=2).stderr:
                raise AssertionError('missing file diagnostic lacks filename')
            run(['normalize', str(temp)], status=2)
            passed.append('missing file and directory input errors')
            bad_utf8 = temp / 'invalid-utf8.txt'
            bad_utf8.write_bytes(b'10.0.0.1\n\xff\n')
            if 'invalid-utf8.txt:2' not in run(['normalize', str(bad_utf8)], status=2).stderr:
                raise AssertionError('invalid UTF-8 must identify its physical line')
            passed.append('invalid UTF-8 is rejected')
            check_json(run(['normalize', '-', '--json'], status=0, data='192.0.2.1\n'), {'cidrs': ['192.0.2.1/32']})
            check_json(run(['diff', '-', old, '--json'], status=0, data=Path(old).read_text()), {'added': [], 'removed': []})
            run(['diff', '-', '-'], status=2, data='192.0.2.1\n')
            passed.append('stdin source and rejection of repeated stdin')
            write('-old', '192.0.2.1\n')
            write('--help', '192.0.2.1/32\n')
            check_json(run(['diff', '--json', '--', '-old', '--help'], status=0, cwd=temp), {'added': [], 'removed': []})
            passed.append('option terminator preserves hyphen-prefixed filenames')
            for argv in [['diff', old], ['normalize'], ['normalize', old, new], ['unknown'], ['normalize', old, '--unknown']]:
                run(argv, status=2)
            passed.append('wrong argument counts and unknown options fail')

            base = int(ipaddress.IPv6Address('2001:db8::'))
            addresses = [str(ipaddress.IPv6Address(base + 2 * index)) for index in range(6000)]
            large = write('large.txt', '\n'.join(addresses) + '\n')
            output = run(['normalize', large], status=0).stdout
            wanted = ''.join(address + '/128\n' for address in addresses)
            if output != wanted or len(output.encode()) < 65536:
                raise AssertionError('large piped output is truncated or fixture is too small')
            passed.append('more than 64 KiB stdout is flushed completely')

            if args.launcher:
                launcher = absolute_command(args.launcher)
                check_json(run(['diff', old, new, '--json'], status=1, program=launcher, cwd=temp), expected)
                passed.append('stable launcher works outside repository and preserves diff exit code')
                write('relative.txt', Path(old).read_text())
                check_json(run(['diff', '-', 'relative.txt', '--json'], status=0, data=Path(old).read_text(),
                               program=launcher, cwd=temp), {'added': [], 'removed': []})
                passed.append('launcher rebuild preserves relative paths and stdin')
                minimal = dict(os.environ, PATH='')
                help_result = run(['--help'], status=0, program=launcher, cwd=temp, env=minimal)
                if 'diff' not in help_result.stdout or 'normalize' not in help_result.stdout:
                    raise AssertionError('help lacks user commands')
                if run(['--help'], status=0).stdout != help_result.stdout:
                    raise AssertionError('launcher and compiled CLI help drifted')
                run(['normalize', old], status=2, program=launcher, cwd=temp, env=minimal)
                passed.append('launcher help works without MoonBit; missing compiler reports error')
                runtime = Path(launcher[-1]).parent / 'runtime.mjs'
                failure = write('host-failure.mjs', 'throw new Error("synthetic-host-failure");\n')
                caught = run([failure], status=2, program=[launcher[0], '--import', runtime.as_uri()], cwd=temp)
                if 'synthetic-host-failure' not in caught.stderr:
                    raise AssertionError('runtime guard lost the host exception diagnostic')
                passed.append('unexpected host exceptions cannot masquerade as diff changes')

                bootstrap_dir = temp / 'bootstrap checks'
                bootstrap_dir.mkdir()
                bootstrap = bootstrap_dir / 'run.mjs'
                shutil.copyfile(Path(launcher[-1]).parent / 'run.mjs', bootstrap)
                entry = bootstrap_dir / 'entry.mjs'
                entry.write_text('process.exitCode = 1;\n', encoding='utf-8')
                boot_command = [launcher[0], str(bootstrap), str(entry)]
                missing_runtime = run([], status=2, program=boot_command, cwd=temp)
                if 'runtime.mjs' not in missing_runtime.stderr:
                    raise AssertionError('missing runtime diagnostic lacks its filename')
                runtime_copy = bootstrap_dir / 'runtime.mjs'
                runtime_copy.write_text('export const = ;\n', encoding='utf-8')
                run([], status=2, program=boot_command, cwd=temp)
                shutil.copyfile(runtime, runtime_copy)
                entry.unlink()
                missing_entry = run([], status=2, program=boot_command, cwd=temp)
                if 'entry.mjs' not in missing_entry.stderr:
                    raise AssertionError('missing compiled entry diagnostic lacks its filename')
                entry.write_text('export const = ;\n', encoding='utf-8')
                run([], status=2, program=boot_command, cwd=temp)
                entry.write_text('throw new Error("synthetic-entry-failure");\n', encoding='utf-8')
                run([], status=2, program=boot_command, cwd=temp)
                passed.append('bootstrap maps missing and malformed runtime or compiled entry to exit 2')

                entry.write_text(
                    'process.stdout.write(JSON.stringify({argv: process.argv.slice(2), '
                    'cwd: process.cwd(), stdin: process.getBuiltinModule("fs").readFileSync(0, "utf8")}));\n'
                    'process.exitCode = 1;\n', encoding='utf-8')
                preserved = run(['diff', '-', 'relative.txt'], status=1, data='192.0.2.1\n',
                                program=boot_command, cwd=temp)
                check_json(preserved, {'argv': ['diff', '-', 'relative.txt'], 'cwd': str(temp),
                                       'stdin': '192.0.2.1\n'})
                passed.append('bootstrap preserves argument positions cwd stdin and valid exit 1')

        lines = run([], status=0, data='{\n{"op":"parse","address":"::1"}\n').stdout.splitlines()
        if len(lines) != 2 or json.loads(lines[0]).get('ok') is not False or json.loads(lines[1]) != {'ok': True, 'address': '::1', 'family': 6}:
            raise AssertionError('legacy JSONL error recovery changed')
        passed.append('legacy no-argument JSONL behavior remains intact')
        report['status'] = 'passed'
    except (AssertionError, OSError, ValueError, subprocess.TimeoutExpired) as error:
        report['failure'] = str(error)
    report['passed_checks'] = len(passed)
    rendered = json.dumps(report, ensure_ascii=False, indent=2)
    if args.report:
        output = Path(args.report)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(rendered + '\n', encoding='utf-8')
    print(rendered)
    return 0 if report['status'] == 'passed' else 1


if __name__ == '__main__':
    raise SystemExit(main())
