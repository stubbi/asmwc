# Compatibility contract

The reference is [LuminousToaster/ripwc](https://github.com/LuminousToaster/ripwc) at commit [`de1a12e8e2d7c031404370773e5099b23ef01e95`](https://github.com/LuminousToaster/ripwc/tree/de1a12e8e2d7c031404370773e5099b23ef01e95) (19 May 2025). The unchanged Rust source is retained in [`upstream/`](../upstream/). The goal is observable agreement with that revision on the target platform.

The implemented native targets are Apple Silicon macOS and Linux glibc AArch64/x86-64. Each target is compared with pinned Rust built on the same operating system. The [portability matrix](PORTABILITY.md) describes build requirements and native CI. There is no claim of GNU/POSIX `wc` compatibility or Unicode-aware counting. musl/Alpine, Intel macOS, Windows, and BSD are outside the supported matrix.

## Counting rules

| Option | Long option | Actual behavior |
|---|---|---|
| `-c` | `--bytes` | Count input bytes; use saved metadata for byte-only jobs when available. |
| `-m` | `--chars` | Count bytes whose value is not zero. This is not a Unicode character count. |
| `-l` | `--lines` | Count LF bytes (`0x0a`), so an unterminated final line adds no newline. |
| `-w` | `--words` | Count runs separated by space, tab, LF, or CR only. |
| `-L` | `--max-line-length` | Maximum number of bytes between LF characters, including an unterminated final line. |

Without a counting option, `-l`, `-w`, and `-c` are enabled. Counting options combine, including short-option clusters such as `-lwmcL`.

Vertical tab, form feed, nonbreaking space, other Unicode whitespace, and NUL are word content. Every byte of a multibyte UTF-8 encoding counts separately for `-m` and `-L`. CR, tabs, NUL, and multibyte encodings each contribute their byte lengths to a line; tabs are not expanded into display columns.

For byte counting, upstream falls back to saved metadata if a successful scan counted zero bytes. Metadata is collected before opening and scanning, so concurrently changing files can expose that upstream policy. Input is otherwise consumed to EOF; saved size is not a read limit.

## Arguments and diagnostics

- One or more paths are required. No arguments produce the upstream usage error.
- A path named `-` is a literal filename, not standard input. Use `--` to end option parsing for other dash-prefixed paths.
- `-r` / `--recursive` enables traversal. `-v` enables verbose messages; upstream defines no `--verbose` option.
- `-h` / `--help` and `-V` / `--version` reproduce the pinned CLI. The reported version is `ripwc 1.0.0`.
- Duplicate options, unexpected values, unknown options, UTF-8 argument validation, and typo hints follow the pinned clap behavior covered by the differential suite.

The two executables are tested with identical `argv[0]`, environment, working directory, and input streams. This matters because usage text derives its program name from `argv[0]`.

## Paths and traversal

Paths are handled in argument order. Recursive traversal visits each directory's entries sorted by name. A directory symlink supplied as a root is followed; descendant directory symlinks are not traversed. File symlinks can be opened and counted. Repeated paths remain repeated tasks.

Missing paths, traversal errors, failed opens, and failed reads are silently skipped. A read failure discards that file's partial result. A readable directory can produce its metadata size in byte-only mode; modes that attempt to read its contents normally skip it after the read fails. These behaviors are inherited from the reference.

Verbose `Processing: …` messages are attempted before opening an entry only when saved metadata is unavailable or its size is at least 512 KiB. Parallel workers can emit these messages in a different order. Stdout results retain collected task order.

## Output and totals

Selected, nonzero fields appear in this fixed order:

```text
lines: N words: N chars: N bytes: N max line length: N path
```

Zero fields are omitted, including for empty files. If every selected count is zero, the line contains one leading space followed by the path. Names are printed directly, without quoting or escaping embedded whitespace.

When more than one file succeeds, output includes a blank line and a final `total` row. Counts are summed except maximum line length, which is the maximum across files. Failed files do not contribute a row or totals. If all files are skipped, the program normally exits successfully with no count output.

Count-output write failures produce a nonzero exit status and upstream-style I/O diagnostics. The implementation ignores SIGPIPE so it can report a broken output pipe in the same way as Rust. Exact failure text depends on the host libc and Rust reference. Error strings are not expected to be identical between macOS and Linux.

## Evidence and known limits

The immutable **M3/macOS benchmark snapshot** passed 235 general, 86 I/O, and 124 large-file/pipeline end-to-end cases: **445 total**. It also passed **576 CLI differential cases**, **128 parser-state combinations**, independent kernel/guard-page/register tests, pipeline setup-failure checks, and benchmark-contract tests. See the [recorded evidence](../benchmarks/results/apple-m3-2026-10-31/) and [benchmark report](BENCHMARKS.md).

Differential comparisons require exact stdout bytes, stderr bytes, and exit status. Only verbose stderr ordering in explicitly marked parallel cases is normalized, preserving each line and its multiplicity.

Native CI runs the common counting, CLI, I/O, large-file, guard-page, and ABI tests on all three targets. Linux additionally exercises invalid UTF-8 filenames where the filesystem permits them, `/dev/full` when available, permission errors when running as an unprivileged user, and injected pthread creation failures. Case counts depend on host capabilities; inspect the job reports for explicit unavailable fixtures. Darwin dispatch setup-failure tests apply only to the macOS pipeline.

The historical validation filesystem was APFS and rejected invalid UTF-8 filenames, so that filename fixture could not run in the M3 snapshot. Malformed UTF-8 contents and arguments were covered. Directory sizes, error strings, scheduling, and filesystem edge cases vary with the host. Differential agreement means agreement with Rust on that host, not byte-identical OS-dependent values across platforms. Passing finite tests does not prove equivalence for every input, resource exhaustion, or operating-system failure.
