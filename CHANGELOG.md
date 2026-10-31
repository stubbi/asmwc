# Changelog

## Unreleased — initial public snapshot

- Implement the pinned ripwc CLI, traversal, counting, aggregation, and output behavior in native macOS ARM64 assembly.
- Add NEON counting with exact four-byte word separator classification and shared scans for combined maximum-line/counting modes.
- Add adaptive read buffers and a bounded, serial-scanner pipeline for large single-file word-counting jobs, including buffered fallback when setup fails.
- Preserve unchanged upstream Rust and the first assembly implementation as reproducible comparison baselines.
- Add differential CLI and end-to-end tests, independent counting-kernel checks, guard-page and ABI coverage, and pipeline resource-failure tests.
- Include a balanced three-way Apple M3 benchmark snapshot, raw timing samples, build metadata, and verification evidence.
- Document build requirements, compatibility boundaries, implementation design, and contribution expectations.

The CLI version remains the pinned upstream `ripwc 1.0.0` for compatibility. This entry does not indicate a published release or tag.
