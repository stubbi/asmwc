"""Native test paths shared by the standalone differential harnesses."""
from pathlib import Path
import os
import platform
import shlex

ROOT = Path(__file__).resolve().parents[1]
BIN_DIR = Path(os.environ.get("ASMWC_BIN_DIR", ROOT / "bin")).expanduser().resolve()
RESULTS_DIR = Path(os.environ.get("ASMWC_RESULTS_DIR", ROOT / "results")).expanduser().resolve()


def native_source(name):
    system, machine = platform.system(), platform.machine().lower()
    if system == "Darwin" and machine in ("arm64", "aarch64"):
        return ROOT / "src" / name
    if system == "Linux":
        architectures = {"x86_64": "x86_64", "amd64": "x86_64",
                         "aarch64": "aarch64", "arm64": "aarch64"}
        if machine in architectures:
            return ROOT / "src/linux" / architectures[machine] / name
    raise SystemExit(f"Unsupported native test target: {system} {machine}")


def compiler():
    return shlex.split(os.environ.get("CC", "cc"))
