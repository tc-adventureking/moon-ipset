#!/usr/bin/env python3
"""Check actual Node CLI framing, input encoding, and per-request recovery."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import shlex
import subprocess
import tempfile


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--command", required=True, help="Node CLI command, compiled or portable")
    parser.add_argument("--report")
    args = parser.parse_args()
    command = shlex.split(args.command)
    passed: list[str] = []
    responses = 0
    report: dict[str, object] = {"status": "failed", "responses": 0, "checks": 0}

    def run(data: bytes, arguments: list[str] | None = None, *,
            env: dict[str, str] | None = None) -> subprocess.CompletedProcess[bytes]:
        return subprocess.run(command + (arguments or []), input=data,
                              capture_output=True, env=env, timeout=30, check=False)

    def check_jsonl(name: str, data: bytes, expected: list[dict[str, object]], *,
                    arguments: list[str] | None = None) -> None:
        nonlocal responses
        result = run(data, arguments)
        if result.returncode != 0 or result.stderr:
            raise ValueError(f"{name}: exit {result.returncode}; stderr={result.stderr[:1500]!r}")
        actual = [json.loads(line) for line in result.stdout.splitlines()]
        if len(actual) != len(expected):
            raise ValueError(f"{name}: expected {len(expected)} responses, received {len(actual)}")
        for index, (response, wanted) in enumerate(zip(actual, expected)):
            if not isinstance(response, dict) or response.get("ok") is not wanted["ok"]:
                raise ValueError(f"{name}, response {index}: expected {wanted}, got {response}")
            if wanted["ok"]:
                if response != wanted:
                    raise ValueError(f"{name}, response {index}: expected {wanted}, got {response}")
            elif not isinstance(response.get("error"), str) or not response["error"]:
                raise ValueError(f"{name}, response {index}: missing error message")
            elif "error_contains" in wanted and wanted["error_contains"] not in response["error"]:
                raise ValueError(f"{name}, response {index}: unexpected error {response['error']!r}")
        responses += len(actual)
        passed.append(name)

    def check_input_error(name: str, data: bytes, diagnostic: str, *,
                          arguments: list[str] | None = None,
                          env: dict[str, str] | None = None) -> None:
        result = run(data, arguments or ["normalize", "-"], env=env)
        stderr = result.stderr.decode("utf-8")
        if result.returncode != 2 or result.stdout or stderr != diagnostic + "\n":
            raise ValueError(f"{name}: expected exit 2, empty stdout, stderr={diagnostic!r}; "
                             f"got exit {result.returncode}, stdout={result.stdout[:500]!r}, "
                             f"stderr={stderr[:1500]!r}")
        passed.append(name)

    try:
        lines = [
            "", '{"op":"parse","address":"::1"}', "{",
            '{"op":"normalize","cidrs":[]}', "[]",
            '{"op":"parse","op":"contains","address":"::1"}',
            '{"op":"contains","cidrs":["192.0.2.0/24"],"address":"192.0.2.1"}',
            "  ", '{"op":"range","start":"::","end":"::1"}',
        ]
        expected = [
            {"ok": True, "address": "::1", "family": 6}, {"ok": False},
            {"ok": True, "cidrs": []}, {"ok": False}, {"ok": False},
            {"ok": True, "value": True}, {"ok": True, "cidrs": ["::/127"]},
        ]
        check_jsonl("CRLF, blanks, malformed/non-object/duplicate-key recovery, final line without newline",
                    "\r\n".join(lines).encode("utf-8"), expected)
        valid = b'{"op":"parse","address":"::1"}'
        success = {"ok": True, "address": "::1", "family": 6}
        bom = b"\xef\xbb\xbf"
        for arguments in [[], ["jsonl"]]:
            check_jsonl(f"initial BOM accepted; later BOM rejected ({arguments or 'default'})",
                        bom + valid + b"\r\n" + bom + valid + b"\n" + valid,
                        [success, {"ok": False}, success], arguments=arguments)
        check_jsonl("only one initial BOM is stripped", bom + bom + valid + b"\n" + valid,
                    [{"ok": False}, success])
        check_jsonl("BOM after blank line is not initial", b"\n" + bom + valid + b"\n" + valid,
                    [{"ok": False}, success])
        # Use core/json's existing depth guard; test both recursive parser paths.
        for label, nested in [
            ("arrays", b"[" * 100000 + b"]" * 100000),
            ("objects", b'{"x":' * 100000 + b"0" + b"}" * 100000),
        ]:
            check_jsonl(f"100000 nested {label}: preserve preceding and following response",
                        valid + b'\n{"op":' + nested + b"}\n" + valid,
                        [success, {"ok": False, "error_contains": "Depth limit exceeded"}, success])

        with tempfile.TemporaryDirectory(prefix="ipset-protocol-") as directory:
            temporary = Path(directory)
            for encoding, prefix in [("utf-16le", b"\xff\xfe"), ("utf-16be", b"\xfe\xff")]:
                data = prefix + "10.0.0.0/8\r\n".encode(encoding)
                message = "UTF-16 input is not supported; save as UTF-8"
                check_input_error(f"{encoding} BOM stdin diagnostic", data, "-:1: " + message)
                filename = temporary / (encoding + ".txt")
                filename.write_bytes(data)
                check_input_error(f"{encoding} BOM file diagnostic", b"", f"{filename}:1: {message}",
                                  arguments=["normalize", str(filename)])
            check_input_error("invalid UTF-8 retains physical line diagnostic",
                              b"::1\r\n\xff\n", "-:2: invalid UTF-8")

            # Fault injection only affects the CLI's strict decoder, not Node's
            # module loader. Each subprocess gets a fresh, isolated decoder.
            for failing_call, error_type in [(0, "RangeError"), (0, "Error"), (1, "RangeError")]:
                injection = temporary / f"decoder-{failing_call}-{error_type}.mjs"
                injection.write_text(
                    'const Original = globalThis.TextDecoder;\n'
                    'globalThis.TextDecoder = class extends Original {\n'
                    '  constructor(encoding, options) {\n'
                    '    super(encoding, options);\n'
                    '    this.target = encoding === "utf-8" && options?.fatal === true && options?.ignoreBOM === true;\n'
                    '    this.calls = 0;\n'
                    '  }\n'
                    '  decode(...args) {\n'
                    f'    if (this.target && this.calls++ === {failing_call}) throw new {error_type}("decoder fault probe");\n'
                    '    return super.decode(...args);\n'
                    '  }\n'
                    '};\n', encoding="utf-8")
                env = os.environ.copy()
                env["NODE_OPTIONS"] = (env.get("NODE_OPTIONS", "") + " --import=" + injection.as_uri()).strip()
                check_input_error(f"decoder {error_type} on call {failing_call} is not mislabeled UTF-8",
                                  b"\xff" if failing_call else b"::1", "-: decoder fault probe", env=env)
        report["status"] = "passed"
    except (ValueError, TypeError, OSError, subprocess.TimeoutExpired) as error:
        report["failure"] = str(error)
    report.update(responses=responses, checks=len(passed), cases=passed)
    rendered = json.dumps(report, indent=2)
    if args.report:
        output = Path(args.report)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(rendered + "\n", encoding="utf-8")
    print(rendered)
    return 0 if report["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
