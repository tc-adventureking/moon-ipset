#!/usr/bin/env python3
"""Build and verify a MoonBit library ZIP and a portable Node CLI ZIP.

Uses only Python's standard library plus the existing moon, node and git tools.
The archive-consumer check is local; it does not install from Mooncakes.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import zipfile


ENTRY = """#!/usr/bin/env node
try {
  await import('./runtime.mjs');
  await import('./ipset.js');
} catch (error) {
  process.exitCode = 2;
  process.stderr.write(`ipset: internal error: ${error instanceof Error ? error.message : String(error)}\\n`);
}
"""

SMOKE_TEST = """///|
test "archive consumer uses the public API" {
  let rules = @net.IpSet::from_cidrs([
    "192.0.2.0/25", "192.0.2.128/25", "2001:db8::/126",
  ])
  assert_eq(rules.cidrs().map(cidr => cidr.to_string()), [
    "192.0.2.0/24", "2001:db8::/126",
  ])
  let excluded = @net.IpSet::from_cidrs(["192.0.2.64/26"])
  assert_eq(rules.difference(excluded).cidrs().map(cidr => cidr.to_string()), [
    "192.0.2.0/26", "192.0.2.128/25", "2001:db8::/126",
  ])
  assert_true(rules.contains(@net.Address::parse("2001:db8::3")))
  assert_false(rules.contains(@net.Address::parse("2001:db8::4")))
}
"""


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def executable(name: str) -> str:
    located = shutil.which(name)
    if located is None and Path(name).is_file():
        located = str(Path(name).resolve())
    require(located is not None, f"required executable not found: {name}")
    return str(Path(located).resolve())


def digest(path: Path) -> str:
    sha = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            sha.update(chunk)
    return sha.hexdigest()


def manifest_string(source: str, key: str) -> str:
    matches = re.findall(rf'^\s*{re.escape(key)}\s*=\s*("[^"\n]*")\s*$', source, re.MULTILINE)
    require(len(matches) == 1, f"moon.mod must contain one string {key}")
    return json.loads(matches[0])


def archive_members(archive: Path) -> list[str]:
    with zipfile.ZipFile(archive) as zipped:
        names = zipped.namelist()
        require(len(names) == len(set(names)), f"duplicate ZIP members in {archive.name}")
        for member in zipped.infolist():
            path = PurePosixPath(member.filename)
            require(bool(path.parts) and not path.is_absolute() and ".." not in path.parts
                    and "\\" not in member.filename and ":" not in member.filename,
                    f"unsafe ZIP member: {member.filename!r}")
            require(not stat.S_ISLNK(member.external_attr >> 16),
                    f"ZIP symlinks are not accepted: {member.filename}")
        require(zipped.testzip() is None, f"ZIP integrity check failed: {archive.name}")
    return names


def check_library_archive(archive: Path, module: str, version: str) -> list[str]:
    names = archive_members(archive)
    forbidden = {
        "moon.work", "bench", "cmd", "bin", "examples", "scripts", "work", "_build",
        "target", "node_modules", "__pycache__", ".git", ".github", ".mooncakes",
    }
    for name in names:
        parts = PurePosixPath(name).parts
        require(not any(part in forbidden or part.startswith(".") for part in parts),
                f"development/private file in library archive: {name}")
        require(not name.startswith(("docs/ai/", "docs/verification/")),
                f"development report in library archive: {name}")
        require(Path(name).suffix.lower() not in {".pyc", ".core", ".pem", ".key"},
                f"private/generated file in library archive: {name}")
    required = {"moon.mod", "moon.pkg", "LICENSE", "README.md", "address.mbt", "cidr.mbt", "set.mbt"}
    require(required.issubset(names), f"missing library files: {sorted(required - set(names))}")
    with zipfile.ZipFile(archive) as zipped:
        module_text = zipped.read("moon.mod").decode("utf-8")
    require(manifest_string(module_text, "name") == module, "packaged module name differs")
    require(manifest_string(module_text, "version") == version, "packaged version differs")
    return sorted(names)


def write_cli_archive(archive: Path, files: dict[str, bytes]) -> None:
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as zipped:
        for name, content in sorted(files.items()):
            info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.create_system = 3
            info.external_attr = (0o100755 if name == "ipset.mjs" else 0o100644) << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            zipped.writestr(info, content)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=Path("_build/release"),
                        help="outside the repository, or inside its _build directory (default: _build/release)")
    parser.add_argument("--moon", default="moon", help="Moon executable name or path")
    parser.add_argument("--node", default="node", help="Node executable name or path")
    parser.add_argument("--timeout", type=float, default=240, help="timeout per build/check in seconds")
    parser.add_argument("--allow-dirty", action="store_true",
                        help="allow development packaging from uncommitted sources; never use for a release")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    output = args.output.resolve()
    require(args.timeout > 0, "--timeout must be positive")
    require(not output.is_relative_to(repo) or output.is_relative_to(repo / "_build"),
            "--output must be outside the repository or under _build to prevent packaging previous releases")
    moon, node, git = executable(args.moon), executable(args.node), executable("git")
    core = Path(os.environ.get("MOON_HOME", str(Path(moon).parent.parent))) / "lib" / "core"
    core_notices = {}
    for name in ("LICENSE", "NOTICE"):
        source = core / name
        require(source.is_file(), f"MoonBit core {name} is missing from the selected toolchain")
        content = source.read_bytes()
        require(bool(content.strip()), f"MoonBit core {name} is empty")
        core_notices[f"third_party/moonbit-core/{name}"] = content
    module_source = (repo / "moon.mod").read_text(encoding="utf-8")
    module, version = (manifest_string(module_source, key) for key in ("name", "version"))
    require(re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?", version)
            is not None, "unsupported release version")
    build_env = os.environ.copy()
    build_env["MOON_WORK"] = "off"

    def run(command: list[str], *, cwd: Path, env: dict[str, str] | None = None,
            status: int = 0, label: str, input_text: str | None = None) -> subprocess.CompletedProcess[str]:
        print(f"[release] {label}", file=sys.stderr, flush=True)
        result = subprocess.run(command, cwd=cwd, env=env or build_env,
                                capture_output=True, text=True, encoding="utf-8", errors="replace",
                                stdin=subprocess.DEVNULL if input_text is None else None,
                                input=input_text, timeout=args.timeout, check=False)
        if result.returncode != status:
            detail = (result.stderr + "\n" + result.stdout).strip()[-6000:]
            raise RuntimeError(f"{label}: exit {result.returncode}, expected {status}\n{detail}")
        return result

    source_head = run([git, "rev-parse", "HEAD"], cwd=repo, label="read source revision").stdout.strip()
    require(re.fullmatch(r"[0-9a-f]{40,64}", source_head) is not None, "invalid source revision")
    source_dirty = bool(run([git, "status", "--porcelain", "--untracked-files=normal"],
                            cwd=repo, label="check source worktree").stdout.strip())
    require(args.allow_dirty or not source_dirty,
            "source worktree is dirty; commit changes before release or use --allow-dirty for development")
    node_version = run([node, "--version"], cwd=repo, label="read Node version").stdout.strip()
    node_numbers = re.fullmatch(r"v(\d+)\.(\d+)\.(\d+)", node_version)
    require(node_numbers is not None and tuple(map(int, node_numbers.groups())) >= (22, 3, 0),
            "portable CLI requires Node.js 22.3.0 or newer")
    moon_version_output = run([moon, "version"], cwd=repo, label="read Moon version").stdout.strip()
    # Keep public metadata independent of local executable locations.
    moon_version_match = re.search(r"moon [0-9][^\r\n]*?\([^\r\n)]+\)", moon_version_output)
    moon_version = moon_version_match.group(0) if moon_version_match else "unreported"
    output.mkdir(parents=True, exist_ok=True)
    (repo / "_build").mkdir(exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="release-build-", dir=repo / "_build") as build_directory, \
            tempfile.TemporaryDirectory(prefix="moon-ipset-verify-") as verification_directory, \
            tempfile.TemporaryDirectory(prefix=".release-stage-", dir=output) as staging_directory:
        build, verification, stage = map(Path, (build_directory, verification_directory, staging_directory))
        require(not verification.is_relative_to(repo), "verification temp directory must be outside the repository")
        packaged = run([moon, "package", "--target-dir", str(build)], cwd=repo,
                       label="create official MoonBit library ZIP")
        candidates = list(build.rglob("*.zip"))
        # Some mooncake versions place archives outside the supplied build directory.
        if not candidates:
            for line in (packaged.stdout + "\n" + packaged.stderr).splitlines():
                if line.startswith("Package to "):
                    candidate = Path(line[len("Package to "):].strip())
                    if not candidate.is_absolute():
                        candidate = repo / candidate
                    if candidate.is_file() and candidate.resolve().is_relative_to(repo / "_build"):
                        candidates.append(candidate)
        require(len(candidates) == 1, f"expected one generated library ZIP, found {len(candidates)}")
        library = stage / f"moon-ipset-{version}-library.zip"
        shutil.copyfile(candidates[0], library)
        require(digest(library) == digest(candidates[0]), "official library ZIP was not copied unchanged")
        library_members = check_library_archive(library, module, version)

        unpacked = verification / "library"
        with zipfile.ZipFile(library) as zipped:
            zipped.extractall(unpacked)
        isolated_env = os.environ.copy()
        isolated_env.pop("MOON_WORK", None)
        run([moon, "check", "--target", "wasm-gc", "--deny-warn"], cwd=unpacked,
            env=isolated_env, label="check unpacked library outside any repository workspace")

        consumer = verification / "consumer"
        consumer.mkdir()
        (consumer / "moon.mod").write_text(
            'name = "smoke/ipset-release-consumer"\nversion = "0.1.0"\n'
            f'import {{\n  "{module}@{version}",\n}}\n', encoding="utf-8")
        (consumer / "moon.pkg").write_text(f'import {{\n  "{module}" @net,\n}} for "test"\n', encoding="utf-8")
        (consumer / "smoke_test.mbt").write_text(SMOKE_TEST, encoding="utf-8")
        workspace = verification / "moon.work"
        workspace.write_text('members = ["library", "consumer"]\n', encoding="utf-8")
        consumer_env = isolated_env | {"MOON_WORK": str(workspace)}
        consumed = run([moon, "test", ".", "--target", "wasm-gc", "--deny-warn", "--frozen"],
                       cwd=consumer, env=consumer_env, label="test independent consumer using only unpacked library")
        require(re.search(r"Total tests:\s*1,\s*passed:\s*1,\s*failed:\s*0", consumed.stdout + consumed.stderr)
                is not None, "independent consumer did not report exactly one passing test")

        run([moon, "build", "cmd/ipset", "--release", "--target", "js", "--target-dir", str(build)],
            cwd=repo, label="build release JavaScript CLI")
        js_candidates = [path for path in build.rglob("ipset.js")
                         if path.as_posix().endswith("/cmd/ipset/ipset.js")]
        require(len(js_candidates) == 1, f"expected one built CLI entry, found {len(js_candidates)}")
        compiled_js = js_candidates[0].read_bytes()
        require(bool(compiled_js), "compiled CLI is empty")
        for local_path in {str(repo), repo.as_posix(), str(build), build.as_posix()}:
            require(local_path.encode() not in compiled_js, "compiled CLI contains a local build path")
        cli = stage / f"moon-ipset-{version}-cli.zip"
        readme = f"""moon-ipset {version} portable CLI

