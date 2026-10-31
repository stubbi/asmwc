# Architecture

`ripwc-asm` has three native implementations: Mach-O arm64 on macOS, and ELF AArch64/x86-64 on Linux glibc. Parsing, traversal policy, counting, aggregation, and formatting are handwritten assembly. System libraries provide allocation and I/O; scheduling uses libdispatch on macOS and pthreads on Linux. No C or Rust application wrapper is linked.

All targets implement upstream ripwc commit `de1a12e8e2d7c031404370773e5099b23ef01e95`. See the [compatibility contract](COMPATIBILITY.md), [portability matrix](PORTABILITY.md), and [macOS benchmark evidence](BENCHMARKS.md).

## Source map

| Location | Responsibility |
|---|---|
| [`src/*.S`](../src/) | Darwin arm64 parser, orchestration, NEON scanner, and dispatch pipeline. |
| [`src/linux/aarch64/`](../src/linux/aarch64/) | Linux AArch64 `main.S`, `cli.S`, and ported NEON `count.S`. |
| [`src/linux/x86_64/`](../src/linux/x86_64/) | Linux System V AMD64 `main.S`, `cli.S`, and SSE2 `count.S`. |
| [`tools/linux_abi.c`](../tools/linux_abi.c) | Native build-time glibc layout/constant probe; never linked into the application. |
| [`upstream/`](../upstream/) | Unchanged pinned Rust source, original manifest/license, and comparison lockfile. |
| [`history/original-src/`](../history/original-src/) | Preserved first Darwin assembly implementation for before/after comparisons. |
| [`tests/`](../tests/) | Differential tests and independent C/assembly harnesses, separate from the application. |

The Makefile selects native sources and flags from the host OS and architecture. On Linux it compiles and runs the ABI probe, producing `.build/linux/abi.h` from target libc headers. That header supplies `stat`/`FTSENT` sizes and offsets, traversal constants, errno values, and the online-CPU query constant. This avoids copying Darwin layouts or guessing glibc offsets. The build is native, not a cross-compilation interface.

## Shared execution flow

1. Parse flags and paths. If no counting flag is selected, enable lines, words, and bytes.
2. Collect tasks in argument order and sorted traversal order, retaining each path and any available metadata size.
3. Process one task directly, or schedule independent tasks through the target's multiple-file scheduler.
4. For each successful task, finalize any pending word and unterminated line once at EOF.
5. Emit successful results in collected order, then aggregate totals if more than one result succeeded.

Each task owns its count state. Workers do not update shared totals; aggregation happens after processing completes. This preserves ordered stdout while allowing verbose stderr messages to appear in worker order.

Both platforms use `fts` with physical traversal, no directory changes, and command-line symlink following. Linux reconstructs displayed descendant paths relative to the original root spelling because glibc `fts` can trim trailing root separators. The compatibility target is upstream WalkDir behavior on the same host.

## Incremental counting contract

`ripwc_count_buffer` takes an input address, byte length, count flags, and a pointer to zero-initialized 64-byte state. AArch64 passes these in `x0`–`x3`; System V AMD64 uses `rdi`, `rsi`, `rdx`, and `rcx`. The kernel reads only the supplied range, preserves the target ABI's callee-saved registers, and carries unfinished words and lines across calls.

| Flag bit | Value | Field |
|---|---:|---|
| 0 | 1 | Bytes (`-c`) |
| 1 | 2 | Nonzero bytes (`-m`) |
| 2 | 4 | LF characters (`-l`) |
| 3 | 8 | Words (`-w`) |
| 4 | 16 | Maximum line length (`-L`) |

The default count mask is 13. All implementations share eight unsigned 64-bit state fields:

| Offset | Meaning |
|---:|---|
| 0 | Bytes |
| 8 | Nonzero bytes |
| 16 | Completed words |
| 24 | LF count |
| 32 | Maximum completed line length |
| 40 | Pending word flag |
| 48 | Current line length |
| 56 | Reserved |

