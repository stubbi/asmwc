#!/usr/bin/env python3
"""Capture the tiny CLI example and render deterministic README SVGs.

Run ``make`` first, then ``python3 tools/render_demo_graphics.py``.
Use ``--check`` to recapture the example and verify the checked-in assets.
Only Python's standard library is required; no timings are collected.
"""
from __future__ import annotations

import argparse
from html import escape
import json
from pathlib import Path
import subprocess
from tempfile import TemporaryDirectory
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "docs" / "assets"
BACKGROUND = "#0b1220"
CARD = "#111c2f"
TEAL = "#4adbc8"
TEXT = "#cbd5e1"
WHITE = "#f8fafc"
MUTED = "#94a3b8"
BORDER = "#26364c"
SANS = "-apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif"
MONO = "ui-monospace, 'SFMono-Regular', Menlo, Consolas, monospace"
COMMANDS = (
    "printf 'hello assembly\\n' > example.txt",
    "./bin/asmwc example.txt",
    "./bin/asmwc -lwmcL example.txt",
)


def capture_session() -> dict:
    binary = ROOT / "bin" / "asmwc"
    if not binary.is_file():
        raise FileNotFoundError("bin/asmwc is missing; run make before capturing the demo")
    session = []
    with TemporaryDirectory(prefix="asmwc-readme-") as directory:
        temporary = Path(directory)
        (temporary / "bin").mkdir()
        (temporary / "bin" / "asmwc").symlink_to(binary)
        for command in COMMANDS:
            result = subprocess.run(
                ["/bin/sh", "-c", command], cwd=temporary,
                capture_output=True, text=True, check=False,
            )
            if result.returncode or result.stderr:
                raise RuntimeError(f"demo command failed: {command!r}: {result.stderr}")
            session.append({
                "command": command,
                "stdout": result.stdout,
                "stderr": result.stderr,
                "exit_code": result.returncode,
            })
        contents = (temporary / "example.txt").read_bytes()
    return {
        "schema_version": 1,
        "description": "Actual CLI output captured in an isolated temporary directory.",
        "input": {
            "path": "example.txt",
            "content": contents.decode("ascii"),
            "byte_length": len(contents),
        },
        "session": session,
    }


def start_svg(height: int, title: str, description: str) -> list[str]:
    return [
        '<?xml version="1.0" encoding="UTF-8"?>',
        f'<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="{height}" '
        f'viewBox="0 0 1200 {height}" role="img" aria-labelledby="title desc">',
        f'  <title id="title">{escape(title)}</title>',
        f'  <desc id="desc">{escape(description)}</desc>',
        f'  <rect width="1200" height="{height}" rx="20" fill="{BACKGROUND}"/>',
    ]


def text(x: int, y: int, content: str, size: int = 20, color: str = TEXT,
         *, family: str = SANS, weight: int = 400, anchor: str = "start") -> str:
    return (
        f'  <text x="{x}" y="{y}" font-family="{escape(family, quote=True)}" '
        f'font-size="{size}" font-weight="{weight}" fill="{color}" '
        f'text-anchor="{anchor}" xml:space="preserve">{escape(content)}</text>'
    )


def rect(x: int, y: int, width: int, height: int, *, fill: str = CARD,
         stroke: str = BORDER, radius: int = 12) -> str:
    return (
        f'  <rect x="{x}" y="{y}" width="{width}" height="{height}" '
        f'rx="{radius}" fill="{fill}" stroke="{stroke}"/>'
    )


def line(x1: int, y1: int, x2: int, y2: int, color: str = BORDER) -> str:
    return f'  <path d="M{x1} {y1}H{x2}" fill="none" stroke="{color}"/>' if y1 == y2 else (
        f'  <path d="M{x1} {y1}L{x2} {y2}" fill="none" stroke="{color}"/>'
    )


def arrow(x1: int, x2: int, y: int) -> list[str]:
    return [
        f'  <path d="M{x1} {y}H{x2 - 7}" fill="none" stroke="{TEAL}" stroke-width="2"/>',
        f'  <path d="M{x2 - 8} {y - 5}L{x2} {y}L{x2 - 8} {y + 5}" fill="none" '
        f'stroke="{TEAL}" stroke-width="2" stroke-linejoin="round"/>',
    ]


def finish_svg(parts: list[str]) -> str:
    result = "\n".join(parts + ["</svg>", ""])
    ET.fromstring(result)
    return result


