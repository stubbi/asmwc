// Overlap sequential reads with counting through a four-slot buffer pool.
// x0=fd, x1=flags, x2=zeroed 64-byte count state.
// Return 0 on success, -1 on read error, or 1 on setup failure before any read.
// The caller may fall back to buffered reads after setup failure.
// Only the calling thread reads fd; the serial queue updates count state.
.text
.p2align 2
.globl _asmwc_pipeline_scan
_asmwc_pipeline_scan:
    stp x29, x30, [sp, #-144]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    stp x23, x24, [sp, #48]
    stp x25, x26, [sp, #64]
    stp x27, x28, [sp, #80]
    mov w19, w0
    mov x20, x1
    mov x21, x2
    mov x0, #0x400000
    add x0, x0, #512
    bl _malloc
    cbz x0, Lpipeline_nomem
    mov x22, x0
    mov x1, #0
    mov x2, #512
    bl _memset
    bl _dispatch_group_create
    cbz x0, Lpipeline_group_failed
    mov x23, x0
    mov x0, #0
    mov x1, #0
    bl _dispatch_queue_create
    cbz x0, Lpipeline_queue_failed
    mov x24, x0
    mov x25, #0  // slot index
    mov x27, #0  // return status
Lpipeline_read:
    add x28, x22, x25, lsl #7
    add x1, x22, #512
    add x1, x1, x25, lsl #20
    str x1, [x28]
    mov w0, w19
    mov x2, #0x100000
    bl _read
    tbnz x0, #63, Lpipeline_read_error
    cbz x0, Lpipeline_eof
    str x0, [x28, #8]
    str x20, [x28, #16]
    str x21, [x28, #24] // shared state; serial queue preserves chunk order
    mov x0, x23
    mov x1, x24
    mov x2, x28
    adrp x3, Lpipeline_count@PAGE
    add x3, x3, Lpipeline_count@PAGEOFF
    bl _dispatch_group_async_f
    add x25, x25, #1
    cmp x25, #4
    b.lo Lpipeline_read
    // Finish the bounded batch before reusing its storage. Counts accumulate
    // across batches; FIFO callback execution carries word and line state.
    mov x0, x23
    mov x1, #-1
    bl _dispatch_group_wait
    mov x25, #0
    b Lpipeline_read
Lpipeline_read_error:
    mov x27, #-1
Lpipeline_eof:
    mov x0, x23
    mov x1, #-1
    bl _dispatch_group_wait
    mov x0, x23
    bl _dispatch_release
Lpipeline_free:
    mov x0, x24
    bl _dispatch_release
    mov x0, x22
    bl _free
    mov x0, x27
    b Lpipeline_return
Lpipeline_queue_failed:
    mov x0, x23
    bl _dispatch_release
Lpipeline_group_failed:
    mov x0, x22
    bl _free
Lpipeline_nomem:
    mov x0, #1
Lpipeline_return:
    ldp x27, x28, [sp, #80]
    ldp x25, x26, [sp, #64]
    ldp x23, x24, [sp, #48]
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #144
    ret

.p2align 2
Lpipeline_count:
    mov x9, x0
    ldp x0, x1, [x9]
    ldr x2, [x9, #16]
    ldr x3, [x9, #24]
    b _asmwc_count_buffer
.subsections_via_symbols
