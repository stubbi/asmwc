# Contributing

asmwc implements a pinned ripwc behavior contract in handwritten assembly. Changes should preserve that contract unless they explicitly propose a new one. Start with the [compatibility notes](docs/COMPATIBILITY.md) and [architecture](docs/ARCHITECTURE.md).

## Development setup

Use a [supported native target](docs/PORTABILITY.md): Apple Silicon macOS with Xcode Command Line Tools, or Linux glibc on AArch64/x86-64 with a compiler, linker, make, and glibc headers. Tests also require Python 3.11+ and Rust installed through rustup. The baseline build selects Rust 1.97.1 from `rust-toolchain.toml` and installs it if needed.

```sh
make
make baselines
make test
make check
```

`make test` builds missing baselines and runs repository checks plus the native suite. Linux compares with pinned native Rust; macOS also builds the preserved first assembly implementation. Resource tests inject pthread creation failures on Linux and dispatch setup failures on macOS. `make check` needs only make, POSIX sh, and Python's standard library. The first baseline build may fetch the pinned toolchain and locked dependencies. Use a suitable `CPU` target on earlier Apple Silicon, for example `make CPU=apple-m1 test`.

Darwin sources live in `src/*.S`; Linux sources live in `src/linux/{aarch64,x86_64}/`. C and assembly in `tests/` are isolated harnesses. `tools/linux_abi.c` is a build-time glibc layout probe and is not linked into the application. Its native execution makes cross-compilation unsupported.

Keep `upstream/`, `history/original-src/`, and the committed M3 evidence unchanged when developing a port or optimization. Generated binaries, corpora, and local reports do not belong in a pull request.

## Correctness changes

For a bug report, include the OS/distribution, libc where applicable, CPU architecture, compiler, build command, exact arguments, a minimal input or a way to generate it, and stdout, stderr, and exit status. State whether pinned upstream Rust behaves differently. Use synthetic data if the original input contains private information.

For a fix or optimization:

1. Add a focused regression case that exercises the behavior being changed.
2. Preserve the target calling convention (Darwin arm64, AAPCS64, or System V AMD64), stack alignment, and register rules. The counting kernel must never load beyond its input range.
3. Preserve word and line carry across arbitrary read boundaries, handle partial reads, and continue reading to EOF.
4. Run `make test` before submitting and include the command and result. Run `make check` separately when native tests are unavailable.
5. Check all affected native CI jobs before merging. Shared behavior changes need coverage on all three targets; do not treat emulation or portable checks as native validation.

Do not normalize output differences merely to make a comparison pass. Tests allow the exact `asmwc 1.0.0` version banner in place of upstream's `ripwc 1.0.0`, and a fallback usage name of `asmwc` when `argv[0]` has no usable basename. They sort verbose stderr lines only in cases explicitly marked as parallel. A skipped filesystem fixture is a limitation to report, not a passing test.

## Performance changes

Explain which workload a change targets and why it should help. Run correctness checks before measuring, then stop builds, tests, and other benchmarks during the timed run.

```sh
make bench
```

Use the [benchmark method](docs/BENCHMARKS.md): native assembly and Rust in the same run, plus the preserved assembly baseline on macOS, with identical inputs and output checks, balanced order, warmups, raw observations, and uncertainty estimates where available. `make bench` is two-way on Linux and three-way on macOS; the original assembly baseline is Darwin-only. Include regressions and unchanged workloads alongside improvements. Keep diagnostic kernel throughput separate from end-to-end measurements.

Report the machine, OS, toolchains, build flags, corpus size, repetitions, and whether the filesystem cache was warm. A change measured on one host does not establish a general language or hardware ranking. The published M3/macOS measurements are not Linux results. Hosted CI timing is not a performance gate. Do not replace the committed reference snapshot with unrelated results; add a clearly identified dataset when a new snapshot is warranted.

## Pull requests

Keep changes focused and describe the resulting behavior first. For assembly changes, explain state ownership, boundary handling, and any scheduling tradeoff that is difficult to see from the instructions alone. Link relevant test or benchmark evidence. Documentation corrections are welcome without running hardware tests when they do not change code or executable examples.

Contributions are distributed under the repository's [GPL-3.0 license](LICENSE). Preserve upstream attribution and license files.
