/* Dynamic check for the AAPCS64 callee-saved GPR and SIMD subset. */
#if defined(__APPLE__)
#define ABI_PROBE _kernel_abi_probe
#define COUNT_BUFFER _ripwc_count_buffer
#else
#define ABI_PROBE kernel_abi_probe
#define COUNT_BUFFER ripwc_count_buffer
#endif
.text
.p2align 4
.globl ABI_PROBE
ABI_PROBE:
    sub sp, sp, #160
    stp x19, x20, [sp]
    stp x21, x22, [sp, #16]
    stp x23, x24, [sp, #32]
    stp x25, x26, [sp, #48]
    stp x27, x28, [sp, #64]
    stp x29, x30, [sp, #80]
    stp d8, d9, [sp, #96]
    stp d10, d11, [sp, #112]
    stp d12, d13, [sp, #128]
    stp d14, d15, [sp, #144]
    mov x19, #119
    mov x20, #120
    mov x21, #121
    mov x22, #122
    mov x23, #123
    mov x24, #124
    mov x25, #125
    mov x26, #126
    mov x27, #127
    mov x28, #128
    mov x29, #129
    mov x16, #208
    fmov d8, x16
    mov x16, #209
    fmov d9, x16
    mov x16, #210
    fmov d10, x16
    mov x16, #211
    fmov d11, x16
    mov x16, #212
    fmov d12, x16
    mov x16, #213
    fmov d13, x16
    mov x16, #214
    fmov d14, x16
    mov x16, #215
    fmov d15, x16
    bl COUNT_BUFFER
    cmp x19, #119
    b.ne Labi_failed
    cmp x20, #120
    b.ne Labi_failed
    cmp x21, #121
    b.ne Labi_failed
    cmp x22, #122
    b.ne Labi_failed
    cmp x23, #123
    b.ne Labi_failed
    cmp x24, #124
    b.ne Labi_failed
    cmp x25, #125
    b.ne Labi_failed
    cmp x26, #126
    b.ne Labi_failed
    cmp x27, #127
    b.ne Labi_failed
    cmp x28, #128
    b.ne Labi_failed
    cmp x29, #129
    b.ne Labi_failed
    fmov x16, d8
    cmp x16, #208
    b.ne Labi_failed
    fmov x16, d9
    cmp x16, #209
    b.ne Labi_failed
    fmov x16, d10
    cmp x16, #210
    b.ne Labi_failed
    fmov x16, d11
    cmp x16, #211
    b.ne Labi_failed
    fmov x16, d12
    cmp x16, #212
    b.ne Labi_failed
    fmov x16, d13
    cmp x16, #213
    b.ne Labi_failed
    fmov x16, d14
    cmp x16, #214
    b.ne Labi_failed
    fmov x16, d15
    cmp x16, #215
    b.ne Labi_failed
    mov x0, #0
    b Labi_restore
Labi_failed:
    mov x0, #1
Labi_restore:
    ldp x19, x20, [sp]
    ldp x21, x22, [sp, #16]
    ldp x23, x24, [sp, #32]
    ldp x25, x26, [sp, #48]
    ldp x27, x28, [sp, #64]
    ldp x29, x30, [sp, #80]
    ldp d8, d9, [sp, #96]
    ldp d10, d11, [sp, #112]
    ldp d12, d13, [sp, #128]
    ldp d14, d15, [sp, #144]
    add sp, sp, #160
    ret
#if !defined(__APPLE__)
.section .note.GNU-stack,"",%progbits
#endif
