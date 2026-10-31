/* Dynamic check for SysV AMD64 callee-saved GPRs and the caller stack.
   All XMM registers are caller-saved under this ABI. */
.text
.macro CHECK_SAVED register, value
    movabsq $\value, %r10
    cmpq %r10, \register
    jne .Labi_failed
.endm
.p2align 4
.globl kernel_abi_probe
.type kernel_abi_probe,@function
kernel_abi_probe:
    pushq %rbx
    pushq %rbp
    pushq %r12
    pushq %r13
    pushq %r14
    pushq %r15
    subq $24, %rsp
    movq %rsp, 8(%rsp)
    movq $0x12345678, 16(%rsp)
    /* The stack must be 16-byte aligned immediately before a call. */
    testq $15, %rsp
    jnz .Labi_failed
    movabsq $0x1928374655647381, %rbx
    movabsq $0x2938475665748391, %rbp
    movabsq $0x39485766758493a1, %r12
    movabsq $0x495867768594a3b1, %r13
    movabsq $0x5968778695a4b3c1, %r14
    movabsq $0x69788796a5b4c3d1, %r15
    call asmwc_count_buffer
    cmpq %rsp, 8(%rsp)
    jne .Labi_failed
    cmpq $0x12345678, 16(%rsp)
    jne .Labi_failed
    CHECK_SAVED %rbx, 0x1928374655647381
    CHECK_SAVED %rbp, 0x2938475665748391
    CHECK_SAVED %r12, 0x39485766758493a1
    CHECK_SAVED %r13, 0x495867768594a3b1
    CHECK_SAVED %r14, 0x5968778695a4b3c1
    CHECK_SAVED %r15, 0x69788796a5b4c3d1
    xorl %eax, %eax
    jmp .Labi_restore
.Labi_failed:
    movl $1, %eax
.Labi_restore:
    addq $24, %rsp
    popq %r15
    popq %r14
    popq %r13
    popq %r12
    popq %rbp
    popq %rbx
    ret
.size kernel_abi_probe,.-kernel_abi_probe
.section .note.GNU-stack,"",@progbits