def terminal_svg(captured: dict) -> str:
    session = captured["session"]
    parts = start_svg(
        420, "asmwc: a captured command-line demonstration",
        "A real invocation on example.txt containing hello assembly followed by LF, "
        "15 bytes in total. The default output reports one line, two words and 15 bytes. "
        "Selecting -lwmcL also reports 15 nonzero bytes as chars and maximum line length 14. "
        "The adjacent demo-session.json preserves every command, stdout, stderr and exit code.",
    )
    parts += [
        text(32, 46, "asmwc on a 15-byte file", 28, WHITE, weight=600),
        rect(944, 21, 224, 34, fill=BACKGROUND, radius=17),
        text(1056, 43, "ACTUAL CLI OUTPUT", 14, TEAL, weight=600, anchor="middle"),
        line(32, 73, 1168, 73),
        text(32, 114, "$", 22, TEAL, family=MONO),
        text(59, 114, session[0]["command"], 22, WHITE, family=MONO),
        rect(895, 91, 273, 34, radius=8),
        text(1031, 114, "example.txt · 15 bytes · LF", 16, TEXT, anchor="middle"),
        text(32, 158, "DEFAULT COUNTS", 13, MUTED, weight=600),
        text(32, 188, "$", 22, TEAL, family=MONO),
        text(59, 188, session[1]["command"], 22, WHITE, family=MONO),
        text(59, 222, session[1]["stdout"].removesuffix("\n"), 22, TEXT, family=MONO),
        text(32, 267, "ALL FIVE COUNTS", 13, MUTED, weight=600),
        text(32, 297, "$", 22, TEAL, family=MONO),
        text(59, 297, session[2]["command"], 22, WHITE, family=MONO),
        text(59, 331, session[2]["stdout"].removesuffix("\n"), 22, TEXT, family=MONO),
        line(32, 364, 1168, 364),
        text(32, 397, "“chars” counts nonzero bytes. Maximum line length excludes LF.", 18, MUTED),
    ]
    return finish_svg(parts)


def pipeline_svg() -> str:
    parts = start_svg(
        344, "asmwc: the macOS single-file read and scan pipeline",
        "On macOS only, this path is selected for exactly one collected task, with word counting enabled "
        "and saved size at least 8 MiB. The reader issues sequential reads into four reusable "
        "1 MiB buffers. One serial NEON scanning worker processes the buffers in order, "
        "preserving word and line state across chunks. Reads overlap queued scans. All "
        "scans in the batch finish before buffers are reused. Counts are finalized once at EOF.",
    )
    parts += [
        text(30, 43, "asmwc on macOS: overlapped reading and counting", 27, WHITE, weight=600),
        text(30, 75, "Eligible path: exactly one task · word counting enabled · saved size ≥ 8 MiB", 18, MUTED),
        rect(30, 103, 209, 114),
        text(134, 138, "Sequential reader", 22, WHITE, weight=600, anchor="middle"),
        text(134, 169, "owns the file descriptor", 16, TEXT, anchor="middle"),
        text(134, 195, "read, then enqueue", 16, MUTED, anchor="middle"),
        rect(283, 103, 290, 114),
        text(428, 132, "4 reusable buffers", 22, WHITE, weight=600, anchor="middle"),
    ]
    for index in range(4):
        x = 298 + index * 67
        parts += [
            rect(x, 147, 59, 55, fill=BACKGROUND, radius=7),
            text(x + 29, 169, f"B{index}", 17, TEAL, family=MONO, weight=600, anchor="middle"),
            text(x + 29, 190, "1 MiB", 14, TEXT, anchor="middle"),
        ]
    parts += [
        rect(617, 103, 290, 114),
        text(762, 138, "Serial NEON scanner", 22, WHITE, weight=600, anchor="middle"),
        text(762, 169, "one ordered worker", 17, TEXT, anchor="middle"),
        text(762, 195, "word + line state carry", 17, TEAL, anchor="middle"),
        rect(951, 103, 219, 114),
        text(1060, 138, "Final counts", 22, WHITE, weight=600, anchor="middle"),
        text(1060, 175, "finalize once at EOF", 16, TEXT, anchor="middle"),
    ]
    parts += arrow(247, 275, 160)
    parts += arrow(581, 609, 160)
    parts += arrow(915, 943, 160)
    parts += [
        # A shared band describes concurrency without suggesting parallel scanners.
        rect(30, 239, 877, 38, fill=BACKGROUND, radius=8),
        text(468, 264, "The reader fills the next buffer while queued buffers scan.", 18, TEXT, anchor="middle"),
        f'  <path d="M762 283V301H428V283" fill="none" stroke="{TEAL}" stroke-width="2"/>',
        f'  <path d="M423 290L428 282L433 290" fill="none" stroke="{TEAL}" '
        'stroke-width="2" stroke-linejoin="round"/>',
        text(595, 329, "Wait for the whole batch before reusing buffers.", 17, MUTED, anchor="middle"),
    ]
    return finish_svg(parts)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="verify assets without writing them")
    args = parser.parse_args()
    captured = capture_session()
    outputs = {
        "demo-session.json": json.dumps(captured, indent=2, ensure_ascii=True) + "\n",
        "terminal-demo.svg": terminal_svg(captured),
        "pipeline.svg": pipeline_svg(),
    }
    if args.check:
        stale = [name for name, content in outputs.items()
                 if not (ASSETS / name).is_file() or (ASSETS / name).read_text() != content]
        if stale:
            parser.exit(1, "README demo assets need regeneration: " + ", ".join(stale) + "\n")
        print("CLI capture and both README SVGs match the checked-in assets.")
    else:
        ASSETS.mkdir(parents=True, exist_ok=True)
        for name, content in outputs.items():
            (ASSETS / name).write_text(content)
        print("Captured the CLI session and rendered both README SVGs.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
