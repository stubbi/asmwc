# Attribution and source provenance

`ripwc-asm` is a handwritten assembly implementation of the observable behavior of [LuminousToaster/ripwc](https://github.com/LuminousToaster/ripwc), an experimental Rust word-counting utility. Its native targets are macOS arm64 and Linux glibc AArch64/x86-64. It is an independent repository, with no claim of endorsement by that project's author.

The reference version is pinned to commit [`de1a12e8e2d7c031404370773e5099b23ef01e95`](https://github.com/LuminousToaster/ripwc/commit/de1a12e8e2d7c031404370773e5099b23ef01e95), dated 19 May 2025. Its behavior, including differences from GNU `wc`, defines this experiment's compatibility target.

The following upstream files are included unchanged:

- `upstream/src/main.rs`
- `upstream/Cargo.toml`
- `upstream/LICENSE`

`upstream/Cargo.lock` was generated for the experiment and fixes the resolved dependency versions. The reference build uses those locked dependencies. Dependencies retain their respective licenses; Cargo can enumerate the dependency tree with `cargo tree --manifest-path upstream/Cargo.toml --locked`.

The root [LICENSE](LICENSE) contains the same GNU General Public License version 3 text as the reference project. The assembly implementation, tests, tooling and documentation in this repository are distributed under GPL-3.0-only. Existing upstream notices are retained. Contributions are accepted under the same license; no contributor license agreement is required.

The first macOS assembly implementation is preserved in `history/original-src/` for reproducible before/after comparisons. Its files represent an actual earlier implementation from this experiment; no earlier Git commit history is implied. It is not a Linux baseline.

The Linux AArch64 NEON kernel is ported from the optimized Darwin kernel; the Linux x86-64 scanner uses baseline SSE2. `tools/linux_abi.c` is a native build-time probe of glibc headers, not application code linked into the executable.

This project was developed with AI coding assistance. Its performance claims are based on recorded executable comparisons, not on how the source was authored. Tests and measurements establish the behavior of the tested cases and machine, not a general claim that assembly is faster than Rust.
