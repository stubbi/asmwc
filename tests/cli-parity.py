#!/usr/bin/env python3
"""Compare parser output, diagnostics, and exits against the pinned Rust binary.

The C program below is an isolated test harness for inspecting assembly globals;
it is never part of either product executable.
"""
from pathlib import Path
import os
import random
import subprocess
import sys
import tempfile

from support import BIN_DIR, compiler, native_source

RUST = BIN_DIR / "ripwc-rust"
HARNESS = r"""
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
extern void ripwc_parse(int, char **);
extern uint64_t ripwc_flags, ripwc_recursive, ripwc_verbose, ripwc_nargs;
extern char **ripwc_paths;
int main(int argc, char **argv) {
    ripwc_parse(argc, argv);
    if (getenv("RIPWC_CLI_DUMP")) {
        printf("%llu %llu %llu %llu\n", (unsigned long long)ripwc_flags,
               (unsigned long long)ripwc_recursive,
               (unsigned long long)ripwc_verbose, (unsigned long long)ripwc_nargs);
        for (uint64_t i = 0; i < ripwc_nargs; ++i) puts(ripwc_paths[i]);
    }
    return 0;
}
"""


def run(binary, args, name=b"ripwc", dump=False):
    env = dict(os.environ)
    env.pop("RIPWC_CLI_DUMP", None)
    if dump:
        env["RIPWC_CLI_DUMP"] = "1"
    result = subprocess.run([name, *args], executable=binary, env=env,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return result.returncode, result.stdout, result.stderr


with tempfile.TemporaryDirectory(prefix="ripwc-cli-") as temp:
    temp = Path(temp)
    source, harness = temp / "harness.c", temp / "harness"
    source.write_text(HARNESS)
    subprocess.run([*compiler(), "-Wall", "-Wextra", "-Werror", str(source), str(native_source("cli.S")), "-o",
                    str(harness)], check=True)
    cases = [[], [b"--help"], [b"-h"], [b"--version"], [b"-V"],
             [b"--wat"], [b"-z"], [b"-cc", b"missing"],
             [b"-c", b"--bytes", b"missing"], [b"--bytes=true"],
             [b"--verbose"], [b"-vcwmLrr"], [b"-c"], [b"--", b"-z"],
             [b"--recursive"], [b"-hX"], [b"--ver"], [b"--byte"],
             [b"-"], [b"--bytes", b"--", b"-"], [b"--bytes="],
             [b"--Bytes"], [b"--lines", b"--words"], [b"-clx"],
             [b"missing", b"-cc"], [b"-rwclmvL"], [b"-vr"],
             [b"-V=1"], [b"--help=x"], [b"--version=1"],
             [b"--bytes", b"--bytes=true"], [b"--chars", b"--bad"],
             [b"--bytes", b"--verbose"], [b"--bytes", b"--byte"],
             [b"missing", b"--chars", b"--byte"], [b"--Bytes=x"],
             [b"-foo"], [b"--foo=bar"], [b"---"], [b"--max_line_length"],
             [b"--lines", b"--linez"], [b"--recursive", b"--recurse"],
             [b"--", b""], [b"--", b"--"], [b"--\x1b[31mfoo"]]
    names = [b"bytes", b"chars", b"lines", b"words", b"max-line-length",
             b"recursive", b"help", b"version"]
    for name in names:
        for i in range(len(name) + 1):
            cases.extend([[b"--" + name[:i] + name[i + 1:]],
                          [b"--" + name[:i] + b"x" + name[i:]],
                          [b"--" + name[:i] + "é".encode() + name[i:]]])
    for value in [b"\xff", b"\xc0", b"\xc1", b"\xc2", b"\xe0\x80",
                  b"\xed\xa0", b"\xe1\x80", b"\xf0\x90\x80",
                  b"\xf4\x90\x80\x80", b"\xf5", "€".encode()]:
        for prefix in [b"", b"-", b"--", b"--bytes="]:
            cases.extend([[prefix + value], [prefix + value, b"--help"],
                          [prefix + value, b"--bad"]])
    program_names = [b".", b"..", b"/", b"//", b"/foo/.", b"/foo/..",
                     b"\xff", b"foo\xff", b"--", b"foo//././/", b"\xff/foo"]
    # clap's plain-text writer strips controls and terminal escape sequences.
    # Keep the upstream process as the oracle, including state that carries
    # from an incomplete escape into the next diagnostic text fragment.
    for control in (bytes([value]) for value in (*range(1, 32), 127)):
        cases.extend([[b"--" + control], [b"-" + control],
                      [b"--bytes=" + control]])
        program_names.append(b"rip" + control + b"wc")
    sequences = [
        b"\x1b[31mred\x1b[0m", b"\x1b[2J", b"\x1b[?25l",
        b"\x1b]0;title\x07", b"\x1b]0;title\x1b\\",
        b"\x1b]8;;https://example.test\x1b\\label\x1b]8;;\x1b\\",
        b"\x1bP1;2|payload\x1b\\", b"\x1b_hidden\x1b\\",
        b"\x1b^hidden\x1b\\", b"\x1bXhidden\x1b\\",
        b"\x1b[31\x18mTAIL", b"\x1b]hidden\x1aTAIL",
        b"\x1bPpayload\xc3\x9cTAIL", b"\x1b\xf0\x9f\x98\x80hello",
    ]
    for sequence in sequences:
        cases.extend([[b"--" + sequence + b"unknown"],
                      [b"-" + sequence + b"x"],
                      [b"--bytes=" + sequence + b"value"]])
        program_names.append(b"rip" + sequence + b"wc")
    for incomplete in (b"\x1b", b"\x1b[", b"\x1b[31", b"\x1b]0;title",
                       b"\x1bPpayload", b"\x1b_hidden", b"\x1b^hidden",
                       b"\x1bXhidden"):
        cases.extend([[b"--unknown" + incomplete], [b"-" + incomplete],
                      [b"--bytes=value" + incomplete]])
        program_names.append(b"ripwc" + incomplete)
    # A valid unknown short scalar is reported alone even when later bytes are
    # malformed. A malformed first scalar retains clap's lossy remainder.
    for tail in (b"\xff", b"\xc0", b"\xc2", b"\xe0\x80", b"\xed\xa0",
                 b"\xe1\x80", b"\xf0\x90\x80", b"\xf4\x90\x80\x80"):
        for prefix in (b"-x", "-é".encode(), b"-cX", "-🙂".encode(), "-w€".encode()):
            cases.append([prefix + tail])
        cases.extend([[b"-" + tail + b"x"], [b"-c" + tail + b"x"]])
    random.seed(7)
    tokens = [b"-c", b"-m", b"-l", b"-w", b"-L", b"-r", b"-v",
              b"--bytes", b"--chars", b"--lines", b"--words", b"--help",
              b"--version", b"--verbose", b"--byte", b"--ver", b"--z",
              b"-z", b"-crL", b"--bytes=true", b"--help=x", b"--",
              b"missing", b"", b"-", b"\xff", b"-\xffx", b"--\xff"]
    cases.extend(random.choices(tokens, k=random.randrange(1, 7))
                 for _ in range(200))
    failures = []
    for args in cases:
        actual, expected = run(harness, args), run(RUST, args)
        if actual != expected:
            failures.append((args, b"ripwc", actual, expected))
    for name in program_names:
        actual, expected = run(harness, [b"--wat"], name), run(RUST, [b"--wat"], name)
        if actual != expected:
            failures.append(([b"--wat"], name, actual, expected))
    for mask in range(128):
        chosen = [char for i, char in enumerate("cmlwLrv") if mask >> i & 1]
        random.Random(mask).shuffle(chosen)
        args = [b"-" + "".join(chosen).encode()] if chosen else []
        args.append(b"/nonexistent/ripwc-cli-test")
        actual = run(harness, args, dump=True)
        expected = (f"{mask & 31 or 13} {(mask >> 5) & 1} "
                    f"{(mask >> 6) & 1} 1\n/nonexistent/ripwc-cli-test\n").encode()
        assert actual == (0, expected, b""), (mask, actual, expected)
    if failures:
        # repr keeps terminal escape/control bytes confined to captured output.
        for args, name, actual, expected in failures[:6]:
            print(f"FAIL argv={args!r} argv0={name!r}\n"
                  f"  assembly={actual!r}\n  Rust={expected!r}", file=sys.stderr)
        raise AssertionError(f"CLI parity: {len(failures)}/{len(cases) + len(program_names)} "
                             "Rust differential cases failed; 128 flag states passed")
    print(f"CLI parity: {len(cases) + len(program_names)} Rust differential cases; "
          "128 assembly flag-state combinations passed.")