A word completes when a nonseparator run meets space, tab, LF, or CR. The caller adds a pending final word at EOF and folds the final current line length into the maximum. A buffer boundary is never treated as EOF.

## NEON scanner: macOS arm64 and Linux AArch64

The Linux AArch64 kernel ports the optimized Darwin NEON kernel to the Linux ABI and assembler conventions. Its main loops consume 64 bytes through four 16-byte vectors. A table lookup identifies tab, LF, and CR; an equality mask identifies space. Nonseparator-to-separator transitions count completed words, carrying the previous vector's final separator state forward.

LF and NUL masks supply line and nonzero-byte counts. Byte-lane accumulators are reduced after at most 128 vectors (2 KiB), before they can overflow. Scalar code handles short inputs and remaining bytes without reading beyond the buffer.

Maximum-line scanning locates LF positions with packed masks. Combined modes reuse loaded vectors and LF masks for other selected counts. A maximum-line-only path skips whole vectors without LF. Current line length and the best completed length survive chunk boundaries.

## SSE2 scanner: Linux x86-64

The x86-64 kernel uses mandatory baseline SSE2, without AVX, AVX2, or POPCNT. It loads bounded 16-byte vectors, compares bytes for LF/NUL and the four word separators, then extracts masks with `pmovmskb`. A scalar bit-count sequence counts mask bits without a CPU extension. Separator transitions carry the prior word state between vectors.

Maximum-line handling walks the LF mask with scalar bit operations, updates the longest completed line, and retains the remaining line length. A scalar tail handles fewer than 16 bytes. This is a separate implementation of the same state contract, not an x86 translation of the NEON instruction sequence.

## File reads

Byte-only mode opens the path and uses saved metadata when available, matching upstream. Other modes read sequentially to EOF. Saved size chooses buffer size; it does not limit the bytes read or partition a file into fixed ranges. No implementation uses memory mapping.

Ordinary reads use a heap buffer of 256 KiB below 8 MiB and 1 MiB for larger saved sizes. Absent metadata uses the smaller buffer. Linux retries interrupted opens and reads. Other read failures discard the file's partial result.

### macOS scheduling and pipeline

Multiple tasks use `dispatch_apply_f`; a single task bypasses that scheduler. The macOS pipeline is selected only for exactly one collected task with word counting enabled and saved size of at least 8 MiB:

- The caller owns the file descriptor and performs sequential reads.
- Four disjoint 1 MiB buffers hold a bounded batch.
- One serial dispatch queue scans in order and owns shared count state.
- The caller waits for the batch before reusing buffers.
- EOF or read failure drains outstanding scans before releasing resources.

Pipeline storage and dispatch objects are acquired before any read. Setup failure releases acquired resources and returns a fallback status, so ordinary buffered reading can start at the original file position. A read failure discards the result.

### Linux scheduling

Linux has no reader/scanner pipeline. A task's worker reads and scans each buffer sequentially. For multiple tasks, a bounded pthread pool uses at most `min(online CPUs, task count, 32)` workers including the calling thread, with at least one worker when work exists. Workers atomically reserve distinct tasks and write only their task's state.

The calling thread participates rather than waiting idle. Failed thread creation leaves work available to the other workers; only successfully created threads are joined. Results are emitted after processing and joins, preserving collected order.

These I/O and scheduling differences matter for performance. The recorded M3/macOS speedups do not characterize either Linux port.

## Verification boundaries

Each native counting kernel has an independent scalar oracle covering flag masks, byte values, alignments, randomized chunk carry, guard pages, and preserved registers. End-to-end tests compare with pinned upstream Rust built on the same host, including CLI and I/O failures. Large-file boundary tests run on every target. Dispatch setup-failure injection is macOS-only.

Native CI runs the platform suites; portable checks verify repository syntax, tooling, and immutable benchmark evidence. The benchmark separately checks outputs before and after timed invocations. Kernel throughput is diagnostic; published speed comparisons measure the whole executable. See [contributing](../CONTRIBUTING.md) for changes to these contracts.
