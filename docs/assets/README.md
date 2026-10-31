# README graphics

All three graphics are stored locally as SVGs, with accessible titles and descriptions. They contain no scripts, external fonts or image dependencies. The README keeps copyable command examples and a text results table alongside the graphics.

- `terminal-demo.svg` renders actual stdout captured from the assembly executable. The input, commands, output and exit codes are preserved in `demo-session.json`; no timing result is invented for the demonstration.
- `benchmark.svg` is a Matplotlib plot of the committed [measurement evidence](../../benchmarks/results/apple-m3-2026-10-31/benchmark.json). Every bar starts at zero and represents a recorded median. The original assembly baseline and the machine/corpus conditions are shown along with the optimized Rust comparison.
- `pipeline.svg` illustrates the macOS bounded reading/scanning pipeline. This path is selected for one task with word counting enabled and saved size of at least 8 MiB. Linux uses sequential buffered reads per file.

## Regenerate the demo and diagram

Requires Apple Silicon macOS, the built assembly executable, and the standard library only:

```sh
make
python3 tools/render_demo_graphics.py
python3 tools/render_demo_graphics.py --check
```

The `--check` command recaptures the tiny CLI example and compares all three generated files without modifying them. No benchmark is run.

## Regenerate the chart

The pinned graphics-authoring dependencies require **Python 3.12+** and are isolated from the application and ordinary test suite. Use that version or newer as `python3` below; the project's normal verification requirement remains Python 3.11+.

```sh
python3 -m venv .build/graphics-venv
.build/graphics-venv/bin/python -m pip install -r requirements-graphics.txt
.build/graphics-venv/bin/python tools/render_benchmark_graphic.py
.build/graphics-venv/bin/python tools/render_benchmark_graphic.py --check
```

The chart uses a fixed SVG identifier salt, bundled font paths and no creation timestamp. Inspect rendered output after changing a generator, including labels, clipping and readability at README width. Keep the [benchmark methodology](../BENCHMARKS.md) and [compatibility contract](../COMPATIBILITY.md) intact when updating a visual.
