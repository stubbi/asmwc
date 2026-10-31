/* System V AMD64: rdi=data, rsi=len, rdx=flags, rcx=64-byte state.
 * State: bytes, non-NUL chars, ended words, LF, max, inword, current, reserved.
 * SSE2 is part of the x86-64 baseline. No POPCNT, AVX or unbounded loads.
 * The caller finalizes the pending word and final line exactly once at EOF.
 */
.intel_syntax noprefix
.text

/* Population count of the low sixteen bits without a CPU feature extension. */
.macro POP16
    mov edx, eax
    shr edx, 1
    and edx, 0x5555
    sub eax, edx
    mov edx, eax
    shr edx, 2
    and eax, 0x3333
    and edx, 0x3333
    add eax, edx
    mov edx, eax
    shr edx, 4
    add eax, edx
    and eax, 0x0f0f
    mov edx, eax
    shr edx, 8
    add eax, edx
    and eax, 31
.endm

.p2align 4
.globl ripwc_count_buffer
.type ripwc_count_buffer,@function
ripwc_count_buffer:
    push rbp
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rbp, rcx
    mov r15, rdx
    mov r9, [rcx+8]
    mov r10, [rcx+16]
    mov r11, [rcx+24]
    mov r12, [rcx+32]
    mov r13, [rcx+40]
    mov r14, [rcx+48]
    test r15b, 1
    jz .Lbytes_done
    add [rbp], rsi
.Lbytes_done:
    test rsi, rsi
    jz .Lstore
    test r15b, 30
    jz .Lstore
    cmp rsi, 16
    jb .Lscalar
    pxor xmm7, xmm7
    movdqa xmm6, [rip+.Llf]
.Lvector:
    movdqu xmm0, [rdi]
    test r15b, 2
    jz .Lvector_chars_done
    movdqa xmm1, xmm0
    pcmpeqb xmm1, xmm7
    pmovmskb eax, xmm1
    POP16
    add r9, 16
    sub r9, rax
.Lvector_chars_done:
    test r15b, 20
    jz .Lvector_lf_done
    movdqa xmm1, xmm0
    pcmpeqb xmm1, xmm6
    pmovmskb ebx, xmm1
    test r15b, 4
    jz .Lvector_lines_done
    mov eax, ebx
    POP16
    add r11, rax
.Lvector_lines_done:
    test r15b, 16
    jz .Lvector_lf_done
    xor ecx, ecx
    test ebx, ebx
    jz .Lmax_remainder
.Lmax_lf:
    bsf eax, ebx
    mov edx, eax
    sub edx, ecx
    add r14, rdx
    cmp r14, r12
    cmova r12, r14
    xor r14d, r14d
    lea ecx, [eax+1]
    lea edx, [ebx-1]
    and ebx, edx
    jnz .Lmax_lf
.Lmax_remainder:
    mov eax, 16
    sub eax, ecx
    add r14, rax
.Lvector_lf_done:
    test r15b, 8
    jz .Lvector_words_done
    movdqa xmm1, xmm0
    movdqa xmm2, xmm0
    pcmpeqb xmm1, [rip+.Ltab]
    pcmpeqb xmm2, xmm6
    por xmm1, xmm2
    movdqa xmm2, xmm0
    pcmpeqb xmm2, [rip+.Lcr]
    por xmm1, xmm2
    movdqa xmm2, xmm0
    pcmpeqb xmm2, [rip+.Lspace]
    por xmm1, xmm2
    pmovmskb ebx, xmm1
    mov eax, ebx
    shl eax, 1
    mov edx, 1
    sub edx, r13d
    or eax, edx
    not eax
    and eax, ebx
    shr ebx, 15
    xor ebx, 1
    mov r13d, ebx
    POP16
    add r10, rax
.Lvector_words_done:
    add rdi, 16
    sub rsi, 16
    cmp rsi, 16
    jae .Lvector
    test rsi, rsi
    jz .Lstore
.Lscalar:
    movzx eax, byte ptr [rdi]
    inc rdi
    test r15b, 2
    jz .Lscalar_chars_done
    test eax, eax
    jz .Lscalar_chars_done
    inc r9
.Lscalar_chars_done:
    test r15b, 4
    jz .Lscalar_lines_done
    cmp eax, 10
    jne .Lscalar_lines_done
    inc r11
.Lscalar_lines_done:
    test r15b, 8
    jz .Lscalar_words_done
    cmp eax, 32
    je .Lscalar_separator
    cmp eax, 9
    je .Lscalar_separator
    cmp eax, 10
    je .Lscalar_separator
    cmp eax, 13
    je .Lscalar_separator
    mov r13d, 1
    jmp .Lscalar_words_done
.Lscalar_separator:
    add r10, r13
    xor r13d, r13d
.Lscalar_words_done:
    test r15b, 16
    jz .Lscalar_max_done
    cmp eax, 10
    jne .Lscalar_max_increment
    cmp r14, r12
    cmova r12, r14
    xor r14d, r14d
    jmp .Lscalar_max_done
.Lscalar_max_increment:
    inc r14
.Lscalar_max_done:
    dec rsi
    jnz .Lscalar
.Lstore:
    mov [rbp+8], r9
    mov [rbp+16], r10
    mov [rbp+24], r11
    mov [rbp+32], r12
    mov [rbp+40], r13
    mov [rbp+48], r14
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
.size ripwc_count_buffer,.-ripwc_count_buffer
.section .rodata
.p2align 4
.Llf: .fill 16,1,10
.Ltab: .fill 16,1,9
.Lcr: .fill 16,1,13
.Lspace: .fill 16,1,32
.section .note.GNU-stack,"",@progbits
