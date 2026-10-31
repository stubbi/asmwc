# Benchmark methods and evidence

The captured experiment was run on **31 October 2026** on an Apple M3 with 8 cores (4 performance, 4 efficiency), 16 GiB memory and macOS 15.6.1. It compares three executable implementations of the same pinned ripwc contract:

1. Unmodified Rust reference at `de1a12e8e2d7c031404370773e5099b23ef01e95`.
2. The first assembly implementation, preserved in `history/original-src/`.
3. The optimized macOS assembly implementation in `src/*.S`.

This snapshot predates the rename from `ripwc-asm` to `asmwc`. Its recorded executable paths (`bin/ripwc`, `bin/ripwc-rust`, and `bin/ripwc-before`), symbol names, hashes, and reports are preserved. Current builds use `bin/asmwc`, `bin/asmwc-rust`, and `bin/asmwc-before`; the rename does not constitute a new benchmark run.

The measurements describe this generated corpus, these builds and this machine. **They are macOS-only; no Linux performance measurements are published.** The Linux ports use different scheduling and I/O paths, and x86-64 uses a different scanner. These figures do not establish Linux speed, a performance ranking between programming languages, or a general replacement for GNU `wc`.

## Reproduce the comparison

On Apple Silicon macOS with the [documented requirements](../README.md#build-and-run):

```sh
make baselines
make test
make check
python3 bench.py --before bin/asmwc-before --extended --size-mib 128 --runs 24 \
  --corpus .build/benchmark-corpus --output-dir results/your-run
```

On macOS, `make bench` runs the same three-way, 24-sample comparison with the default 128 MiB corpus. Close other intensive programs before measuring. Do not run builds, tests or several benchmarks concurrently. Report all samples and the exact environment when sharing a result; the fastest observation alone is not a useful comparison.

The corpus and generated reports stay in ignored directories. New measurements must not overwrite the committed reference evidence. [Contribution guidance](../CONTRIBUTING.md) explains how to propose a new result.

## Run a new native Linux comparison

On a [supported Linux glibc target](PORTABILITY.md), install the native build tools, Python 3.11+, and Rust through rustup, then run:

```sh
make test
make bench
```

Linux `make bench` compares **two executables**: native assembly and the pinned native Rust build, with a 128 MiB corpus and 24 samples per executable. The preserved first assembly implementation is macOS-only and is not supplied as `--before` on Linux. For an explicitly named local report directory:

```sh
python3 bench.py --extended --size-mib 128 --runs 24 \
  --corpus .build/benchmark-corpus --output-dir results/linux-your-run
```

The two execution orders are balanced on Linux, rather than the six used in the captured three-way run. Before/after assembly bootstrap intervals require an actual `--before` executable and are absent from a two-way run. Keep a new Linux dataset separate from the immutable M3 snapshot; do not reuse its speedups, executable hashes, or performance chart as Linux evidence.

Native CI tests correctness and packages executables. CI durations, emulation timings, and artifact builds are not published performance measurements.

## Captured macOS builds

The reference Rust source is unchanged. Cargo dependencies are fixed by `upstream/Cargo.lock`. The captured build used Rust 1.97.1 / LLVM 22.1.6, `-C target-cpu=native`, optimization level 3, fat LTO, one codegen unit, aborting panics and incremental compilation disabled.

The captured macOS assembly was built with Apple clang 17.0.0, `-arch arm64 -mcpu=apple-m3 -O3 -g`. All application logic is assembly; libc and libdispatch supply OS and scheduling services. The C sources under `tests/` are test harnesses and are not linked into the application.

CI uses an explicit Apple M1 CPU setting to check the baseline ARM64/NEON code on a hosted Apple Silicon runner. CI verifies correctness, not performance. Neither its results nor its machine are presented as an M3 benchmark.

## Workloads and timing

The deterministic corpus contains:

- A 128 MiB text file built from a repeated line with ASCII words, whitespace and valid UTF-8.
- A 128 MiB binary file built from a seeded, generated 1 MiB block.
- A directory of 64 alternating text/binary files totaling 128 MiB.
- A 4 KiB text file for startup-sensitive workloads.

This deliberately bounded corpus is not a broad real-world language or storage benchmark. Every generated file's length and SHA-256 hash is recorded in the report. Different text distributions, long lines, disk state or machines can change the outcome.

The timed region covers subprocess startup, path traversal, reads, counting, output capture and shutdown. Each workload first passes a three-way stdout/stderr/exit comparison. Every measured invocation's output is hashed and checked again after timing.

The filesystem cache is warm after preflight and two warmup rounds. There is no cache flushing or cold-storage claim. For 24 measured rounds, the six possible executable orders each occur four times, shuffled with a fixed seed. Both raw order and duration are recorded. All executables inherit the same available cores, without CPU affinity pinning.

The Rust reference initializes a Rayon thread pool on every invocation, including single-file and metadata-only jobs. The first assembly version creates parallel file work only when needed. For large single-file word-counting jobs, the optimized version overlaps one reader with one serial scanning worker. These architectural and startup differences are part of the executable comparison; the improvement cannot be attributed solely to instruction selection.

Metadata-only `-c` cases do not scan file contents and must not be reported as scanning throughput.

## Results and uncertainty

The [summary CSV](../benchmarks/results/apple-m3-2026-10-31/benchmark.csv) contains medians, means, ranges, standard deviations, scanning throughput where appropriate, before/after ratios and time reductions. The [JSON report](../benchmarks/results/apple-m3-2026-10-31/benchmark.json) also contains every observation, corpus metadata, build settings and output hashes. The [raw sample CSV](../benchmarks/results/apple-m3-2026-10-31/benchmark-samples.csv) preserves execution order.

Speedup means the ratio of median times, not the ratio of the fastest runs. A 1.25× speedup corresponds to 20% less time. Paired 95% percentile bootstrap intervals resample matched rounds, with 5,000 seeded resamples, and recompute the ratio of medians. They describe uncertainty within this run; they are not guarantees under other system load, and no multiple-comparison adjustment is applied.

Default counting used 15–22% less time than the first assembly version; word counting used 19–22% less; the 64-file default workload used 21% less. All five fields together used 40–42% less time. Those workloads' intervals exclude parity. Most other modes had no clear change. The binary `-m` median was 6.7% slower, with a 0.900–1.006× interval that includes parity. These unchanged or uncertain results are retained in the full data.

| Workload | Rust | Previous assembly | Optimized assembly | Previous / optimized (95% interval) | Rust / optimized |
|---|---:|---:|---:|---:|---:|
| `text/default` | 68.468 ms | 17.903 ms | 15.234 ms | 1.175× (1.093–1.255) | 4.494× |
| `text/lines` | 22.649 ms | 13.374 ms | 13.463 ms | 0.993× (0.959–1.035) | 1.682× |
| `text/words` | 73.425 ms | 16.624 ms | 13.435 ms | 1.237× (1.189–1.290) | 5.465× |
| `text/chars` | 24.013 ms | 12.647 ms | 12.651 ms | 1.000× (0.984–1.035) | 1.898× |
| `text/max-line` | 106.981 ms | 15.464 ms | 15.618 ms | 0.990× (0.926–1.043) | 6.850× |
| `text/byte-metadata` | 2.126 ms | 1.761 ms | 1.738 ms | 1.013× (0.978–1.035) | 1.223× |
| `text/all-counts` | 122.720 ms | 22.353 ms | 13.307 ms | 1.680× (1.621–1.723) | 9.222× |
| `binary/default` | 60.061 ms | 16.535 ms | 12.906 ms | 1.281× (1.263–1.301) | 4.654× |
| `binary/lines` | 21.731 ms | 12.705 ms | 12.647 ms | 1.005× (0.993–1.015) | 1.718× |
| `binary/words` | 68.288 ms | 16.274 ms | 12.735 ms | 1.278× (1.242–1.307) | 5.362× |
| `binary/chars` | 26.155 ms | 13.307 ms | 14.198 ms | 0.937× (0.900–1.006) | 1.842× |
| `binary/max-line` | 108.638 ms | 16.039 ms | 16.059 ms | 0.999× (0.982–1.020) | 6.765× |
| `binary/byte-metadata` | 1.945 ms | 1.549 ms | 1.553 ms | 0.998× (0.948–1.014) | 1.253× |
| `binary/all-counts` | 123.094 ms | 23.267 ms | 13.470 ms | 1.727× (1.697–1.743) | 9.139× |
| `many/default` | 18.268 ms | 8.623 ms | 6.833 ms | 1.262× (1.214–1.352) | 2.674× |
| `many/chars` | 11.445 ms | 8.009 ms | 6.687 ms | 1.198× (1.082–1.303) | 1.712× |
| `startup/default` | 2.639 ms | 2.209 ms | 2.107 ms | 1.048× (0.911–1.133) | 1.252× |
| `startup/byte-metadata` | 2.414 ms | 1.890 ms | 1.892 ms | 0.999× (0.947–1.108) | 1.276× |

The earlier [original-run evidence](../benchmarks/results/apple-m3-2026-10-31/original-run/benchmark.json) is a separate 20-sample, two-way experiment. It provides history; its old timings are not used as the baseline for the new three-way ratios.

## Correctness evidence

The captured M3/macOS validation covers 445 end-to-end cases: 235 general differential cases, 86 I/O-boundary cases and 124 large-file/pipeline cases. It also covers 576 CLI differential cases, 128 parser-state combinations, all kernel flag masks and byte values, randomized carry, guard pages, preserved registers and setup-failure fallback.

In the captured run, stdout, stderr and exit status were compared exactly. Only explicitly parallel verbose stderr ordering was normalized, because upstream scheduling makes it nondeterministic. APFS rejected invalid UTF-8 filenames, so that filename fixture is explicitly recorded as unavailable; malformed contents and arguments were still tested. The current suite also allows the documented [program-name differences](COMPATIBILITY.md#arguments-and-diagnostics). These checks cover the tested cases, not every input or OS failure.

## Publication and integrity

The committed [publication manifest](../benchmarks/results/apple-m3-2026-10-31/PUBLICATION.json) gives a checksum for each published report. Local filesystem paths and the machine hostname have been redacted. All numerical values, sample order, statistics, compiler settings, corpus checksums and measured executable hashes are preserved. The exporter checks that redaction does not change the numerical evidence.

`tools/check_evidence.py` verifies the publication checksums, recomputes medians and ratios from the samples, checks balanced order and output hashes, and connects the tested binary hashes to the measured binary hashes. It runs in `make check` and CI.

Executable hashes identify the captured builds. A rebuild may differ because of compiler versions, debug paths, Mach-O identifiers or signing; byte-for-byte reproducible builds are not claimed. The measured source hashes are retained in `build-info.json`. The [export tool](../tools/export_evidence.py) can publish a new captured report directory to a new destination and refuses to overwrite an existing publication.
