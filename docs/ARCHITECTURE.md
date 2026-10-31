# Architecture

`ripwc-asm` is a native Mach-O arm64 executable. All application logic is in assembly. It calls macOS libc for allocation, filesystem operations, I/O, and formatting, and libdispatch for scheduling. Those services are supplied by libSystem; no C or Rust application wrapper is linked.

The implementation targets the behavior of upstream ripwc commit `de1a12e8e2d7c031404370773e5099b23ef01e95`. Read the [compatibility contract](COMPATIBILITY.md) for observable semantics and the [benchmark report](BENCHMARKS.md) for performance evidence.

## Source map

| File | Responsibility |
|---|---|
| [`src/cli.S`](../src/cli.S) | Parse arguments; match pinned clap help, diagnostics, duplicate-option handling, and exit behavior. |
| [`src/main.S`](../src/main.S) | Collect paths, save metadata, schedule tasks, read files, finalize counts, aggregate results, and write output. |
| [`src/count.S`](../src/count.S) | Incrementally count a bounded input buffer using NEON and scalar tails. |
| [`src/pipeline.S`](../src/pipeline.S) | Overlap sequential reads with one ordered scanning worker for eligible single-file jobs. |
| [`upstream/`](../upstream/) | Unchanged pinned Rust source, original manifest/license, and comparison lockfile. |
| [`history/original-src/`](../history/original-src/) | Preserved first assembly implementation for before/after comparisons. |
| [`tests/`](../tests/) | Differential and independent tests; C harnesses are not part of the application. |

## Execution flow

1. Parse flags and paths. If no counting flag is selected, enable lines, words, and bytes.
2. Collect tasks in argument order and sorted traversal order, retaining each path and any available metadata size.
3. Process one task directly, or schedule independent tasks with `dispatch_apply_f` when there are multiple entries.
4. For each successful task, finalize any pending word and unterminated line once at EOF.
5. Emit successful results in collected order, then aggregate totals if more than one result succeeded.

Each task owns its count state. Workers do not update shared totals; aggregation happens after processing completes. This preserves ordered stdout while allowing verbose stderr messages to appear in worker order.

Traversal uses Darwin `fts` with physical traversal, no directory changes, and command-line symlink following. The assembly relies on native Darwin arm64 structure layouts, which is one reason this is not a portable Unix assembly implementation.

## Incremental counting contract

`ripwc_count_buffer` receives the input address in `x0`, byte length in `x1`, selected flags in `x2`, and a pointer to zero-initialized 64-byte state in `x3`. It only reads the supplied byte range, preserves callee-saved registers, and carries unfinished words and lines into subsequent calls.

| Flag bit | Value | Field |
|---|---:|---|
| 0 | 1 | Bytes (`-c`) |
| 1 | 2 | Nonzero bytes (`-m`) |
| 2 | 4 | LF characters (`-l`) |
| 3 | 8 | Words (`-w`) |
| 4 | 16 | Maximum line length (`-L`) |

The default count mask is 13. State consists of eight unsigned 64-bit fields:

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

A word is completed when a nonseparator run meets one of space, tab, LF, or CR. A pending final word is added by the caller at EOF. Likewise, the final current line length is folded into the maximum at EOF. The kernel itself does not treat the end of a buffer as the end of a file.

## NEON scanner

The main loops consume 64 bytes through four 16-byte vectors. A NEON table lookup identifies tab, LF, and CR, and an equality mask identifies space. Transitions from a nonseparator byte to a separator count completed words; the previous vector's final separator state carries into the next vector.

LF and NUL masks supply line counts and nonzero-byte counts. Byte-lane accumulators are reduced after at most 128 vectors (2 KiB), before they can overflow. Scalar code handles short inputs and remaining bytes without reading beyond the buffer.

Maximum-line scanning locates LF positions using packed masks. Combined modes reuse loaded vectors and LF masks for the other selected counts. A maximum-line-only path can skip whole vectors containing no LF. Current line length and the best completed length survive every chunk boundary.

## Reading and scheduling

Byte-only mode opens the path and uses saved metadata when available, matching upstream. Other modes read sequentially to EOF. File size chooses an I/O strategy; it does not limit the bytes read or partition a file into fixed ranges. No path uses memory mapping.

Ordinary reads use a heap buffer of 256 KiB for files smaller than 8 MiB and 1 MiB for larger files. Metadata that is absent or zero leads to the smaller buffer; reads still continue to EOF.

The pipeline is selected only when there is exactly one collected task, word counting is enabled, and saved size is at least 8 MiB:

- The caller owns the file descriptor and issues sequential reads.
- Four disjoint 1 MiB buffers hold a bounded batch of input.
- One serial dispatch queue scans buffers in order and owns the shared count state.
- The caller waits for the batch before reusing any buffer, then continues reading.
- At EOF or read failure, outstanding scans finish before resources are released.

Pipeline setup allocates storage and creates dispatch objects before reading any input. If setup fails, it releases acquired resources and returns a fallback status; the caller can safely use the ordinary reader from the original file position. A read failure discards the file's result, as upstream does.

This pipeline overlaps I/O and counting without parallelizing count state within one file. Multiple-file jobs instead use independent per-file tasks. These choices matter when interpreting comparisons with upstream's single-file reader/scanner and Rayon startup cost.

## Verification boundaries

The counting kernel has an independent scalar oracle covering flag masks, byte values, alignments, randomized chunk carry, guard pages, and preserved registers. End-to-end tests compare the executable with pinned upstream Rust, including I/O failures and CLI output. Pipeline tests inject setup failures and exercise large-file boundaries. The benchmark also checks outputs before and after timed invocations.

These layers protect different contracts. Kernel throughput is useful for diagnostics, but the published speed comparisons measure the whole executable. See [contributing](../CONTRIBUTING.md) for expectations when changing either layer.
