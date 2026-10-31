#!/usr/bin/env python3
"""Exercise the public executable's identity independently of the Rust oracle."""
import argparse
from pathlib import Path
import subprocess

from support import BIN_DIR


def run(binary, args, name=b"asmwc"):
    # Python's posix_spawn rejects empty argv[0]; use fork/exec for that fixture.
    result = subprocess.run([name, *args], executable=binary,
                            start_new_session=(name == b""),
                            stdin=subprocess.DEVNULL, capture_output=True,
                            timeout=10)
    return result.returncode, result.stdout, result.stderr


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--asm", type=Path, default=BIN_DIR / "asmwc")
    args = parser.parse_args()
    binary = args.asm.resolve()

    # Version is the product identity, even when a caller chooses another name.
    for flag in (b"--version", b"-V"):
        for name in (b"asmwc", b"/local/tools/word-count"):
            actual = run(binary, [flag], name)
            assert actual == (0, b"asmwc 1.0.0\n", b""), (flag, name, actual)

    # Usage and errors use the invocation's basename, including renamed links.
    invocations = [(b"asmwc", b"asmwc"),
                   (b"/local/tools/word-count", b"word-count")]
    invocations += [(name, b"asmwc") for name in
                    (b"", b".", b"..", b"/", b"//", b"/foo/..", b"\xff", b"foo\xff")]
    for name, basename in invocations:
        short = run(binary, [b"-h"], name)
        long = run(binary, [b"--help"], name)
        assert short == long, (name, short, long)
        status, output, error = long
        usage = b"Usage: " + basename + b" [OPTIONS] <FILE>...\n"
        assert status == 0 and not error and usage in output, (name, long)
        invalid = run(binary, [b"--unknown"], name)
        assert invalid[0] == 2 and not invalid[1] and usage in invalid[2], (name, invalid)

    # A normal path-based launch also advertises the installed executable name.
    actual = subprocess.run([str(binary), "--version"], stdin=subprocess.DEVNULL,
                            capture_output=True, timeout=10)
    assert (actual.returncode, actual.stdout, actual.stderr) == (0, b"asmwc 1.0.0\n", b"")
    print("CLI identity: asmwc version aliases and invocation-derived usage passed.")


if __name__ == "__main__":
    main()
