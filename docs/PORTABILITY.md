# Portability and native builds

The project implements one pinned [ripwc behavior contract](COMPATIBILITY.md) through three handwritten assembly targets. Platform support describes source builds and native correctness checks; performance evidence remains specific to the [captured M3/macOS run](BENCHMARKS.md).

## Target matrix

| Native target | Scanner / default CPU | Runtime services | Native CI configuration |
|---|---|---|---|
| macOS arm64 (Apple Silicon) | NEON / `apple-m3` | libSystem, libc, libdispatch | `macos-15`, built with `CPU=apple-m1` |
| Linux glibc AArch64 | NEON / `generic` | glibc and pthreads | `ubuntu-24.04-arm` |
| Linux glibc x86-64 | SSE2 / `x86-64` | glibc and pthreads | `ubuntu-24.04` |

SSE2 is part of the x86-64 baseline. The x86-64 port requires no AVX2, AVX, or POPCNT extension. AArch64 uses baseline NEON. `make` detects the host with `uname` and chooses the appropriate sources and compiler flags. `CPU` can select another compiler target on the same native architecture; it is not a cross-compilation switch.

The Linux ports require **glibc**. musl/Alpine is unsupported. Intel macOS, Windows, BSD, 32-bit targets, and cross-compilation are outside the current matrix. `make check` remains available without a supported native application target.

## Build requirements

On Apple Silicon macOS, install Xcode Command Line Tools. The default is tuned for M3; use `make CPU=apple-m1` for an M1 target. The historical performance snapshot was measured on M3/macOS 15.6.1, rather than the hosted CI machine.

On Debian/Ubuntu Linux, install the native compiler, linker, make, glibc headers, and Python for checks:

```sh
sudo apt-get update
sudo apt-get install build-essential python3
```

The supported Python minimum for checks and tests is 3.11. Application builds themselves require neither Python nor Rust. From a native host:

```sh
make
./bin/ripwc --help
```

`CC`, `CPU`, and normal compiler/linker flag overrides are supported for native builds. Linux uses position-independent executables, a non-executable stack, RELRO, and immediate symbol binding. Executables are dynamically linked; a package built on one glibc host is not a promise of compatibility with older libc versions or another architecture.

## Why Linux runs a C probe

[`tools/linux_abi.c`](../tools/linux_abi.c) compiles and executes during a native Linux build. It reads structure sizes, offsets, traversal constants, and errno values from that host's glibc headers and emits `.build/linux/abi.h` for assembly preprocessing. The application is assembled from `main.S`, `cli.S`, and `count.S`; the probe is **not linked into it**.

This isolates host ABI details without adding a C application wrapper. The generated header belongs to the native build host. Supplying a cross compiler or copying that header between targets is not a supported way to build another architecture.

## Verification and baseline builds

Install Rust through rustup to run differential tests. `rust-toolchain.toml` pins Rust/Cargo 1.97.1; the build script installs the pinned toolchain if missing. The first baseline build needs network access for that toolchain and locked Cargo dependencies. Python uses the standard library only.

| Command | macOS arm64 | Linux AArch64 / x86-64 |
|---|---|---|
| `make` | Current assembly executable | Current native assembly executable and build-time ABI probe |
| `make baselines` | Pinned Rust and preserved first Darwin assembly | Pinned native Rust |
| `make test` | Repository checks, kernel/ABI, CLI, I/O, large-file, and dispatch resource tests | Repository checks, native kernel/ABI, CLI, I/O, large-file, and pthread failure tests |
| `make check` | Portable syntax, evidence, and benchmark-tool tests | Same portable checks |
| `make bench` | Three-way comparison | Two-way assembly/Rust comparison |

Each test target compares against Rust built on the same OS, architecture, and libc. OS error messages and metadata sizes can differ between hosts. Linux runs the common large-file carry cases and injects pthread creation failures to verify sequential fallback. Darwin dispatch setup-failure tests apply only to the macOS pipeline.

Filesystem-dependent fixtures are reported as unavailable when they cannot run. For example, the historical APFS snapshot could not create invalid UTF-8 filenames; Linux permission tests require an unprivileged user. Inspect reports rather than assuming identical case counts on every host. Run the complete suite as a normal user for permission coverage.

## Native CI and artifacts

The [CI workflow](https://github.com/stubbi/ripwc-asm/actions/workflows/ci.yml) defines native macOS arm64, Linux x86-64, and Linux AArch64 correctness jobs. Each checks its actual architecture, builds the pinned native Rust reference, runs `make test`, and verifies a staged installation. The workflow page and per-job logs show the status for the revision being reviewed; the matrix above does not itself assert a completed run.

Each native job uploads its reports and test log. Successful Linux jobs also upload `ripwc-linux-x86_64` or `ripwc-linux-aarch64` artifacts containing a tar archive with the executable, README, license, and notice. These are workflow artifacts with the configured retention period, not published release packages. They require the corresponding architecture and a compatible glibc runtime. A source build is the supported route for a different native host.

Hosted CI is a correctness gate, not a performance benchmark. Native execution is required for the platform jobs; emulation is not a substitute for their result.

## Local installation

To install the native executable into a user-owned prefix:

```sh
make install PREFIX="$HOME/.local"
```

The installed name is `ripwc`. `PREFIX` defaults to `/usr/local`; `DESTDIR` supports staged packaging without changing the final prefix. Only the current assembly executable is installed. `make clean` removes generated executables and `.build/`, retaining local `results/` and committed evidence.
