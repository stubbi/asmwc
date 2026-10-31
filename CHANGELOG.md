# Changelog

## Unreleased — Linux ports

- Add native Linux glibc ports for AArch64 with NEON and x86-64 with baseline SSE2; AVX2 and POPCNT are not required.
- Keep all application logic in assembly; obtain Linux libc structure offsets and constants with an isolated build-time C probe.
- Add a bounded pthread pool for independent files while keeping each file's reads sequential to EOF.
- Select native sources and CPU defaults automatically, with a Rust-only comparison baseline on Linux and the existing three-way comparison on macOS.
- Add native Ubuntu 24.04 x86-64 and AArch64 correctness jobs, reports, and executable package artifacts.
- Correct CLI diagnostic filtering and malformed short-option handling against pinned Rust on all three targets.
- Retain the Darwin scanner and pipeline and immutable M3/macOS measurements; no Linux speed result is claimed.

## Initial public snapshot

- Implement the pinned ripwc CLI, traversal, counting, aggregation, and output behavior in native macOS ARM64 assembly.
- Add NEON counting with exact four-byte word separator classification and shared scans for combined maximum-line/counting modes.
- Add adaptive read buffers and a bounded, serial-scanner pipeline for large single-file word-counting jobs, including buffered fallback when setup fails.
- Preserve unchanged upstream Rust and the first assembly implementation as reproducible comparison baselines.
- Add differential CLI and end-to-end tests, independent counting-kernel checks, guard-page and ABI coverage, and pipeline resource-failure tests.
- Include a balanced three-way Apple M3 benchmark snapshot, raw timing samples, build metadata, and verification evidence.
- Document build requirements, compatibility boundaries, implementation design, and contribution expectations.
- Add a captured CLI demo, evidence-driven benchmark chart, and pipeline diagram to the README, with local SVG assets and regeneration tools.

The CLI version remains the pinned upstream `ripwc 1.0.0` for compatibility. This entry does not indicate a published release or tag.
