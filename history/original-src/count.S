/* Apple arm64 ABI: x0=data, x1=length, x2=flags, x3=64-byte state.
 * State: bytes, non-NUL characters, ended words, LF lines, max line,
 *        pending word, current line length, reserved (all uint64_t).
 * No load crosses the input boundary. Only caller-saved registers are used.
 */
.text

// Convert one 16-byte block into separator transitions and optional LF/NUL
// counts. Mask bytes are 0xff, so subtraction increments the count lanes.
.macro COUNT_VECTOR src, m, l, w
.if \w
    cmeq v16.16b, \src\().16b, v25.16b
    cmeq v17.16b, \src\().16b, v26.16b
    cmeq v18.16b, \src\().16b, v24.16b
    cmeq v19.16b, \src\().16b, v27.16b
    orr v16.16b, v16.16b, v17.16b
.if \l
    sub v20.16b, v20.16b, v18.16b
.endif
    orr v18.16b, v18.16b, v19.16b
    orr v16.16b, v16.16b, v18.16b
    ext v17.16b, v31.16b, v16.16b, #15
    bic v17.16b, v16.16b, v17.16b
    sub v21.16b, v21.16b, v17.16b
    mov v31.16b, v16.16b
.elseif \l
    cmeq v18.16b, \src\().16b, v24.16b
    sub v20.16b, v20.16b, v18.16b
.endif
.if \m
    cmeq v17.16b, \src\().16b, #0
    sub v22.16b, v22.16b, v17.16b
.endif
.endm

// The 8-bit accumulators are reduced after at most 128 vectors (2 KiB),
// avoiding saturation even for all-LF/all-NUL input. Four vectors per loop
// amortize branches and let independent comparisons overlap on Apple M3.
.macro NEON_LOOP name, m, l, w
Lneon_\name\():
Louter\@:
.if \l
    movi v20.16b, #0
.endif
.if \w
    movi v21.16b, #0
.endif
.if \m
    movi v22.16b, #0
.endif
    lsr x12, x1, #6
    mov x13, #32
    cmp x12, x13
    csel x12, x12, x13, lo
.if \m
    add x5, x5, x12, lsl #6
.endif
Linner\@:
    ldp q0, q1, [x0], #32
    ldp q2, q3, [x0], #32
    COUNT_VECTOR v0, \m, \l, \w
    COUNT_VECTOR v1, \m, \l, \w
    COUNT_VECTOR v2, \m, \l, \w
    COUNT_VECTOR v3, \m, \l, \w
    sub x1, x1, #64
    subs x12, x12, #1
    b.ne Linner\@
.if \l
    uaddlv h23, v20.16b
    umov w11, v23.h[0]
    add x7, x7, x11
.endif
.if \w
    uaddlv h23, v21.16b
    umov w11, v23.h[0]
    add x6, x6, x11
.endif
.if \m
    uaddlv h23, v22.16b
    umov w11, v23.h[0]
    sub x5, x5, x11
.endif
    cmp x1, #64
    b.hs Louter\@
.if \w
    umov w9, v31.b[15]
    cmp w9, #0
    cset x9, eq
.endif
    cbnz x1, Lscalar
    b Lstore
.endm

.p2align 4
.globl _ripwc_count_buffer
_ripwc_count_buffer:
    ldp x4, x5, [x3]
    ldp x6, x7, [x3, #16]
    ldp x8, x9, [x3, #32]
    ldr x10, [x3, #48]
    tbz x2, #0, Lbytes_done
    add x4, x4, x1
Lbytes_done:
    cbz x1, Lstore
    // Maximum line length uses the positions of LF bytes. A bounded
    // preliminary vector pass skips entire 16-byte blocks without LF.
    tbz x2, #4, Lmax_scan_done
    mov x14, x0
    mov x15, x1
    movi v24.16b, #10
Lmax_vector:
    cmp x15, #16
    b.lo Lmax_tail
    ldr q0, [x14], #16
    cmeq v16.16b, v0.16b, v24.16b
    // Narrow each 16-bit pair to two four-bit masks. Every input byte
    // owns a nibble in the scalar register, preserving byte positions.
    shrn v16.8b, v16.8h, #4
    fmov x11, d16
    cbnz x11, Lmax_has_lf
    add x10, x10, #16
Lmax_vector_next:
    sub x15, x15, #16
    b Lmax_vector
Lmax_has_lf:
    mov x12, #16
Lmax_next_lf:
    rbit x13, x11
    clz x13, x13
    lsr x13, x13, #2
    add x10, x10, x13
    cmp x10, x8
    csel x8, x10, x8, hi
    mov x10, #0
    add x13, x13, #1
    sub x12, x12, x13
    // Avoid a shift by 64, which AArch64 would interpret as zero.
    cbz x12, Lmax_vector_next
    lsl x13, x13, #2
    lsr x11, x11, x13
    cbnz x11, Lmax_next_lf
    add x10, x10, x12
    b Lmax_vector_next
Lmax_tail:
    cbz x15, Lmax_scan_done
Lmax_tail_loop:
    ldrb w11, [x14], #1
    cmp w11, #10
    b.ne Lmax_tail_increment
    cmp x10, x8
    csel x8, x10, x8, hi
    mov x10, #0
    b Lmax_tail_next
Lmax_tail_increment:
    add x10, x10, #1
Lmax_tail_next:
    subs x15, x15, #1
    b.ne Lmax_tail_loop
Lmax_scan_done:
    and w11, w2, #14
    cbz w11, Lstore
    cmp x1, #64
    b.lo Lscalar
    movi v24.16b, #10
    movi v25.16b, #32
    movi v26.16b, #9
    movi v27.16b, #13
    // A separator mask before byte zero carries the pending-word state.
    eor x12, x9, #1
    neg w12, w12
    dup v31.16b, w12
    cmp w11, #2
    b.eq Lneon_m
    cmp w11, #4
    b.eq Lneon_l
    cmp w11, #6
    b.eq Lneon_ml
    cmp w11, #8
    b.eq Lneon_w
    cmp w11, #10
    b.eq Lneon_mw
    cmp w11, #12
    b.eq Lneon_lw
    b Lneon_mlw
    NEON_LOOP m,   1, 0, 0
    NEON_LOOP l,   0, 1, 0
    NEON_LOOP ml,  1, 1, 0
    NEON_LOOP w,   0, 0, 1
    NEON_LOOP mw,  1, 0, 1
    NEON_LOOP lw,  0, 1, 1
    NEON_LOOP mlw, 1, 1, 1
Lscalar:
    ldrb w11, [x0], #1
    tbz x2, #1, Lchar_done
    cmp w11, #0
    cinc x5, x5, ne
Lchar_done:
    tbz x2, #2, Lline_done
    cmp w11, #10
    cinc x7, x7, eq
Lline_done:
    tbz x2, #3, Lword_done
    cmp w11, #32
    ccmp w11, #9, #4, ne
    ccmp w11, #10, #4, ne
    ccmp w11, #13, #4, ne
    cset x12, eq
    and x13, x9, x12
    add x6, x6, x13
    eor x9, x12, #1
Lword_done:
    subs x1, x1, #1
    b.ne Lscalar
Lstore:
    stp x4, x5, [x3]
    stp x6, x7, [x3, #16]
    stp x8, x9, [x3, #32]
    str x10, [x3, #48]
    ret
