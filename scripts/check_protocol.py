#!/usr/bin/env python3
"""Check actual process framing and recovery, not only the request handler."""
import argparse
import json
from pathlib import Path
import shlex
import subprocess


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--command", required=True)
    parser.add_argument("--report")
    args = parser.parse_args()
    lines = [
        "",
        '{"op":"parse","address":"::1"}',
        "{",
        '{"op":"normalize","cidrs":[]}',
        "[]",
        '{"op":"parse","op":"contains","address":"::1"}',
        '{"op":"contains","cidrs":["192.0.2.0/24"],"address":"192.0.2.1"}',
        "  ",
        '{"op":"range","start":"::","end":"::1"}',
    ]
    expected = [
        {"ok": True, "address": "::1", "family": 6},
        {"ok": False},
        {"ok": True, "cidrs": []},
        {"ok": False},
        {"ok": False},
        {"ok": True, "value": True},
        {"ok": True, "cidrs": ["::/127"]},
    ]
    result = subprocess.run(
        shlex.split(args.command), input="\r\n".join(lines), text=True,
        capture_output=True, timeout=30, check=False,
    )
    report = {"status": "failed", "responses": 0, "checks": len(expected)}
    try:
        if result.returncode != 0:
            raise ValueError(f"CLI exited {result.returncode}: {result.stderr}")
        actual = [json.loads(line) for line in result.stdout.splitlines()]
        if len(actual) != len(expected):
            raise ValueError(f"expected {len(expected)} responses, received {len(actual)}")
        for index, (response, wanted) in enumerate(zip(actual, expected)):
            if not isinstance(response, dict):
                raise ValueError(f"response {index} must be an object")
            if response.get("ok") is not wanted["ok"]:
                raise ValueError(f"response {index}: expected {wanted}, got {response}")
            if wanted["ok"]:
                if any(response.get(key) != value for key, value in wanted.items()):
                    raise ValueError(f"response {index}: expected {wanted}, got {response}")
            elif not isinstance(response.get("error"), str) or not response["error"]:
                raise ValueError(f"response {index} has no error message")
        report.update(status="passed", responses=len(actual), cases=[
            "CRLF and blank lines", "malformed JSON recovery", "non-object request",
            "duplicate JSON keys", "subsequent valid requests", "final line without newline",
        ])
    except (ValueError, TypeError) as error:
        report["failure"] = str(error)
    rendered = json.dumps(report, indent=2)
    if args.report:
        output = Path(args.report)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(rendered + "\n", encoding="utf-8")
    print(rendered)
    return 0 if report["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