Requires Node.js 22.3.0 or newer. MoonBit is not required at runtime.
Project code is MIT; compiled MoonBit core portions retain their own license.
See THIRD_PARTY_NOTICES.txt and third_party/moonbit-core/.
Extract every file into the same directory. From any working directory:

  node /path/to/ipset.mjs --help
  node /path/to/ipset.mjs normalize rules.txt --json
  node /path/to/ipset.mjs diff old.txt new.txt --json
  node /path/to/ipset.mjs jsonl < requests.jsonl

Relative input paths are resolved from your current working directory.
Exit codes: 0 success/no changes, 1 diff has changes, 2 input/usage/internal error.
Without arguments the command reads JSON Lines from stdin until EOF.
The library ZIP is a separate MoonBit source package, not a Registry installation.
"""
        files = {
            "ipset.js": compiled_js,
            "ipset.mjs": ENTRY.encode(),
            "runtime.mjs": (repo / "bin/runtime.mjs").read_bytes(),
            "package.json": (json.dumps({"name": "moon-ipset-cli", "version": version,
                "private": True, "type": "commonjs", "engines": {"node": ">=22.3.0"}}, indent=2) + "\n").encode(),
            "LICENSE": (repo / "LICENSE").read_bytes(),
            "README.txt": readme.encode(),
            "THIRD_PARTY_NOTICES.txt": (
                "The compiled ipset.js includes portions of MoonBit core.\n"
                "MoonBit core is distributed under Apache-2.0. Its full LICENSE\n"
                "and upstream NOTICE are retained in third_party/moonbit-core/.\n"
                "The upstream NOTICE is reproduced in full, including notices\n"
                "for core components that may not be linked into this program.\n"
                "Project source code remains MIT (see LICENSE). Node.js is a\n"
                "separately installed runtime and is not bundled here.\n"
            ).encode(),
            **core_notices,
        }
        write_cli_archive(cli, files)
        cli_members = archive_members(cli)
        require(set(cli_members) == set(files), "portable CLI archive file list differs")
        portable = verification / "portable"
        with zipfile.ZipFile(cli) as zipped:
            zipped.extractall(portable)
        for name, expected in core_notices.items():
            require((portable / name).read_bytes() == expected,
                    f"portable archive does not preserve upstream notice: {name}")
            require((core / PurePosixPath(name).name).read_bytes() == expected,
                    "MoonBit core notices changed while packaging")
        caller = verification / "caller"
        caller.mkdir()
        (caller / "old.txt").write_text("192.0.2.0/25\n2001:db8::/126\n", encoding="utf-8")
        (caller / "new.txt").write_text("192.0.2.128/25\n2001:db8::/126\n", encoding="utf-8")
        (caller / "bad.txt").write_text("192.0.2.0/24\nnot-an-address\n", encoding="utf-8")
        runtime_env = os.environ.copy()
        runtime_env["PATH"] = ""
        runtime_env.pop("NODE_OPTIONS", None)
        runtime_env.pop("NODE_PATH", None)
        command = [node, str(portable / "ipset.mjs")]
        help_result = run(command + ["--help"], cwd=caller, env=runtime_env, label="portable --help with empty PATH")
        require("Usage: ipset" in help_result.stdout and not help_result.stderr,
                "portable CLI help is missing or wrote diagnostics")
        changed = run(command + ["diff", "old.txt", "new.txt", "--json"], cwd=caller,
                      env=runtime_env, status=1, label="portable changed diff exits 1 and preserves caller cwd")
        require(json.loads(changed.stdout) == {"added": ["192.0.2.128/25"], "removed": ["192.0.2.0/25"]}
                and not changed.stderr, "portable changed diff output differs")
        equal = run(command + ["diff", "old.txt", "old.txt", "--json"], cwd=caller,
                    env=runtime_env, label="portable unchanged diff exits 0")
        require(json.loads(equal.stdout) == {"added": [], "removed": []} and not equal.stderr,
                "portable equal diff output differs")
        stdin_text = (caller / "old.txt").read_text(encoding="utf-8")
        normalized = run(command + ["normalize", "-", "--json"], cwd=caller, env=runtime_env,
                         input_text=stdin_text, label="portable normalize from stdin")
        require(json.loads(normalized.stdout) == {"cidrs": ["192.0.2.0/25", "2001:db8::/126"]}
                and not normalized.stderr, "portable stdin normalization differs")
        piped_diff = run(command + ["diff", "-", "new.txt", "--json"], cwd=caller,
                         env=runtime_env, input_text=stdin_text, status=1,
                         label="portable diff with stdin and a relative file")
        require(piped_diff.stdout == changed.stdout and not piped_diff.stderr,
                "portable stdin diff differs from the equivalent file diff")
        invalid = run(command + ["diff", "old.txt", "bad.txt", "--json"], cwd=caller,
                      env=runtime_env, status=2, label="portable invalid input exits 2")
        require(not invalid.stdout and "bad.txt:2" in invalid.stderr,
                "portable error must identify the input line and produce no partial stdout")

        for missing_name in ("runtime.mjs", "ipset.js"):
            missing_file = portable / missing_name
            backup = portable / (missing_name + ".missing-probe")
            require(not backup.exists(), f"unexpected portable test backup: {backup.name}")
            missing_file.rename(backup)
            try:
                missing = run(command + ["diff", "old.txt", "new.txt", "--json"],
                              cwd=caller, env=runtime_env, status=2,
                              label=f"portable missing {missing_name} exits 2")
                require(not missing.stdout and bool(missing.stderr.strip()),
                        f"missing {missing_name} must produce empty stdout and an error diagnostic")
            finally:
                backup.rename(missing_file)

        final_head = run([git, "rev-parse", "HEAD"], cwd=repo, label="verify source revision is unchanged").stdout.strip()
        require(final_head == source_head, "source revision changed while packaging")
        dirty = bool(run([git, "status", "--porcelain", "--untracked-files=normal"], cwd=repo,
                         label="record whether packaged source has uncommitted changes").stdout.strip())
        require(args.allow_dirty or not dirty, "source worktree changed while packaging; no assets replaced")
        dirty = source_dirty or dirty
        manifest = {
            "schema_version": 1, "status": "passed", "module": module, "version": version,
            "source_head": source_head, "source_dirty": dirty, "release_ready": not dirty,
            "toolchain": {"moon": moon_version, "node": node_version},
            "bundled_notices": {name: hashlib.sha256(content).hexdigest()
                                for name, content in core_notices.items()},
            "artifacts": [{"file": artifact.name, "sha256": digest(artifact), "bytes": artifact.stat().st_size}
                          for artifact in (library, cli)],
            "library_members": library_members, "cli_members": sorted(cli_members),
            "verification": {
                "official_library_zip_copied_unchanged": True,
                "library_archive_exclusions": "passed",
                "portable_core_license_and_notice": "preserved byte-for-byte from selected toolchain",
                "unpacked_library_direct_check": "wasm-gc, deny-warn, passed",
                "independent_archive_consumer": {"target": "wasm-gc", "passed": 1, "failed": 0},
                "portable_cli": {"node_path": "absolute", "PATH": "", "caller_cwd_preserved": True,
                                 "help_exit": 0, "changed_diff_exit": 1, "unchanged_diff_exit": 0,
                                 "stdin_normalize_exit": 0, "stdin_diff_exit": 1,
                                 "invalid_input_exit": 2, "missing_runtime_exit": 2,
                                 "missing_compiled_entry_exit": 2},
                "registry_installation": "not performed; local archive verification only",
            },
        }
        metadata = stage / "manifest.json"
        metadata.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        sums = stage / "SHA256SUMS"
        sums.write_text("".join(f"{digest(path)}  {path.name}\n" for path in (library, cli, metadata)), encoding="utf-8")
        for path in (library, cli, metadata, sums):
            os.replace(path, output / path.name)
        print(json.dumps({"status": "passed", "version": version,
                          "source_dirty": dirty, "release_ready": not dirty,
                          "artifacts": [library.name, cli.name],
                          "manifest": "manifest.json", "checksums": "SHA256SUMS",
                          "registry_installation": False}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, ValueError, subprocess.SubprocessError, zipfile.BadZipFile) as error:
        print(f"release packaging failed: {error}", file=sys.stderr)
        raise SystemExit(1)
