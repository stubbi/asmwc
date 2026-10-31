#!/usr/bin/env python3
"""Force native Linux pthread_create EAGAIN and verify the real executable."""
import itertools
import os
from pathlib import Path
import platform
import subprocess
import tempfile

from support import BIN_DIR, ROOT, compiler


def run(binary, args, folder, environment):
    result = subprocess.run(["asmwc", *args], executable=str(binary), cwd=folder,
                            env=environment, stdin=subprocess.DEVNULL,
                            capture_output=True, timeout=30)
    return result.returncode, result.stdout, result.stderr


def main():
    if platform.system() != "Linux":
        print("SKIP Linux pthread resource test: requires native Linux")
        return
    if os.sysconf("SC_NPROCESSORS_ONLN") < 2:
        print("SKIP Linux pthread resource test: requires two online CPUs")
        return
    with tempfile.TemporaryDirectory(prefix="asmwc-pthread-fallback-") as temporary:
        folder = Path(temporary)
        preload, trace = folder / "thread-fault.so", folder / "thread-attempts"
        subprocess.run([*compiler(), "-shared", "-fPIC", "-O2", "-Wall", "-Wextra",
                        "-Werror", str(ROOT / "tests/linux-thread-fault.c"), "-pthread",
                        "-o", str(preload)], check=True)
        fixtures = {"mixed": b"first\x00word second\nlast\xff",
                    "empty": b"", "binary": bytes(range(256)) * 17,
                    "long-line": b"x" * (1024 * 1024 + 33) + b"\nlast word"}
        for name, content in fixtures.items():
            (folder / name).write_bytes(content)
        normal = os.environ.copy()
        injected = normal.copy()
        injected["LD_PRELOAD"] = str(preload) + (
            ":" + normal["LD_PRELOAD"] if normal.get("LD_PRELOAD") else "")
        injected["ASMWC_TEST_THREAD_TRACE"] = str(trace)
        cases = 0
        for count in range(1, 6):
            for flags in itertools.combinations("clwmL", count):
                args = ["-" + "".join(flags), *fixtures]
                expected = run(BIN_DIR / "asmwc-rust", args, folder, normal)
                actual = run(BIN_DIR / "asmwc", args, folder, injected)
                assert actual == expected, (args, actual, expected)
                assert trace.is_file(), "pthread fault preload did not report its calls"
                assert int(trace.read_text()) > 0, "no pthread_create failure was exercised"
                trace.unlink()
                cases += 1
        print(f"PASS Linux pthread_create EAGAIN: {cases} count subsets match Rust; "
              "main-thread fallback completes without joining failed workers")


if __name__ == "__main__":
    main()
