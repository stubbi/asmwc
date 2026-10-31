// Native ARM64 macOS application logic. libc/libdispatch provide OS services;
// parsing, traversal policy, counting, aggregation and formatting are assembly.
.section __TEXT,__text,regular,pure_instructions
.p2align 2
.globl _main
_main:
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
    bl _signal
    mov x0, x19
    mov x1, x20
    bl _ripwc_parse
    adrp x9, ___stdoutp@GOTPAGE
    ldr x9, [x9, ___stdoutp@GOTPAGEOFF]
    ldr x0, [x9]
    mov x1, #0
    mov w2, #1 // _IOLBF: one flush per newline, like Rust's stdout LineWriter
    mov x3, #0
    bl _setvbuf
    adrp x19, _ripwc_paths@PAGE
    ldr x19, [x19, _ripwc_paths@PAGEOFF]
    adrp x20, _ripwc_nargs@PAGE
    ldr x20, [x20, _ripwc_nargs@PAGEOFF]
    mov x21, #0
L_collect_args:
    cmp x21, x20
    b.hs L_collected
    ldr x0, [x19, x21, lsl #3]
    bl _collect_path
    add x21, x21, #1
    b L_collect_args
L_collected:
    adrp x19, _tasks@PAGE
    ldr x19, [x19, _tasks@PAGEOFF]
    adrp x20, _task_count@PAGE
    ldr x20, [x20, _task_count@PAGEOFF]
    cbz x20, L_main_done
    // One-file workloads do not pay for a thread pool. Multiple files are
    // independently scheduled using the same available machine cores as Rust.
    cmp x20, #1
    b.ne L_parallel
    mov x0, x19
    mov x1, #0
    bl _process_task
    b L_processed
L_parallel:
    mov x0, #0
    mov x1, #0
    bl _dispatch_get_global_queue
    mov x1, x0
    mov x0, x20
    mov x2, x19
    adrp x3, _process_task@PAGE
    add x3, x3, _process_task@PAGEOFF
    bl _dispatch_apply_f
L_processed:
    // Aggregate only successfully read tasks, preserving argument/traversal order.
    mov x21, #0
    mov x22, #0
    adrp x23, _totals@PAGE
    add x23, x23, _totals@PAGEOFF
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
    bl _emit_counts
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
    bl _putchar
    tbnz w0, #31, L_output_failed
    mov x0, x23
    adrp x1, L_total@PAGE
    add x1, x1, L_total@PAGEOFF
    bl _emit_counts
L_main_done:
    mov x0, #0
    bl _fflush
    tbnz w0, #31, L_output_failed
    mov w0, #0
    ldp x23, x24, [sp, #48]
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #96
    ret

// fts comparator receives pointers to entry pointers. fts_name is offset 104
// in the native ARM64 Darwin ABI. Names compare bytewise, as WalkDir does.
.p2align 2
_compare_entries:
    ldr x0, [x0]
    ldr x1, [x1]
    add x0, x0, #104
    add x1, x1, #104
    b _strcmp

.p2align 2
_collect_path:
    stp x29, x30, [sp, #-80]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    str x0, [sp, #48]
    str xzr, [sp, #56]
    add x0, sp, #48
    mov w1, #21  // FTS_PHYSICAL | FTS_NOCHDIR | FTS_COMFOLLOW
    adrp x2, _compare_entries@PAGE
    add x2, x2, _compare_entries@PAGEOFF
    bl _fts_open
    cbz x0, L_collect_done
    mov x19, x0
    adrp x21, _ripwc_recursive@PAGE
    ldr x21, [x21, _ripwc_recursive@PAGEOFF]
L_fts_next:
    mov x0, x19
    bl _fts_read
    cbz x0, L_fts_close
    mov x20, x0
    ldrh w9, [x20, #88] // fts_info
    cmp w9, #6         // suppress postorder directory duplicates
    b.eq L_fts_next
    cmp w9, #7         // WalkDir drops traversal errors
    b.eq L_fts_continue
    cmp w9, #10        // nonexistent path
    b.eq L_fts_continue
    cmp w9, #4         // unreadable directory -> WalkDir still emits entry
    b.eq L_fts_add
    cmp w9, #2         // cycle error (physical traversal normally avoids it)
    b.eq L_fts_continue
L_fts_add:
    ldr x0, [x20, #48]
    bl _add_task
L_fts_continue:
    cbnz x21, L_fts_next
L_fts_close:
    mov x0, x19
    bl _fts_close
L_collect_done:
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #80
    ret

// Task: path@0, saved metadata length@8, 64-byte count state@16,
// successful@80, metadata available@88. Stride=96, initially zeroed.
.p2align 2
_add_task:
    stp x29, x30, [sp, #-224]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    mov x19, x0
    adrp x20, _task_count@PAGE
    ldr x21, [x20, _task_count@PAGEOFF]
    adrp x9, _task_capacity@PAGE
    ldr x10, [x9, _task_capacity@PAGEOFF]
    cmp x21, x10
    b.lo L_capacity_ok
    lsl x10, x10, #1
    cmp x10, #64
    mov x11, #64
    csel x22, x10, x11, hs
    adrp x0, _tasks@PAGE
    ldr x0, [x0, _tasks@PAGEOFF]
    mov x1, #96
    mul x1, x22, x1
    bl _realloc
    cbz x0, L_out_of_memory
    adrp x9, _tasks@PAGE
    str x0, [x9, _tasks@PAGEOFF]
    adrp x9, _task_capacity@PAGE
    str x22, [x9, _task_capacity@PAGEOFF]
L_capacity_ok:
    adrp x9, _tasks@PAGE
    ldr x9, [x9, _tasks@PAGEOFF]
    mov x10, #96
    madd x22, x21, x10, x9
    stp xzr, xzr, [x22]
    stp xzr, xzr, [x22, #16]
    stp xzr, xzr, [x22, #32]
    stp xzr, xzr, [x22, #48]
    stp xzr, xzr, [x22, #64]
    stp xzr, xzr, [x22, #80]
    mov x0, x19
    bl _strdup
    cbz x0, L_out_of_memory
    str x0, [x22]
    mov x0, x19
    add x1, sp, #64
    bl _stat
    cbnz w0, L_task_added
    ldr x9, [sp, #160] // stat.st_size = 96
    str x9, [x22, #8]
    mov x9, #1
    str x9, [x22, #88]
L_task_added:
    add x21, x21, #1
    str x21, [x20, _task_count@PAGEOFF]
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #224
    ret
L_out_of_memory:
    mov w0, #1
    bl _exit

// libdispatch callback: x0=tasks base, x1=index. No shared count writes.
.p2align 2
_process_task:
    sub sp, sp, #128
    stp x29, x30, [sp, #112]
    add x29, sp, #112
    stp x19, x20, [sp, #32]
    stp x21, x22, [sp, #48]
    stp x23, x24, [sp, #64]
    stp x25, x26, [sp, #80]
    mov x9, #96
    madd x19, x1, x9, x0
    adrp x20, _ripwc_flags@PAGE
    ldr x20, [x20, _ripwc_flags@PAGEOFF]
    ldr x21, [x19, #8]
    // Upstream only logs >=512 KiB entries, and logs before trying open.
    ldr x9, [x19, #88]
    cbz x9, L_maybe_verbose
    cmp x21, #128, lsl #12
    b.lo L_open_file
L_maybe_verbose:
    adrp x9, _ripwc_verbose@PAGE
    ldr x9, [x9, _ripwc_verbose@PAGEOFF]
    cbz x9, L_open_file
    adrp x9, ___stderrp@GOTPAGE
    ldr x9, [x9, ___stderrp@GOTPAGEOFF]
    ldr x0, [x9]
    adrp x1, L_processing@PAGE
    add x1, x1, L_processing@PAGEOFF
    ldr x9, [x19]
    str x9, [sp]
    bl _fprintf
    tbnz w0, #31, L_process_done
L_open_file:
    ldr x0, [x19]
    mov w1, #0
    bl _open
    tbnz w0, #31, L_process_done
    mov w22, w0
    cmp x20, #1
    b.ne L_scan_file
    ldr x9, [x19, #88]
    cbz x9, L_scan_file
    str x21, [x19, #16]
    b L_close_success
L_scan_file:
    tbz x20, #3, L_scan_buffered
    adrp x9, _task_count@PAGE
    ldr x9, [x9, _task_count@PAGEOFF]
    cmp x9, #1
    b.ne L_scan_buffered
    cmp x21, #2048, lsl #12
    b.lo L_scan_buffered
    mov w0, w22
    mov x1, x20
    add x2, x19, #16
    bl _ripwc_pipeline_scan
    cmp w0, #1
    b.eq L_scan_buffered
    cbnz w0, L_close_failed
    b L_finalize_fields
L_scan_buffered:
    // Buffered reads preserve EOF and partial-read behavior for every file type.
    // Smaller files use a smaller working set; large single-mode reads retain1MiB.
    mov x24, #0x40000
    mov x9, #0x100000
    cmp x21, #2048, lsl #12
    csel x24, x24, x9, lo
    mov x0, x24
    bl _malloc
    cbz x0, L_close_failed
    mov x23, x0
L_read_next:
    mov w0, w22
    mov x1, x23
    mov x2, x24
    bl _read
    tbnz x0, #63, L_read_failed
    cbz x0, L_eof
    mov x1, x0
    mov x0, x23
    mov x2, x20
    add x3, x19, #16
    bl _ripwc_count_buffer
    b L_read_next
L_eof:
    mov x0, x23
    bl _free
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
    bl _close
    b L_process_done
L_read_failed:
    mov x0, x23
    bl _free
L_close_failed:
    mov w0, w22
    bl _close
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
    adrp x0, \label@PAGE
    add x0, x0, \label@PAGEOFF
    // Every stored label starts with a space; skip it for the first field.
    add x0, x0, x21
    str x9, [sp]
    bl _printf
    tbnz w0, #31, L_output_failed
    mov x21, #0
9:
.endmacro

.p2align 2
_emit_counts:
    sub sp, sp, #64
    stp x29, x30, [sp, #48]
    add x29, sp, #48
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    mov x19, x0
    mov x20, x1
    mov x21, #1
    adrp x22, _ripwc_flags@PAGE
    ldr x22, [x22, _ripwc_flags@PAGEOFF]
    EMIT_FIELD 2, 24, L_lines
    EMIT_FIELD 3, 16, L_words
    EMIT_FIELD 1, 8, L_chars
    EMIT_FIELD 0, 0, L_bytes
    EMIT_FIELD 4, 32, L_max
    adrp x0, L_path_format@PAGE
    add x0, x0, L_path_format@PAGEOFF
    str x20, [sp]
    bl _printf
    tbnz w0, #31, L_output_failed
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp, #48]
    add sp, sp, #64
    ret

// Match Rust's io::Error debug rendering when a counted-output write fails.
// Darwin strerror supplies the same platform message used by std::io.
.p2align 2
L_output_failed:
    sub sp, sp, #64
    bl ___error
    ldr w19, [x0]
    adrp x20, L_kind_other@PAGE
    add x20, x20, L_kind_other@PAGEOFF
    adrp x9, L_error_kinds@PAGE
    add x9, x9, L_error_kinds@PAGEOFF
L_error_kind_next:
    ldp x10, x11, [x9], #16
    cbz x10, L_error_kind_found
    cmp w19, w10
    b.ne L_error_kind_next
    adrp x20, L_kind_base@PAGE
    add x20, x20, L_kind_base@PAGEOFF
    add x20, x20, x11
L_error_kind_found:
    mov w0, w19
    bl _strerror
    str x0, [sp, #16]
    str x20, [sp, #8]
    str x19, [sp]
    adrp x9, ___stderrp@GOTPAGE
    ldr x9, [x9, ___stderrp@GOTPAGEOFF]
    ldr x0, [x9]
    adrp x1, L_output_error@PAGE
    add x1, x1, L_output_error@PAGEOFF
    bl _fprintf
    mov w0, #1
    bl _exit

.section __TEXT,__cstring,cstring_literals
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

.section __TEXT,__const
.p2align 3
L_error_kinds:
    .quad 32, L_kind_pipe-L_kind_base
    .quad 28, L_kind_full-L_kind_base
    .quad 22, L_kind_invalid-L_kind_base
    .quad 13, L_kind_permission-L_kind_base
    .quad 21, L_kind_directory-L_kind_base
    .quad 27, L_kind_large-L_kind_base
    .quad 35, L_kind_again-L_kind_base
    .quad 4, L_kind_interrupted-L_kind_base
    .quad 12, L_kind_memory-L_kind_base
    .quad 0, 0

.zerofill __DATA,__bss,_tasks,8,3
.zerofill __DATA,__bss,_task_count,8,3
.zerofill __DATA,__bss,_task_capacity,8,3
.zerofill __DATA,__bss,_totals,64,4
.subsections_via_symbols
