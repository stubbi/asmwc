// Linux/glibc AArch64 application logic. libc and pthread provide OS services;
// parsing, traversal policy, counting, aggregation and formatting are assembly.
#include "abi.h"
.text
.p2align 2
.globl main
.type main, %function
main:
    stp x29, x30, [sp, #-96]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    stp x23, x24, [sp, #48]
    // Rust ignores SIGPIPE and propagates write errors through io::Result.
    mov x19, x0
    mov x20, x1
    mov w0, #13
    mov x1, #1
    bl signal
    mov x0, x19
    mov x1, x20
    bl asmwc_parse
    adrp x9, :got:stdout
    ldr x9, [x9, :got_lo12:stdout]
    ldr x0, [x9]
    mov x1, #0
    mov w2, #1 // IOLBF: one flush per newline, like Rust's stdout LineWriter
    mov x3, #0
    bl setvbuf
    adrp x19, asmwc_paths
    ldr x19, [x19, :lo12:asmwc_paths]
    adrp x20, asmwc_nargs
    ldr x20, [x20, :lo12:asmwc_nargs]
    mov x21, #0
L_collect_args:
    cmp x21, x20
    b.hs L_collected
    ldr x0, [x19, x21, lsl #3]
    bl collect_path
    add x21, x21, #1
    b L_collect_args
L_collected:
    adrp x19, tasks
    ldr x19, [x19, :lo12:tasks]
    adrp x20, task_count
    ldr x20, [x20, :lo12:task_count]
    cbz x20, L_main_done
    // One-file workloads do not pay for a thread pool. Multiple files are
    // independently scheduled with a bounded worker count.
    cmp x20, #1
    b.ne L_parallel
    mov x0, x19
    mov x1, #0
    bl process_task
    b L_processed
L_parallel:
    bl run_tasks
L_processed:
    // Aggregate only successfully read tasks, preserving argument/traversal order.
    mov x21, #0
    mov x22, #0
    adrp x23, totals
    add x23, x23, :lo12:totals
L_print_loop:
    cmp x21, x20
    b.hs L_print_totals
    mov x9, #96
    madd x24, x21, x9, x19
    ldr x9, [x24, #80]
    cbz x9, L_print_next
    add x22, x22, #1
    add x0, x24, #16
    ldr x1, [x24]
    bl emit_counts
    ldp x9, x10, [x24, #16]
    ldp x11, x12, [x23]
    add x9, x9, x11
    add x10, x10, x12
    stp x9, x10, [x23]
    ldp x9, x10, [x24, #32]
    ldp x11, x12, [x23, #16]
    add x9, x9, x11
    add x10, x10, x12
    stp x9, x10, [x23, #16]
    ldr x9, [x24, #48]
    ldr x10, [x23, #32]
    cmp x9, x10
    csel x9, x9, x10, hi
    str x9, [x23, #32]
L_print_next:
    add x21, x21, #1
    b L_print_loop
L_print_totals:
    cmp x22, #1
    b.ls L_main_done
    mov w0, #10
    bl putchar
    tbnz w0, #31, L_output_failed
    mov x0, x23
    adrp x1, L_total
    add x1, x1, :lo12:L_total
    bl emit_counts
L_main_done:
    adrp x9, :got:stdout
    ldr x9, [x9, :got_lo12:stdout]
    ldr x0, [x9]
    bl fflush
    tbnz w0, #31, L_output_failed
    mov w0, #0
    ldp x23, x24, [sp, #48]
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #96
    ret

// fts comparisons use the generated libc offsets, with bytewise name order.
.p2align 2
compare_entries:
    ldr x0, [x0]
    ldr x1, [x1]
    add x0, x0, #ABI_FTS_NAME
    add x1, x1, #ABI_FTS_NAME
    b strcmp

// glibc fts may trim a root's trailing separators. Preserve the caller's exact
// root spelling and form descendant paths relative to the first fts entry.
// x0=root. Traversal uses physical descendants and follows a root symlink.
.p2align 2
collect_path:
    stp x29, x30, [sp, #-112]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    stp x23, x24, [sp, #64]
    stp x25, x26, [sp, #80]
    mov x22, x0
    bl strlen
    mov x23, x0
    mov x25, #-1
    str x22, [sp, #48]
    str xzr, [sp, #56]
    add x0, sp, #48
    mov w1, #(ABI_FTS_PHYSICAL | ABI_FTS_NOCHDIR | ABI_FTS_COMFOLLOW)
    adrp x2, compare_entries
    add x2, x2, :lo12:compare_entries
    bl fts_open
    cbz x0, L_collect_done
    mov x19, x0
    adrp x21, asmwc_recursive
    ldr x21, [x21, :lo12:asmwc_recursive]
L_fts_next:
    mov x0, x19
    bl fts_read
    cbz x0, L_fts_close
    mov x20, x0
    cmp x25, #-1
    b.ne L_fts_info
    ldr x0, [x20, #ABI_FTS_PATH]
    bl strlen
    mov x25, x0
L_fts_info:
    ldrh w9, [x20, #ABI_FTS_INFO]
    cmp w9, #ABI_FTS_DP
    b.eq L_fts_next
    cmp w9, #ABI_FTS_ERR
    b.eq L_fts_continue
    cmp w9, #ABI_FTS_NS
    b.eq L_fts_continue
    cmp w9, #ABI_FTS_DC
    b.eq L_fts_continue
#if ABI_FTS_LEVEL_SIZE == 2
    ldrsh x9, [x20, #ABI_FTS_LEVEL]
#elif ABI_FTS_LEVEL_SIZE == 4
    ldrsw x9, [x20, #ABI_FTS_LEVEL]
#elif ABI_FTS_LEVEL_SIZE == 8
    ldr x9, [x20, #ABI_FTS_LEVEL]
#else
#error Unsupported glibc FTS level field width
#endif
    cbnz x9, L_fts_descendant
    mov x0, x22
    bl add_task
    b L_fts_continue
L_fts_descendant:
    ldr x24, [x20, #ABI_FTS_PATH]
    add x24, x24, x25
L_fts_skip_slash:
    ldrb w9, [x24]
    cmp w9, #47
    b.ne L_fts_suffix
    add x24, x24, #1
    b L_fts_skip_slash
L_fts_suffix:
    mov x0, x24
    bl strlen
    add x0, x0, x23
    add x0, x0, #2
    bl malloc
    cbz x0, L_out_of_memory
    mov x26, x0
    mov x1, x22
    mov x2, x23
    bl memcpy
    add x0, x26, x23
    cbz x23, L_fts_join_slash
    ldrb w9, [x0, #-1]
    cmp w9, #47
    b.eq L_fts_join_suffix
L_fts_join_slash:
    mov w9, #47
    strb w9, [x0], #1
L_fts_join_suffix:
    mov x1, x24
    bl strcpy
    mov x0, x26
    bl add_task
    mov x0, x26
    bl free
L_fts_continue:
    cbnz x21, L_fts_next
L_fts_close:
    mov x0, x19
    bl fts_close
L_collect_done:
    ldp x25, x26, [sp, #80]
    ldp x23, x24, [sp, #64]
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #112
    ret

// Up to 32 workers independently reserve files. If thread creation fails,
// the calling thread handles the remaining work. Output retains input order.
.p2align 2
run_tasks:
    stp x29, x30, [sp, #-320]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    mov x19, #0
    mov x0, #ABI_SC_NPROCESSORS_ONLN
    bl sysconf
    cmp x0, #1
    mov x9, #1
    csel x20, x0, x9, gt
    mov x9, #32
    cmp x20, x9
    csel x20, x20, x9, lo
    adrp x9, task_count
    ldr x9, [x9, :lo12:task_count]
    cmp x20, x9
    csel x20, x20, x9, lo
    sub x20, x20, #1
    mov x21, #0
L_create_worker:
    cmp x21, x20
    b.hs L_main_worker
    add x0, sp, #64
    add x0, x0, x19, lsl #3
    mov x1, #0
    adrp x2, task_worker
    add x2, x2, :lo12:task_worker
    mov x3, #0
    bl pthread_create
    cbnz w0, L_created_next
    add x19, x19, #1
L_created_next:
    add x21, x21, #1
    b L_create_worker
L_main_worker:
    mov x0, #0
    bl task_worker
    mov x21, #0
L_join_worker:
    cmp x21, x19
    b.hs L_joined
    add x9, sp, #64
    ldr x0, [x9, x21, lsl #3]
    mov x1, #0
    bl pthread_join
    add x21, x21, #1
    b L_join_worker
L_joined:
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #320
    ret

.p2align 2
task_worker:
    stp x29, x30, [sp, #-32]!
    stp x19, x20, [sp, #16]
    adrp x19, task_next
    add x19, x19, :lo12:task_next
    adrp x20, task_count
    ldr x20, [x20, :lo12:task_count]
L_worker_next:
    ldaxr x1, [x19]
    cmp x1, x20
    b.hs L_worker_done
    add x9, x1, #1
    stlxr w10, x9, [x19]
    cbnz w10, L_worker_next
    adrp x0, tasks
    ldr x0, [x0, :lo12:tasks]
    bl process_task
    b L_worker_next
L_worker_done:
    clrex
    mov x0, #0
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #32
    ret

// Task: path@0, saved metadata length@8, 64-byte count state@16,
// successful@80, metadata available@88. Stride=96, initially zeroed.
.p2align 2
add_task:
    sub sp, sp, #((ABI_STAT_SIZE + 79) & -16)
    stp x29, x30, [sp]
    mov x29, sp
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    mov x19, x0
    adrp x20, task_count
    ldr x21, [x20, :lo12:task_count]
    adrp x9, task_capacity
    ldr x10, [x9, :lo12:task_capacity]
    cmp x21, x10
    b.lo L_capacity_ok
    lsl x10, x10, #1
    cmp x10, #64
    mov x11, #64
    csel x22, x10, x11, hs
    adrp x0, tasks
    ldr x0, [x0, :lo12:tasks]
    mov x1, #96
    mul x1, x22, x1
    bl realloc
    cbz x0, L_out_of_memory
    adrp x9, tasks
    str x0, [x9, :lo12:tasks]
    adrp x9, task_capacity
    str x22, [x9, :lo12:task_capacity]
L_capacity_ok:
    adrp x9, tasks
    ldr x9, [x9, :lo12:tasks]
    mov x10, #96
    madd x22, x21, x10, x9
    stp xzr, xzr, [x22]
    stp xzr, xzr, [x22, #16]
    stp xzr, xzr, [x22, #32]
    stp xzr, xzr, [x22, #48]
    stp xzr, xzr, [x22, #64]
    stp xzr, xzr, [x22, #80]
    mov x0, x19
    bl strdup
    cbz x0, L_out_of_memory
    str x0, [x22]
    mov x0, x19
    add x1, sp, #64
    bl stat
    cbnz w0, L_task_added
    ldr x9, [sp, #(64 + ABI_STAT_ST_SIZE)]
    str x9, [x22, #8]
    mov x9, #1
    str x9, [x22, #88]
L_task_added:
    add x21, x21, #1
    str x21, [x20, :lo12:task_count]
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp]
    add sp, sp, #((ABI_STAT_SIZE + 79) & -16)
    ret
L_out_of_memory:
    mov w0, #1
    bl exit

// x0=tasks base, x1=index. Each task has independent count state.
.p2align 2
process_task:
    sub sp, sp, #128
    stp x29, x30, [sp, #112]
    add x29, sp, #112
    stp x19, x20, [sp, #32]
    stp x21, x22, [sp, #48]
    stp x23, x24, [sp, #64]
    stp x25, x26, [sp, #80]
    mov x9, #96
    madd x19, x1, x9, x0
    adrp x20, asmwc_flags
    ldr x20, [x20, :lo12:asmwc_flags]
    ldr x21, [x19, #8]
    // Upstream only logs >=512 KiB entries, and logs before trying open.
    ldr x9, [x19, #88]
    cbz x9, L_maybe_verbose
    cmp x21, #128, lsl #12
    b.lo L_open_file
L_maybe_verbose:
    adrp x9, asmwc_verbose
    ldr x9, [x9, :lo12:asmwc_verbose]
    cbz x9, L_open_file
    ldr x0, [x19]
    bl asmwc_path_lossy
    mov x25, x0
    adrp x9, :got:stderr
    ldr x9, [x9, :got_lo12:stderr]
    ldr x0, [x9]
    adrp x1, L_processing
    add x1, x1, :lo12:L_processing
    mov x2, x25
    bl fprintf
    mov w26, w0
    mov x0, x25
    bl free
    mov w0, w26
    tbnz w0, #31, L_process_done
L_open_file:
    ldr x0, [x19]
    mov w1, #0
    bl open
    tbz w0, #31, L_opened
    bl __errno_location
    ldr w9, [x0]
    cmp w9, #ABI_EINTR
    b.eq L_open_file
    b L_process_done
L_opened:
    mov w22, w0
    cmp x20, #1
    b.ne L_scan_file
    ldr x9, [x19, #88]
    cbz x9, L_scan_file
    str x21, [x19, #16]
    b L_close_success
L_scan_file:
L_scan_buffered:
    // Buffered reads preserve EOF and partial-read behavior for every file type.
    // Smaller files use 256 KiB; large files use a 1 MiB working buffer.
    mov x24, #0x40000
    mov x9, #0x100000
    cmp x21, #2048, lsl #12
    csel x24, x24, x9, lo
    mov x0, x24
    bl malloc
    cbz x0, L_close_failed
    mov x23, x0
L_read_next:
    mov w0, w22
    mov x1, x23
    mov x2, x24
    bl read
    tbz x0, #63, L_read_result
    bl __errno_location
    ldr w9, [x0]
    cmp w9, #ABI_EINTR
    b.eq L_read_next
    b L_read_failed
L_read_result:
    cbz x0, L_eof
    mov x1, x0
    mov x0, x23
    mov x2, x20
    add x3, x19, #16
    bl asmwc_count_buffer
    b L_read_next
L_eof:
    mov x0, x23
    bl free
L_finalize_fields:
    // Finish an unterminated word and final line exactly once at EOF.
    tbz x20, #3, L_finalize_max
    ldr x9, [x19, #56]
    ldr x10, [x19, #32]
    add x10, x10, x9
    str x10, [x19, #32]
L_finalize_max:
    tbz x20, #4, L_fallback_bytes
    ldr x9, [x19, #64]
    ldr x10, [x19, #48]
    cmp x9, x10
    csel x9, x9, x10, hi
    str x9, [x19, #48]
L_fallback_bytes:
    tbz x20, #0, L_close_success
    ldr x9, [x19, #16]
    cbnz x9, L_close_success
    ldr x9, [x19, #88]
    cbz x9, L_close_success
    str x21, [x19, #16]
L_close_success:
    mov x9, #1
    str x9, [x19, #80]
    mov w0, w22
    bl close
    b L_process_done
L_read_failed:
    mov x0, x23
    bl free
L_close_failed:
    mov w0, w22
    bl close
L_process_done:
    ldp x25, x26, [sp, #80]
    ldp x23, x24, [sp, #64]
    ldp x21, x22, [sp, #48]
    ldp x19, x20, [sp, #32]
    ldp x29, x30, [sp, #112]
    add sp, sp, #128
    ret

.macro EMIT_FIELD bit, offset, label
    tbz x22, #\bit, 9f
    ldr x9, [x19, #\offset]
    cbz x9, 9f
    adrp x0, \label
    add x0, x0, :lo12:\label
    // Every stored label starts with a space; skip it for the first field.
    add x0, x0, x21
    mov x1, x9
    bl printf
    tbnz w0, #31, L_output_failed
    mov x21, #0
9:
.endm

.p2align 2
emit_counts:
    sub sp, sp, #64
    stp x29, x30, [sp, #48]
    add x29, sp, #48
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    mov x19, x0
    mov x0, x1
    bl asmwc_path_lossy
    mov x20, x0
    mov x21, #1
    adrp x22, asmwc_flags
    ldr x22, [x22, :lo12:asmwc_flags]
    EMIT_FIELD 2, 24, L_lines
    EMIT_FIELD 3, 16, L_words
    EMIT_FIELD 1, 8, L_chars
    EMIT_FIELD 0, 0, L_bytes
    EMIT_FIELD 4, 32, L_max
    adrp x0, L_path_format
    add x0, x0, :lo12:L_path_format
    mov x1, x20
    bl printf
    tbnz w0, #31, L_output_failed
    mov x0, x20
    bl free
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp, #48]
    add sp, sp, #64
    ret

// Match Rust's io::Error debug rendering when a counted-output write fails.
// glibc strerror supplies the platform message used by std::io.
.p2align 2
L_output_failed:
    sub sp, sp, #64
    bl __errno_location
    ldr w19, [x0]
    adrp x20, L_kind_other
    add x20, x20, :lo12:L_kind_other
    adrp x9, L_error_kinds
    add x9, x9, :lo12:L_error_kinds
L_error_kind_next:
    ldp x10, x11, [x9], #16
    cbz x10, L_error_kind_found
    cmp w19, w10
    b.ne L_error_kind_next
    adrp x20, L_kind_base
    add x20, x20, :lo12:L_kind_base
    add x20, x20, x11
L_error_kind_found:
    mov w0, w19
    bl strerror
    mov x4, x0
    mov x3, x20
    mov w2, w19
    adrp x9, :got:stderr
    ldr x9, [x9, :got_lo12:stderr]
    ldr x0, [x9]
    adrp x1, L_output_error
    add x1, x1, :lo12:L_output_error
    bl fprintf
    mov w0, #1
    bl exit

.section .rodata
L_lines: .asciz " lines: %llu"
L_words: .asciz " words: %llu"
L_chars: .asciz " chars: %llu"
L_bytes: .asciz " bytes: %llu"
L_max: .asciz " max line length: %llu"
L_path_format: .asciz " %s\n"
L_processing: .asciz "Processing: %s\n"
L_total: .asciz "total"
L_output_error: .asciz "Error: Os { code: %d, kind: %s, message: \"%s\" }\n"
L_kind_base:
L_kind_other: .asciz "Uncategorized"
L_kind_pipe: .asciz "BrokenPipe"
L_kind_full: .asciz "StorageFull"
L_kind_invalid: .asciz "InvalidInput"
L_kind_permission: .asciz "PermissionDenied"
L_kind_directory: .asciz "IsADirectory"
L_kind_large: .asciz "FileTooLarge"
L_kind_again: .asciz "WouldBlock"
L_kind_interrupted: .asciz "Interrupted"
L_kind_memory: .asciz "OutOfMemory"

.section .rodata
.p2align 3
L_error_kinds:
    .quad ABI_EPIPE, L_kind_pipe-L_kind_base
    .quad ABI_ENOSPC, L_kind_full-L_kind_base
    .quad ABI_EINVAL, L_kind_invalid-L_kind_base
    .quad ABI_EACCES, L_kind_permission-L_kind_base
    .quad ABI_EISDIR, L_kind_directory-L_kind_base
    .quad ABI_EFBIG, L_kind_large-L_kind_base
    .quad ABI_EAGAIN, L_kind_again-L_kind_base
    .quad ABI_EINTR, L_kind_interrupted-L_kind_base
    .quad ABI_ENOMEM, L_kind_memory-L_kind_base
    .quad 0, 0

.bss
.p2align 3
tasks: .zero 8
task_count: .zero 8
task_capacity: .zero 8
task_next: .zero 8
.p2align 4
totals: .zero 64

.section .note.GNU-stack,"",%progbits
