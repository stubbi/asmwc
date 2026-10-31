# asmwc

[![CI](https://github.com/stubbi/asmwc/actions/workflows/ci.yml/badge.svg)](https://github.com/stubbi/asmwc/actions/workflows/ci.yml)

Handwritten assembly implementation of [ripwc](https://github.com/LuminousToaster/ripwc) for macOS and Linux.

Supports **Apple Silicon macOS**, **Linux AArch64**, and **Linux x86-64**. ARM targets use NEON; x86-64 uses baseline SSE2, with no AVX2 requirement. It follows upstream commit [`de1a12e`](https://github.com/LuminousToaster/ripwc/tree/de1a12e8e2d7c031404370773e5099b23ef01e95), including its differences from GNU/POSIX `wc`, with `asmwc` as its version and fallback program name.

Parsing, traversal policy, counting, aggregation, and formatting are handwritten assembly. System libraries provide allocation, I/O, and scheduling. No C or Rust application wrapper is linked. C is used for test harnesses and a Linux build-time ABI probe that is not linked into the executable.

![Actual terminal demonstration: a 15-byte example file produces one line, two words, 15 characters and bytes, and a maximum line length of 14.](docs/assets/terminal-demo.svg)

## Build and run

`make` detects the native OS and architecture. Building the assembly program does not require Rust or Python.

| Native target | Build requirements | Default CPU target |
|---|---|---|
| macOS arm64 | Xcode Command Line Tools | `apple-m3` |
| Linux AArch64, glibc | C compiler, linker, make, and glibc development headers | `generic` (NEON) |
| Linux x86-64, glibc | C compiler, linker, make, and glibc development headers | `x86-64` (SSE2) |

On Debian/Ubuntu, `sudo apt-get install build-essential python3` supplies the build tools and Python for checks. On earlier Apple Silicon, select a suitable target, for example `make CPU=apple-m1`. Builds are native; musl/Alpine, Intel macOS, Windows, and BSD are outside the supported matrix. See [portability and native CI](docs/PORTABILITY.md) for details.

```sh
git clone https://github.com/stubbi/asmwc.git
cd asmwc
make
./bin/asmwc --help
```

```sh
./bin/asmwc file.txt            # lines, words, and bytes
./bin/asmwc -lwmcL file.txt     # all five count fields
./bin/asmwc -r directory       # recursive traversal
./bin/asmwc -- -dash-file      # a filename beginning with '-'
```

For example, a file containing `hello assembly` followed by LF produces:

```text
lines: 1 words: 2 bytes: 15 example.txt
```

Paths are required; `-` means a literal filename. There is no standard-input mode. Word separators are exactly space, tab, LF, and CR. `-m` counts nonzero bytes, and `-L` counts bytes between LF characters. Zero fields are omitted. Read the [compatibility contract](docs/COMPATIBILITY.md) before substituting this for another counting tool.

## Measured performance — macOS only

On one **8-core Apple M3, 16 GiB, macOS 15.6.1**, the optimized assembly was **4.49–4.65× faster** than the pinned, natively optimized Rust implementation for default counting, and **9.14–9.22× faster** for all five fields. Each large input was 128 MiB; these are warm-cache, whole-program medians from 24 samples per implementation, recorded on 31 October 2026.

![Zero-based benchmark chart comparing native Rust, the first assembly implementation, and optimized assembly on four 128 MiB workloads. The exact median times are also listed below.](docs/assets/benchmark.svg)

| Workload | Native Rust | Assembly | Rust / assembly |
|---|---:|---:|---:|
| Text, default | 68.468 ms | 15.234 ms | 4.49× |
| Binary, default | 60.061 ms | 12.906 ms | 4.65× |
| Text, all five fields | 122.720 ms | 13.307 ms | 9.22× |
| Binary, all five fields | 123.094 ms | 13.470 ms | 9.14× |

The [benchmark report](docs/BENCHMARKS.md) includes the preserved first assembly implementation, all workloads, confidence intervals, limitations, and reproduction instructions. The [recorded evidence](benchmarks/results/apple-m3-2026-10-31/) predates the asmwc rename and retains its original names, raw samples, corpus identities, build details, and verification reports.

These results describe the macOS implementation on this machine. **No Linux performance measurements are published.** The macOS path overlaps reading and scanning for large single-file word-counting jobs; the Linux ports use sequential buffered reading. Small-file measurements also include runtime startup differences. The M3 figures do not predict Linux, other CPUs, or cold-storage performance.

## Verify and benchmark

Verification requires **Python 3.11+** and **Rust installed through rustup**. `rust-toolchain.toml` pins Rust/Cargo **1.97.1**; the baseline build installs that toolchain through rustup if needed. Python scripts use only the standard library. Building or running the assembly program does not require Rust. The first baseline build needs network access for the pinned toolchain and locked Cargo dependencies.

```sh
make baselines   # native Rust; also preserved first assembly on macOS
make test        # build missing baselines and run the full native test suite
make check       # portable checks; no compiler or Rust required
make bench       # 128 MiB, 24 samples: two-way Linux / three-way macOS
```

The recorded **macOS benchmark snapshot** passed **445 end-to-end cases**, **576 CLI differential cases**, and **128 parser-state combinations**, plus kernel, guard-page, register-preservation, pipeline setup-failure, and benchmark-contract tests. Native CI runs on macOS arm64 and Ubuntu 24.04 on both Linux architectures; its reports cover each target's current tests. Linux also verifies fallback when pthread creation fails; dispatch setup-failure tests apply to macOS.

Differential tests compare stdout, stderr, and exit status against upstream Rust built on the same host, allowing the documented [program-name differences](docs/COMPATIBILITY.md#arguments-and-diagnostics) and explicitly parallel verbose message ordering. Passing tests establishes equivalence for the covered cases, not every input or OS failure.

Generated executables, local reports, and benchmark corpora are excluded from version control. The committed benchmark snapshot is separate from newly generated `results/` files. Rebuilt executable hashes can differ from the recorded ones; the benchmark report explains the snapshot's provenance.

## How it works

![macOS only: for one eligible word-counting task of at least 8 MiB, sequential reads feed four reusable 1 MiB buffers. One serial NEON scanner preserves word and line carry; the batch finishes before buffers are reused, and counts are finalized at EOF.](docs/assets/pipeline.svg)

This reader/scanner pipeline is **macOS-only**. Linux uses sequential buffered reads per file and a bounded pthread pool for multiple files. The [architecture guide](docs/ARCHITECTURE.md) explains both paths and the NEON/SSE2 scanners.

## Project guide

- [Architecture](docs/ARCHITECTURE.md): source map, scanner state, scheduling, and I/O design.
- [Compatibility](docs/COMPATIBILITY.md): counting rules, CLI behavior, traversal, and known limits.
- [Portability](docs/PORTABILITY.md): native targets, dependencies, CI, and build artifacts.
- [Benchmarks](docs/BENCHMARKS.md): methodology, full results, and reproduction.
- [Contributing](CONTRIBUTING.md): correctness and measurement expectations.
- [Changelog](CHANGELOG.md): changes in this repository.
- [README graphics](docs/assets/README.md): captured output, chart data, and regeneration.

## Attribution and license

Based on [LuminousToaster/ripwc](https://github.com/LuminousToaster/ripwc) at commit `de1a12e8e2d7c031404370773e5099b23ef01e95` (19 May 2025). Its unchanged Rust source, manifest, and license are retained in [`upstream/`](upstream/); the comparison dependency graph is fixed by `upstream/Cargo.lock`. [`history/original-src/`](history/original-src/) preserves the first assembly implementation used as the optimization baseline.

Licensed under [GPL-3.0](LICENSE). The upstream license is also preserved at [`upstream/LICENSE`](upstream/LICENSE).
