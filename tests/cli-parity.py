#!/usr/bin/env python3
"""Compare parser output, diagnostics, and exits against the pinned Rust binary.

The C program below is an isolated test harness for inspecting assembly globals;
it is never part of either product executable.
"""
from pathlib import Path
import os
import random
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
RUST = ROOT / "bin/ripwc-rust"
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
        printf("%llu %llu %llu %llu\n", ripwc_flags, ripwc_recursive,
               ripwc_verbose, ripwc_nargs);
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
    subprocess.run(["clang", str(source), str(ROOT / "src/cli.S"), "-o",
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
             [b"--", b""], [b"--", b"--"]]
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
    random.seed(7)
    tokens = [b"-c", b"-m", b"-l", b"-w", b"-L", b"-r", b"-v",
              b"--bytes", b"--chars", b"--lines", b"--words", b"--help",
              b"--version", b"--verbose", b"--byte", b"--ver", b"--z",
              b"-z", b"-crL", b"--bytes=true", b"--help=x", b"--",
              b"missing", b"", b"-", b"\xff", b"-\xffx", b"--\xff"]
    cases.extend(random.choices(tokens, k=random.randrange(1, 7))
                 for _ in range(200))
    for args in cases:
        actual, expected = run(harness, args), run(RUST, args)
        assert actual == expected, (args, actual, expected)
    for name in [b".", b"..", b"/", b"//", b"/foo/.", b"/foo/..",
                 b"\xff", b"foo\xff", b"--", b"foo//././/", b"\xff/foo"]:
        assert run(harness, [b"--wat"], name) == run(RUST, [b"--wat"], name)
    for mask in range(128):
        chosen = [char for i, char in enumerate("cmlwLrv") if mask >> i & 1]
        random.Random(mask).shuffle(chosen)
        args = [b"-" + "".join(chosen).encode()] if chosen else []
        args.append(b"/nonexistent/ripwc-cli-test")
        actual = run(harness, args, dump=True)
        expected = (f"{mask & 31 or 13} {(mask >> 5) & 1} "
                    f"{(mask >> 6) & 1} 1\n/nonexistent/ripwc-cli-test\n").encode()
        assert actual == (0, expected, b""), (mask, actual, expected)
    print(f"CLI parity: {len(cases) + 11} Rust differential cases; "
          "128 assembly flag-state combinations passed.")
