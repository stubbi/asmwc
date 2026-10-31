# Contributing

This project explores an ARM64 assembly implementation of a specific ripwc behavior contract. Changes should preserve that contract unless they explicitly propose a new one. Start with the [compatibility notes](docs/COMPATIBILITY.md) and [architecture](docs/ARCHITECTURE.md).

## Development setup

Use Apple Silicon macOS with Xcode Command Line Tools, Python 3.11+, and the Rust 1.97.1 toolchain selected by `rust-toolchain.toml`.

```sh
make
make baselines
make test
make check
```

`make test` builds missing comparison executables automatically and runs the full native suite. `make check` runs portable repository, evidence, and benchmark-contract checks. Rust dependencies are locked; the first build may fetch them. No third-party Python packages are required. Use a suitable `CPU` target on earlier Apple Silicon, for example `make CPU=apple-m1 test`.

The application lives in `src/`. The C and assembly files in `tests/` are isolated test harnesses. Keep `upstream/` and `history/original-src/` unchanged when developing an optimization so the comparison baselines remain useful. Generated binaries, corpora, and local reports do not belong in a pull request.

## Correctness changes

For a bug report, include the host chip and macOS version, build command, exact arguments, a minimal input or a way to generate it, and stdout, stderr, and exit status. State whether pinned upstream Rust behaves differently. Use synthetic data if the original input contains private information.

For a fix or optimization:

1. Add a focused regression case that exercises the behavior being changed.
2. Preserve the Darwin arm64 calling convention, stack alignment, and register rules. The counting kernel must never load beyond its input range.
3. Preserve word and line carry across arbitrary read boundaries, handle partial reads, and continue reading to EOF.
4. Run `make test` and `make check` before submitting. Include the commands and results in the pull request.

Do not normalize output differences merely to make a comparison pass. The only existing normalization sorts verbose stderr lines in cases explicitly marked as parallel. A skipped filesystem fixture is a limitation to report, not a passing test.

## Performance changes

Explain which workload a change targets and why it should help. Run correctness checks before measuring, then stop builds, tests, and other benchmarks during the timed run.

```sh
make bench
```

Use the [benchmark method](docs/BENCHMARKS.md): all implementations in the same run, identical inputs and output checks, balanced order, warmups, raw observations, and uncertainty estimates. Include regressions and unchanged workloads alongside improvements. Keep diagnostic kernel throughput separate from end-to-end measurements.

Report the machine, OS, toolchains, build flags, corpus size, repetitions, and whether the filesystem cache was warm. A change measured on one host does not establish a general language or hardware ranking. Do not replace the committed reference snapshot with unrelated results; add a clearly identified dataset when a new snapshot is warranted.

## Pull requests

Keep changes focused and describe the resulting behavior first. For assembly changes, explain state ownership, boundary handling, and any scheduling tradeoff that is difficult to see from the instructions alone. Link relevant test or benchmark evidence. Documentation corrections are welcome without running hardware tests when they do not change code or executable examples.

Contributions are distributed under the repository's [GPL-3.0 license](LICENSE). Preserve upstream attribution and license files.
