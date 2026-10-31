#!/usr/bin/env python3
"""Render the README benchmark chart from committed measurement evidence.

Optional authoring dependency: requirements-graphics.txt. No dependency is
added to building, testing or running ripwc itself.
"""
from __future__ import annotations

import argparse
from io import BytesIO
import json
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "benchmarks/results/apple-m3-2026-10-31/benchmark.json"
OUTPUT = ROOT / "docs/assets/benchmark.svg"
SELECTION = (
    ("text/default", "Text · default"),
    ("binary/default", "Binary · default"),
    ("text/all-counts", "Text · all five fields"),
    ("binary/all-counts", "Binary · all five fields"),
)


def render() -> bytes:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.patches import Patch

    report = json.loads(SOURCE.read_text())
    cases = {case["name"]: case for case in report["cases"]}
    if report["status"] != "passed" or report["runs_per_implementation"] != 24:
        raise ValueError("chart requires the captured successful 24-run study")
    selected = [(cases[key], label) for key, label in SELECTION]
    for case, _ in selected:
        if not case["preflight"]["passed"] or case["input_bytes"] != 128 * 1024 * 1024:
            raise ValueError(f"unexpected chart input: {case['name']}")

    background, panel = "#0b1220", "#111c2f"
    foreground, muted = "#f8fafc", "#a8b7ce"
    series = (
        ("rust", "Rust · native release", "#9aa8bd", -0.31),
        ("previous_assembly", "First assembly", "#7e8de6", 0.0),
        ("assembly", "Optimized assembly", "#4adbc8", 0.31),
    )
    with plt.rc_context({
        "font.family": "DejaVu Sans", "font.size": 13,
        "svg.fonttype": "path", "svg.hashsalt": "ripwc-asm-readme-v1",
        "figure.facecolor": background, "axes.facecolor": background,
        "text.color": foreground, "axes.labelcolor": muted,
        "xtick.color": muted, "ytick.color": foreground,
    }):
        figure = plt.figure(figsize=(12, 7.6), dpi=100)
        axes = figure.add_axes((0.235, 0.20, 0.595, 0.58))
        centers = [index * 1.55 for index in range(len(selected))]
        for index, center in enumerate(centers):
            if index % 2 == 0:
                axes.axhspan(center - 0.64, center + 0.64, color=panel, zorder=0)
        for key, label, color, offset in series:
            values = [case["statistics"][key]["median_seconds"] * 1000 for case, _ in selected]
            positions = [center + offset for center in centers]
            axes.barh(positions, values, height=0.22, color=color, zorder=3)
            for position, value in zip(positions, values):
                axes.text(value + 1.8, position, f"{value:.3f}", color=color,
                          va="center", fontsize=11.4, fontweight="normal")
        axes.set_xlim(0, 143)
        axes.set_ylim(centers[-1] + 0.72, -0.72)
        axes.set_xticks((0, 25, 50, 75, 100, 125))
        axes.set_xlabel("Median execution time (ms) · lower is better", labelpad=17, fontsize=12)
        axes.set_yticks(centers, [label for _, label in selected], fontsize=12)
        axes.tick_params(axis="y", length=0, pad=15)
        axes.tick_params(axis="x", length=0, pad=10)
        axes.grid(axis="x", color="#26354b", linewidth=0.7, zorder=1)
        axes.axvline(0, color="#52637e", linewidth=1, zorder=2)
        for spine in axes.spines.values():
            spine.set_visible(False)

        figure.text(0.065, 0.955, "RECORDED MEASUREMENTS", color="#4adbc8", fontsize=10,
                    fontweight="bold", va="top")
        figure.text(0.065, 0.902, "Whole-program execution time", fontsize=25,
                    fontweight="bold", va="top")
        figure.text(0.065, 0.848, "Same workload, captured outputs checked before and during timing.",
                    color=muted, fontsize=11.8, va="top")
        figure.legend(handles=[Patch(facecolor=color, label=label) for _, label, color, _ in series],
                      loc="upper left", bbox_to_anchor=(0.058, 0.810), ncol=3, frameon=False,
                      labelcolor=foreground, handlelength=1.2, handleheight=0.75,
                      columnspacing=2.4, fontsize=11.8)
        axes.text(1.11, 1.04, "Rust / optimized", transform=axes.transAxes, color=muted,
                  fontsize=10.7, ha="center", va="bottom")
        for center, (case, _) in zip(centers, selected):
            axes.text(1.11, center, f"{case['rust_over_assembly_median']:.2f}×",
                      transform=axes.get_yaxis_transform(), color="#4adbc8",
                      fontsize=21, fontweight="bold", va="center", ha="center")
        figure.text(0.065, 0.070, "Apple M3 · macOS 15.6.1 · 128 MiB · warm filesystem cache · 24 runs per executable",
                    color=muted, fontsize=10.7)
        figure.text(0.065, 0.036, "31 Oct 2026 · This machine and corpus only. Full samples, build settings and limitations are linked in the README.",
                    color="#778ba8", fontsize=9.7)
        buffer = BytesIO()
        figure.savefig(buffer, format="svg", metadata={"Date": None, "Creator": "ripwc-asm / Matplotlib"})
        plt.close(figure)

    ET.register_namespace("", "http://www.w3.org/2000/svg")
    ET.register_namespace("xlink", "http://www.w3.org/1999/xlink")
    tree = ET.fromstring(buffer.getvalue())
    namespace = "{http://www.w3.org/2000/svg}"
    tree.set("role", "img")
    tree.set("aria-labelledby", "benchmark-title benchmark-description")
    title = ET.Element(namespace + "title", {"id": "benchmark-title"})
    title.text = "Recorded ripwc whole-program runtimes on Apple M3"
    description = ET.Element(namespace + "desc", {"id": "benchmark-description"})
    details = [
        label + ": " + ", ".join(
            f"{case['statistics'][key]['median_seconds'] * 1000:.3f}"
            for key in ("rust", "previous_assembly", "assembly")
        ) + " milliseconds."
        for case, label in selected
    ]
    description.text = (
        "Zero-based horizontal bars compare native Rust, first assembly and optimized assembly. "
        + " ".join(details)
        + " Medians of 24 warm-cache runs on one Apple M3 with 128 MiB inputs."
    )
    tree.insert(0, title)
    tree.insert(1, description)
    content = ET.tostring(tree, encoding="utf-8", xml_declaration=True).decode("utf-8")
    return ("\n".join(line.rstrip() for line in content.splitlines()) + "\n").encode("utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="fail if committed chart differs from generated output")
    args = parser.parse_args()
    content = render()
    if args.check:
        if not OUTPUT.is_file() or OUTPUT.read_bytes() != content:
            raise SystemExit("benchmark graphic is stale; rerun tools/render_benchmark_graphic.py")
        print("Benchmark graphic matches the captured evidence and generator.")
    else:
        OUTPUT.parent.mkdir(parents=True, exist_ok=True)
        OUTPUT.write_bytes(content)
        print(f"Wrote {OUTPUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
