#!/usr/bin/env python3
"""Differential end-to-end tests against pinned upstream ripwc.

Run from any directory. Only Python's standard library is required. The two
executables see identical argv[0], cwd, environment, fixtures and stdin. Counts
are deliberately compared to ripwc, whose behavior differs from POSIX wc.
"""

from __future__ import annotations

import argparse
import base64
import errno
import hashlib
import itertools
import json
import os
from pathlib import Path
import platform
import random
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass

ROOT = Path(__file__).resolve().parents[1]
# bench.py also imports this module directly by filename, outside tests' path.
BIN_DIR = Path(os.environ.get("ASMWC_BIN_DIR", ROOT / "bin")).expanduser().resolve()
RESULTS_DIR = Path(os.environ.get("ASMWC_RESULTS_DIR", ROOT / "results")).expanduser().resolve()
UPSTREAM_COMMIT = "de1a12e8e2d7c031404370773e5099b23ef01e95"
MIB = 1024 * 1024
COUNT_FLAGS = ("l", "w", "m", "c", "L")


@dataclass(frozen=True)
class Case:
    name: str
    args: tuple[str, ...]
    unordered_stderr: bool = False
    stdout_closed: bool = False
    stderr_closed: bool = False
    stdout_full: bool = False


def run(binary: Path, args: tuple[str, ...], cwd: Path, timeout: float = 30,
        stdout_closed=False, stderr_closed=False, stdout_full=False):
    env = os.environ.copy()
    env.update(LC_ALL="C", LANG="C", NO_COLOR="1", CLICOLOR="0", TERM="dumb")
    # clap derives its usage/error program name from argv[0]. Both programs
    # represent the same CLI even though their executable paths differ.
    if stdout_closed or stderr_closed or stdout_full:
        write_fds = []

        def closed_pipe():
            read_fd, write_fd = os.pipe()
            os.close(read_fd)  # No reader exists before either executable starts.
            write_fds.append(write_fd)
            return write_fd

        output = closed_pipe() if stdout_closed else subprocess.PIPE
        if stdout_full:
            output = os.open("/dev/full", os.O_WRONLY)
            write_fds.append(output)
        errors = closed_pipe() if stderr_closed else subprocess.PIPE
        try:
            process = subprocess.Popen(
                ["asmwc", *args], executable=str(binary), cwd=cwd, env=env,
                stdin=subprocess.DEVNULL, stdout=output, stderr=errors,
            )
        finally:
            for write_fd in write_fds:
                os.close(write_fd)
        try:
            stdout, stderr = process.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            process.kill()
            process.communicate()
            raise
        return subprocess.CompletedProcess(["asmwc", *args], process.returncode, stdout or b"", stderr or b"")
    return subprocess.run(
        ["asmwc", *args], executable=str(binary), cwd=cwd, env=env,
        stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=timeout, check=False,
    )


def result_data(result):
    return {
        "returncode": result.returncode,
        "stdout_base64": base64.b64encode(result.stdout).decode("ascii"),
        "stderr_base64": base64.b64encode(result.stderr).decode("ascii"),
    }


def equivalent(left, right, unordered_stderr=False, *, version_identity=False):
    if version_identity and (left.returncode, left.stdout, left.stderr) == (0, b"ripwc 1.0.0\n", b""):
        # The pinned oracle keeps its upstream identity. Require the complete
        # renamed version response; all other stdout remains byte-for-byte.
        return (right.returncode, right.stdout, right.stderr) == (0, b"asmwc 1.0.0\n", b"")
    stderr_left, stderr_right = left.stderr, right.stderr
    if unordered_stderr:
        # Only explicitly marked verbose cases may vary by Rayon scheduling.
        # Preserve multiplicity and exact line bytes; stdout remains ordered.
        stderr_left = sorted(stderr_left.splitlines(keepends=True))
        stderr_right = sorted(stderr_right.splitlines(keepends=True))
    return (left.returncode == right.returncode and left.stdout == right.stdout
            and stderr_left == stderr_right)


