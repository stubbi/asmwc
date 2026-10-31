# Attribution and source provenance

`asmwc` is a handwritten assembly implementation of [LuminousToaster/ripwc](https://github.com/LuminousToaster/ripwc), an experimental Rust word-counting utility. Its native targets are macOS arm64 and Linux glibc AArch64/x86-64. This is an independent project and does not claim endorsement by the upstream author.

The reference version is pinned to commit [`de1a12e8e2d7c031404370773e5099b23ef01e95`](https://github.com/LuminousToaster/ripwc/commit/de1a12e8e2d7c031404370773e5099b23ef01e95), dated 19 May 2025. Its behavior, including differences from GNU `wc`, defines the compatibility target, apart from asmwc's version and fallback program name.

The following upstream files are included unchanged:

- `upstream/src/main.rs`
- `upstream/Cargo.toml`
- `upstream/LICENSE`

`upstream/Cargo.lock` fixes the resolved dependency versions used by the reference build. Dependencies retain their respective licenses; Cargo can enumerate them with `cargo tree --manifest-path upstream/Cargo.toml --locked`.

The root [LICENSE](LICENSE) contains the same GNU General Public License version 3 text as the reference project. The assembly implementation, tests, tooling and documentation in this repository are distributed under GPL-3.0-only. Existing upstream notices are retained. Contributions are accepted under the same license; no contributor license agreement is required.

The first macOS assembly implementation is preserved in `history/original-src/` for reproducible before/after comparisons. These are the original source files; no earlier Git commit history is implied. This baseline does not run on Linux. The preserved sources and committed M3 benchmark evidence retain their original `ripwc` names from before the project was renamed from `ripwc-asm` to `asmwc`.

The Linux AArch64 NEON kernel is ported from the optimized Darwin kernel; the Linux x86-64 scanner uses baseline SSE2. `tools/linux_abi.c` is a native build-time probe of glibc headers, not application code linked into the executable.
