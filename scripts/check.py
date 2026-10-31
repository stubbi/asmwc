#!/usr/bin/env python3
"""Portable syntax and source-hygiene checks using the standard library only."""
import ast
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
TEXT_SUFFIXES = {".py", ".sh", ".S", ".c", ".md", ".toml", ".yml", ".yaml"}
TOP_LEVEL = {"Makefile", ".editorconfig", ".gitattributes", ".gitignore"}
SOURCE_DIRS = ("src", "tests", "scripts", "tools", "docs", ".github")


def main():
    paths = {path for path in ROOT.iterdir()
             if path.is_file() and (path.suffix in TEXT_SUFFIXES or path.name in TOP_LEVEL)}
    for directory in SOURCE_DIRS:
        paths.update(path for path in (ROOT / directory).rglob("*")
                     if path.is_file() and path.suffix in TEXT_SUFFIXES)
    failures = []
    for path in sorted(paths):
        name = path.relative_to(ROOT)
        try:
            source = path.read_text(encoding="utf-8")
        except UnicodeError as error:
            failures.append(f"{name}: {error}")
            continue
        if source and not source.endswith("\n"):
            failures.append(f"{name}: missing final newline")
        for number, line in enumerate(source.splitlines(), 1):
            if line.rstrip(" \t") != line:
                failures.append(f"{name}:{number}: trailing whitespace")
            if line.startswith(("<<<<<<< ", "=======", ">>>>>>> ")):
                failures.append(f"{name}:{number}: unresolved merge marker")
        if path.suffix == ".py":
            try:
                ast.parse(source, filename=str(name))
            except SyntaxError as error:
                failures.append(str(error))
        elif path.suffix == ".sh":
            result = subprocess.run(["sh", "-n", str(path)], capture_output=True, text=True)
            if result.returncode:
                failures.append(f"{name}: {result.stderr.strip()}")
    if failures:
        print("\n".join(failures), file=sys.stderr)
        return 1
    print(f"PASS syntax and whitespace checks ({len(paths)} first-party text files)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