def make_cases(root: Path, quick: bool):
    fixtures = {}

    def put(name, data):
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        fixtures[name] = {"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}
        return name

    put("empty", b"")
    put("mixed", b"a\x00b c\td\ne\rf\vG\fH\xc2\xa0I\nlast")
    put("binary", bytes(range(256)) * 5 + b"\x00\x80\xff word\n")
    put("ascii", b"alpha beta\ngamma\tdelta\n")
    put("no-newline", b"  first second\tlast")
    put("whitespace", b" \t\n\r" * 17)
    put("not-ripwc-whitespace", b"\v\f\x85\xc2\xa0\xe2\x80\x83\xe2\x80\xa8")
    put("nul-only", b"\x00" * 65)
    put("utf8", "café λ 世界 🙂\nélève\t終".encode())
    put("malformed-utf8", b"\xff\xfe\xc0\xaf\xe2\x82\x80\xed\xa0\x80\xf4\x90\x80\x80\x00\n")
    put("long-line", b"x" * (2 * MIB + 71) + b"\nshort\n" + b"y" * 131)
    put("newline-only", b"\n" * 131)
    put("trailing-newline", b"a\n")
    put("trailing-space", b"a ")
    put("space name.txt", b"space name\n")
    put("é-世界.txt", "unicode path\n".encode())
    put("-dash", b"dash\n")
    put("-", b"literal dash\n")

    cases = []
    # Every one of the 31 nonempty subsets, including zero-output cases.
    for count in range(1, 6):
        for selected in itertools.combinations(COUNT_FLAGS, count):
            flag = "-" + "".join(selected)
            for name in ("mixed", "empty", "binary"):
                cases.append(Case(f"subset/{''.join(selected)}/{name}", (flag, name)))

    all_flags = "-lwmcL"
    for name in ("ascii", "no-newline", "whitespace", "not-ripwc-whitespace",
                 "nul-only", "utf8", "malformed-utf8", "long-line", "newline-only",
                 "trailing-newline", "trailing-space", "space name.txt", "é-世界.txt"):
        cases.append(Case(f"content/{name}", (all_flags, name)))
    cases += [Case("default/mixed", ("mixed",)),
              Case("default/empty", ("empty",)),
              Case("long-flags", ("--lines", "--words", "--chars", "--bytes",
                                  "--max-line-length", "mixed")),
              Case("option-after-file", ("ascii", "-L")),
              Case("dash-filename", ("--", "-dash")),
              Case("literal-dash-file", ("-",)),
              Case("repeated-file", (all_flags, "ascii", "ascii")),
              Case("totals/all", (all_flags, "ascii", "empty", "mixed")),
              Case("totals/default", ("no-newline", "binary", "empty")),
              Case("totals/zero", ("-l", "empty", "no-newline"))]

    # Cross transitions and trailing bytes at scalar, NEON and cache-line edges.
    lengths = (1, 7, 8, 15, 16, 17, 31, 32, 33, 63, 64, 65) if quick else (
        1, 2, 3, 7, 8, 9, 15, 16, 17, 23, 24, 25, 31, 32, 33, 47, 48,
        49, 63, 64, 65, 95, 96, 97, 127, 128, 129, 255, 256, 257)
    pattern = b"a \n\x00b\t\r\xff\v\f"  # includes all source whitespace and non-whitespace quirks
    for length in lengths:
        name = put(f"edges/n{length}", (pattern * ((length + 9) // 10))[:length])
        cases.append(Case(f"vector/{length}", (all_flags, name)))

    for boundary in ((MIB,) if quick else (512 * 1024, MIB, 2 * MIB)):
        for delta in (-1, 0, 1):
            length = boundary + delta
            data = bytearray((b"word \x00\xff\n" * ((length + 7) // 8))[:length])
            # A word and an unterminated line survive the 1 MiB reader boundary.
            for pos in range(max(0, MIB - 3), min(length, MIB + 4)):
                data[pos] = 0x78
            name = put(f"edges/io-{length}", bytes(data))
            cases.append(Case(f"io/{length}", (all_flags, name)))
    if not quick:
        rng = random.Random(0x5249505743)
        for index, length in enumerate((5, 511, 4097, 65537, MIB + 37)):
            name = put(f"random/{index}", rng.randbytes(length))
            cases.append(Case(f"random/{length}", (all_flags, name)))
        # A second independent seeded matrix exercises command/content choices,
        # especially maximum-line state across blocks and final partial vectors.
        for index in range(25):
            length = rng.choice((0, 1, 7, 15, 16, 17, 63, 64, 65, 4095,
                                 4096, 4097, MIB - 1, MIB, MIB + 1))
            alphabet = rng.choice((b"x", b" \t\n\r", b"\x00\x80\xff\n", b"a b\tc\rd\n\v\f"))
            block = bytes(rng.choice(alphabet) for _ in range(min(length, 4096)))
            data = (block * ((length + max(1, len(block)) - 1) // max(1, len(block))))[:length]
            name = put(f"random/combo-{index}", data)
            flags = rng.choice(((), ("-L",), ("-wL",), ("-lcL",), (all_flags,)))
            cases.append(Case(f"random-combo/{index}/{length}", (*flags, name)))

    # Creation order differs from lexical traversal order. Descendant directory
    # links are not followed by WalkDir, but root directory links are followed.
    (root / "tree").mkdir()
    put("tree/z-last", b"zeta\n")
    put("tree/a-first", b"alpha alpha\n")
    put("tree/m-dir/z-inner", b"inner\nline\n")
    put("tree/m-dir/a-inner", b"first")
    put("tree/b-empty", b"")
    put("tree/é-世界.txt", b"unicode descendant\n")
    # Rust Path.display() replaces invalid filename bytes. The file itself must
    # still be opened through its original bytes while its printed path is lossy.
    raw_name = os.fsencode(root / "tree") + b"/\xff-raw-name"
    try:
        with open(raw_name, "wb") as stream:
            stream.write(b"raw filename\n")
    except OSError as error:
        if error.errno not in (errno.EILSEQ, errno.EINVAL):
            raise
        # APFS rejects invalid UTF-8 names. Do not mistake filesystem inability
        # to create this fixture for either program passing a display test.
        fixtures["tree/<ff>-raw-name"] = {"status": "unsupported", "error": str(error),
                                           "reason": "filesystem rejects invalid UTF-8 filenames"}
    else:
        fixtures["tree/<ff>-raw-name"] = {"bytes": 13, "sha256": hashlib.sha256(b"raw filename\n").hexdigest(),
                                           "relative_path_base64": base64.b64encode(b"tree/\xff-raw-name").decode("ascii")}
        # Invalid bytes in a directory and its children must retain their raw
        # spelling for traversal and opening, including repeated replacements.
        raw_directory = os.fsencode(root / "tree") + b"/\xfe-invalid-dir"
        os.mkdir(raw_directory)
        for name in (b"\xc0-child", b"\xff\xfe-child", b"valid-child"):
            with open(raw_directory + b"/" + name, "wb") as stream:
                stream.write(b"raw descendant\x00 word\n")
        fixtures["tree/<fe>-invalid-dir"] = {"children": 3,
            "relative_path_base64": base64.b64encode(b"tree/\xfe-invalid-dir").decode("ascii")}
    (root / "empty-dir").mkdir()
    (root / "tree/file-link").symlink_to("a-first")
    (root / "tree/dir-link").symlink_to("m-dir", target_is_directory=True)
    (root / "tree/broken-link").symlink_to("not-there")
    (root / "root-dir-link").symlink_to("tree", target_is_directory=True)
    (root / "root-file-link").symlink_to("ascii")
    (root / "root-broken-link").symlink_to("not-there")
    for name, args in (
        ("sorted-tree", ("-r", all_flags, "tree")),
        ("default-tree", ("-r", "tree")),
        ("verbose-tree", ("-rv", "tree")),
        ("tree-byte-metadata", ("-rc", "tree")),
        ("trailing-slash", ("-r", all_flags, "tree/")),
        ("repeated-slash", ("-r", all_flags, "tree//")),
        ("interior-repeated-slash", ("-r", all_flags, "tree//m-dir//")),
        ("dot-prefix", ("-r", all_flags, "./tree")),
        ("dot-suffix", ("-r", all_flags, "tree/./")),
        ("parent-component", ("-r", all_flags, "tree/m-dir/../")),
        ("nonrecursive-trailing-slash", ("-c", "tree//")),
        ("root-directory-link", ("-r", all_flags, "root-dir-link")),
        ("root-file-link", (all_flags, "root-file-link")),
        ("root-broken-link", (all_flags, "root-broken-link")),
        ("root-link-no-recursion", (all_flags, "root-dir-link")),
        ("directory-no-recursion", ("tree",)),
        ("directory-byte-metadata", ("-c", "tree")),
        ("directory-all-flags", (all_flags, "tree")),
        ("empty-directory", ("-r", "empty-dir")),
        ("missing-only", ("missing-file",)),
        ("missing-recursive", ("-r", "missing-directory")),
        ("missing-between-files", (all_flags, "ascii", "missing-file", "mixed")),
        ("file-and-directory", ("-r", all_flags, "ascii", "tree")),
    ):
        cases.append(Case(f"paths/{name}", args))

    # Only >=512 KiB paths reach upstream's verbose write. Several such files
    # expose the one known nondeterministic component: stderr line ordering.
    put("large-a", b"a \n" * (MIB // 3 + 1))
    put("large-b", b"b\x00\n" * (MIB // 3 + 1))
    cases += [Case("verbose/small", ("-v", "ascii")),
              Case("verbose/large", ("-v", "large-a")),
              Case("verbose/parallel", ("-v", all_flags, "large-b", "large-a", "ascii"), True)]
    for delta in (-1, 0, 1):
        length = 512 * 1024 + delta
        name = put(f"verbose-{length}", b"v" * length)
        cases.append(Case(f"verbose/threshold-{length}", ("-v", "-c", name)))

    for name, args in (
        ("help-short", ("-h",)), ("help-long", ("--help",)),
        ("version-short", ("-V",)), ("version-long", ("--version",)),
        ("no-args", ()), ("flags-without-file", ("-lw",)),
        ("unknown-long", ("--not-an-option",)), ("unknown-short", ("-x",)),
        ("unknown-after-file", ("ascii", "--unknown")),
        ("duplicate-flag", ("-l", "-l", "ascii")),
        ("flag-value", ("--lines=true", "ascii")),
        ("help-with-path", ("--help", "ascii")),
        ("version-with-path", ("--version", "ascii")),
    ):
        cases.append(Case(f"cli/{name}", args))
    cases += [Case("stdout/broken-pipe-single", (all_flags, "ascii"), stdout_closed=True),
              Case("stdout/broken-pipe-totals", (all_flags, "ascii", "mixed"), stdout_closed=True)]
    for flag in ("-h", "--help", "-V", "--version"):
        cases.append(Case(f"stdout/closed-{flag}", (flag,), stdout_closed=True))
    cases += [Case("stderr/closed-verbose-large", ("-v", all_flags, "large-a"), stderr_closed=True),
              Case("stderr/closed-verbose-mixed", ("-v", all_flags, "large-b", "ascii", "large-a"), stderr_closed=True)]
    if platform.system() == "Linux":
        if Path("/dev/full").exists():
            cases += [Case("stdout/full-single", (all_flags, "ascii"), stdout_full=True),
                      Case("stdout/full-totals", (all_flags, "ascii", "mixed"), stdout_full=True)]
            for flag in ("-h", "--help", "-V", "--version"):
                cases.append(Case(f"stdout/full-{flag}", (flag,), stdout_full=True))
        else:
            fixtures["/dev/full"] = {"status": "unsupported", "reason": "device is unavailable"}
        if os.geteuid() != 0:
            put("unreadable-file", b"private content\n")
            (root / "unreadable-file").chmod(0)
            put("unreadable-directory/inside", b"private descendant\n")
            (root / "unreadable-directory").chmod(0)
            for name, args in (
                ("unreadable-file", (all_flags, "unreadable-file")),
                ("unreadable-file-metadata", ("-c", "unreadable-file")),
                ("unreadable-file-between", (all_flags, "ascii", "unreadable-file", "mixed")),
                ("unreadable-directory", ("-r", all_flags, "unreadable-directory")),
                ("unreadable-directory-no-recursion", (all_flags, "unreadable-directory")),
                ("unreadable-directory-metadata", ("-c", "unreadable-directory")),
            ):
                cases.append(Case(f"permissions/{name}", args))
        else:
            fixtures["permissions"] = {"status": "unsupported", "reason": "requires an unprivileged user"}
    return cases, fixtures


def binary_metadata(path):
    return {"path": str(path), "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}


def write_report(path, report):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report, indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rust", type=Path, default=BIN_DIR / "asmwc-rust")
    parser.add_argument("--asm", type=Path, default=BIN_DIR / "asmwc")
    parser.add_argument("--quick", action="store_true", help="retain all subsets, shorten edge/random matrix")
    parser.add_argument("--case", action="append", default=[], help="run names containing this substring (repeatable)")
    parser.add_argument("--list", action="store_true", help="list selected case names without running executables")
    parser.add_argument("--fail-fast", action="store_true")
    parser.add_argument("--timeout", type=float, default=30)
    parser.add_argument("--report", type=Path, default=RESULTS_DIR / "parity.json")
    args = parser.parse_args()
    args.rust, args.asm = args.rust.resolve(), args.asm.resolve()
    report = {"upstream_commit": UPSTREAM_COMMIT, "quick": args.quick,
              "comparison": "exact exit status/stdout/stderr except exact ripwc/asmwc 1.0.0 version identity; verbose parallel stderr sorted as byte lines",
              "started_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
              "cases": [], "failures": 0}
    if not args.list:
        missing = [str(p) for p in (args.rust, args.asm) if not p.is_file() or not os.access(p, os.X_OK)]
        if missing:
            report.update(status="unavailable", error="missing/non-executable binary", missing=missing)
            write_report(args.report, report)
            print("Parity unavailable: missing/non-executable binary: " + ", ".join(missing), file=sys.stderr)
            return 2
        report["binaries"] = {"rust": binary_metadata(args.rust), "asm": binary_metadata(args.asm)}
    with tempfile.TemporaryDirectory(prefix="asmwc-parity-") as temporary:
        root = Path(temporary)
        cases, fixtures = make_cases(root, args.quick)
        if args.case:
            cases = [case for case in cases if any(part in case.name for part in args.case)]
        if not cases:
            parser.error("no cases selected")
        if args.list:
            print("\n".join(case.name for case in cases))
            return 0
        report["fixtures"] = fixtures
        report["fixture_limits"] = {name: info for name, info in fixtures.items()
                                    if info.get("status") == "unsupported"}
        for name, info in report["fixture_limits"].items():
            print(f"Fixture unavailable: {name}: {info['reason']}", flush=True)
        started = time.monotonic()
        for index, case in enumerate(cases, 1):
            record = {"name": case.name, "argv": list(case.args),
                      "unordered_stderr": case.unordered_stderr, "stdout_closed": case.stdout_closed,
                      "stderr_closed": case.stderr_closed, "stdout_full": case.stdout_full}
            try:
                rust = run(args.rust, case.args, root, args.timeout, case.stdout_closed, case.stderr_closed, case.stdout_full)
                asm = run(args.asm, case.args, root, args.timeout, case.stdout_closed, case.stderr_closed, case.stdout_full)
                passed = equivalent(rust, asm, case.unordered_stderr, version_identity=True)
                record["passed"] = passed
                if not passed:
                    record.update(rust=result_data(rust), asm=result_data(asm))
                    print(f"FAIL {case.name}: Rust exit={rust.returncode}, assembly exit={asm.returncode}", file=sys.stderr)
                    for stream in ("stdout", "stderr"):
                        left, right = getattr(rust, stream), getattr(asm, stream)
                        if left != right:
                            print(f"  {stream}: Rust {left[:1500]!r}\n  assembly {right[:1500]!r}", file=sys.stderr)
            except (OSError, subprocess.TimeoutExpired) as error:
                passed = False
                record.update(passed=False, error=str(error))
                print(f"FAIL {case.name}: {error}", file=sys.stderr)
            report["cases"].append(record)
            if not passed:
                report["failures"] += 1
                if args.fail_fast:
                    break
            if index % 25 == 0:
                print(f"Parity: {index}/{len(cases)} cases, {report['failures']} failures", flush=True)
        report.update(status="passed" if not report["failures"] else "failed",
                      elapsed_seconds=time.monotonic() - started,
                      selected_cases=len(cases), executed_cases=len(report["cases"]))
    write_report(args.report, report)
    print(f"Parity {report['status']}: {report['executed_cases']} cases, {report['failures']} failures; {args.report}")
    return 1 if report["failures"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
