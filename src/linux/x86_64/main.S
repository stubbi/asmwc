/* Linux/glibc x86-64 application logic. libc supplies OS services only.
 * Parsing, traversal policy, counting, aggregation and formatting are assembly.
 * Native libc layout/constants are probed into abi.h by the build.
 */
#include "abi.h"
.intel_syntax noprefix
.text
.p2align 4
.globl main
.type main,@function
main:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov r12d, edi
    mov r13, rsi
    mov edi, 13
    mov esi, 1
    call signal@PLT
    mov edi, r12d
    mov rsi, r13
    call ripwc_parse
    mov rdi, [rip+stdout@GOTPCREL]
    mov rdi, [rdi]
    xor esi, esi
    mov edx, 1
    xor ecx, ecx
    call setvbuf@PLT
    mov r12, [rip+ripwc_paths]
    mov r13, [rip+ripwc_nargs]
    xor ebx, ebx
.Lcollect_args:
    cmp rbx, r13
    jae .Lcollected
    mov rdi, [r12+rbx*8]
    call .Lcollect_path
    inc rbx
    jmp .Lcollect_args
.Lcollected:
    mov r12, [rip+.Ltasks]
    mov r13, [rip+.Ltask_count]
    test r13, r13
    jz .Lmain_done
    cmp r13, 1
    jne .Lparallel
    mov rdi, r12
    call .Lprocess_task
    jmp .Lprocessed
.Lparallel:
    call .Lrun_tasks
.Lprocessed:
    xor ebx, ebx
    xor r14d, r14d
    lea r15, [rip+.Ltotals]
.Lprint_loop:
    cmp rbx, r13
    jae .Lprint_totals
    imul rax, rbx, 96
    lea rax, [r12+rax]
    cmp qword ptr [rax+80], 0
    je .Lprint_next
    inc r14
    mov [rsp], rax
    lea rdi, [rax+16]
    mov rsi, [rax]
    call .Lemit_counts
    mov rax, [rsp]
    mov rcx, [rax+16]
    add [r15], rcx
    mov rcx, [rax+24]
    add [r15+8], rcx
    mov rcx, [rax+32]
    add [r15+16], rcx
    mov rcx, [rax+40]
    add [r15+24], rcx
    mov rcx, [rax+48]
    cmp rcx, [r15+32]
    jbe .Lprint_next
    mov [r15+32], rcx
.Lprint_next:
    inc rbx
    jmp .Lprint_loop
.Lprint_totals:
    cmp r14, 1
    jbe .Lmain_done
    mov edi, 10
    call putchar@PLT
    test eax, eax
    js .Loutput_failed
    mov rdi, r15
    lea rsi, [rip+.Ltotal]
    call .Lemit_counts
.Lmain_done:
    mov rdi, [rip+stdout@GOTPCREL]
    mov rdi, [rdi]
    call fflush@PLT
    test eax, eax
    js .Loutput_failed
    xor eax, eax
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
.size main,.-main

/* fts comparator receives pointers to entry pointers. */
.p2align 4
.Lcompare_entries:
    mov rdi, [rdi]
    mov rsi, [rsi]
    add rdi, ABI_FTS_NAME
    add rsi, ABI_FTS_NAME
    jmp strcmp@PLT

/* Preserve the exact original root spelling. glibc fts removes trailing '/'
 * from roots; child paths are reconstructed from the original root plus the
 * traversal suffix, matching WalkDir's PathBuf::push spelling.
 */
.Lcollect_path:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 40
    mov r12, rdi
    mov [rsp], rdi
    mov qword ptr [rsp+8], 0
    mov qword ptr [rsp+16], -1
    call strlen@PLT
    mov r15, rax
    mov rdi, rsp
    mov esi, ABI_FTS_PHYSICAL | ABI_FTS_NOCHDIR | ABI_FTS_COMFOLLOW
    lea rdx, [rip+.Lcompare_entries]
    call fts_open@PLT
    test rax, rax
    jz .Lcollect_done
    mov r13, rax
.Lfts_next:
    mov rdi, r13
    call fts_read@PLT
    test rax, rax
    jz .Lfts_close
    mov rbx, rax
    cmp qword ptr [rsp+16], -1
    jne .Lfts_info
    mov rdi, [rbx+ABI_FTS_PATH]
    call strlen@PLT
    mov [rsp+16], rax
    mov qword ptr [rsp+24], 1
.Lfts_info:
    movzx eax, word ptr [rbx+ABI_FTS_INFO]
    cmp eax, ABI_FTS_DP
    je .Lfts_next
    cmp eax, ABI_FTS_ERR
    je .Lfts_continue
    cmp eax, ABI_FTS_NS
    je .Lfts_continue
    cmp eax, ABI_FTS_DC
    je .Lfts_continue
    cmp qword ptr [rsp+24], 1
    jne .Lfts_child
    mov rdi, r12
    call .Ladd_task
    jmp .Lfts_continue
.Lfts_child:
    mov r14, [rbx+ABI_FTS_PATH]
    add r14, [rsp+16]
    test r15, r15
    jz .Lfts_suffix_ready
    cmp byte ptr [r12+r15-1], 47
    jne .Lfts_suffix_ready
    cmp byte ptr [r14], 47
    jne .Lfts_suffix_ready
    inc r14
.Lfts_suffix_ready:
    mov rdi, r14
    call strlen@PLT
    lea rdi, [rax+r15+1]
    call malloc@PLT
    test rax, rax
    jz .Lout_of_memory
    mov rbx, rax
    mov rdi, rax
    mov rsi, r12
    mov rdx, r15
    call memcpy@PLT
    lea rdi, [rbx+r15]
    mov rsi, r14
    call strcpy@PLT
    mov rdi, rbx
    call .Ladd_task
    mov rdi, rbx
    call free@PLT
.Lfts_continue:
    mov qword ptr [rsp+24], 0
    cmp qword ptr [rip+ripwc_recursive], 0
    jne .Lfts_next
.Lfts_close:
    mov rdi, r13
    call fts_close@PLT
.Lcollect_done:
    add rsp, 40
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

/* At most min(online CPUs, task count, 32) workers, including the calling
 * thread. Each reserves a distinct task with an atomic fetch-and-add. Only
 * successfully created threads are joined; failures leave their work available
 * to the calling thread. Results are printed in input order after all joins.
 */
.p2align 4
.Lrun_tasks:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 264
    mov qword ptr [rip+.Ltask_next], 0
    xor r12d, r12d
    mov edi, ABI_SC_NPROCESSORS_ONLN
    call sysconf@PLT
    mov r13d, 1
    cmp rax, 1
    cmovg r13, rax
    mov eax, 32
    cmp r13, rax
    cmova r13, rax
    mov rax, [rip+.Ltask_count]
    cmp r13, rax
    cmova r13, rax
    dec r13
    xor r14d, r14d
.Lcreate_worker:
    cmp r14, r13
    jae .Lmain_worker
    lea rdi, [rsp+r12*8]
    xor esi, esi
    lea rdx, [rip+.Ltask_worker]
    xor ecx, ecx
    call pthread_create@PLT
    test eax, eax
    jne .Lcreated_next
    inc r12
.Lcreated_next:
    inc r14
    jmp .Lcreate_worker
.Lmain_worker:
    xor edi, edi
    call .Ltask_worker
    xor r14d, r14d
.Ljoin_worker:
    cmp r14, r12
    jae .Ljoined
    mov rdi, [rsp+r14*8]
    xor esi, esi
    call pthread_join@PLT
    inc r14
    jmp .Ljoin_worker
.Ljoined:
    add rsp, 264
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

.p2align 4
.Ltask_worker:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    sub rsp, 8
    mov r12, [rip+.Ltask_count]
    mov r13, [rip+.Ltasks]
.Lworker_next:
    mov eax, 1
    lock xadd qword ptr [rip+.Ltask_next], rax
    cmp rax, r12
    jae .Lworker_done
    imul rdi, rax, 96
    add rdi, r13
    call .Lprocess_task
    jmp .Lworker_next
.Lworker_done:
    xor eax, eax
    add rsp, 8
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

/* Task stride 96: path@0, metadata size@8, count state@16, success@80,
 * metadata-present@88. All entries are collected before files are processed.
 */
.Ladd_task:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, ((ABI_STAT_SIZE + 15) & -16) + 8
    mov r12, rdi
    mov r13, [rip+.Ltask_count]
    mov r14, [rip+.Ltask_capacity]
    cmp r13, r14
    jb .Lcapacity_ok
    add r14, r14
    mov eax, 64
    cmp r14, rax
    cmovb r14, rax
    imul rsi, r14, 96
    mov rdi, [rip+.Ltasks]
    call realloc@PLT
    test rax, rax
    jz .Lout_of_memory
    mov [rip+.Ltasks], rax
    mov [rip+.Ltask_capacity], r14
.Lcapacity_ok:
    imul rbx, r13, 96
    add rbx, [rip+.Ltasks]
    pxor xmm0, xmm0
    movdqu [rbx], xmm0
    movdqu [rbx+16], xmm0
    movdqu [rbx+32], xmm0
    movdqu [rbx+48], xmm0
    movdqu [rbx+64], xmm0
    movdqu [rbx+80], xmm0
    mov rdi, r12
    call strdup@PLT
    test rax, rax
    jz .Lout_of_memory
    mov [rbx], rax
    mov rdi, r12
    mov rsi, rsp
    call stat@PLT
    test eax, eax
    jne .Ltask_added
    mov rax, [rsp+ABI_STAT_ST_SIZE]
    mov [rbx+8], rax
    mov qword ptr [rbx+88], 1
.Ltask_added:
    inc r13
    mov [rip+.Ltask_count], r13
    add rsp, ((ABI_STAT_SIZE + 15) & -16) + 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
.Lout_of_memory:
    mov edi, 1
    call exit@PLT

.Lprocess_task:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 24
    mov r12, rdi
    mov r13, [rip+ripwc_flags]
    mov r14, [r12+8]
    cmp qword ptr [r12+88], 0
    je .Lmaybe_verbose
    cmp r14, 524288
    jb .Lopen_file
.Lmaybe_verbose:
    cmp qword ptr [rip+ripwc_verbose], 0
    je .Lopen_file
    mov rdi, [r12]
    call ripwc_lossy
    mov [rsp], rax
    mov rdx, rax
    mov rdi, [rip+stderr@GOTPCREL]
    mov rdi, [rdi]
    lea rsi, [rip+.Lprocessing]
    xor eax, eax
    call fprintf@PLT
    mov ebx, eax
    mov rdi, [rsp]
    call free@PLT
    test ebx, ebx
    js .Lprocess_done
.Lopen_file:
    mov rdi, [r12]
    xor esi, esi
    xor eax, eax
    call open@PLT
    test eax, eax
    js .Lopen_failed
    mov ebx, eax
    cmp r13, 1
    jne .Lscan_file
    cmp qword ptr [r12+88], 0
    je .Lscan_file
    mov [r12+16], r14
    jmp .Lclose_success
.Lopen_failed:
    call __errno_location@PLT
    cmp dword ptr [rax], ABI_EINTR
    je .Lopen_file
    jmp .Lprocess_done
.Lscan_file:
    mov edi, 1048576
    call malloc@PLT
    test rax, rax
    jz .Lclose_failed
    mov r15, rax
.Lread_next:
    mov edi, ebx
    mov rsi, r15
    mov edx, 1048576
    call read@PLT
    test rax, rax
    js .Lread_error
    jz .Leof
    mov rsi, rax
    mov rdi, r15
    mov rdx, r13
    lea rcx, [r12+16]
    call ripwc_count_buffer
    jmp .Lread_next
.Leof:
    mov rdi, r15
    call free@PLT
    test r13b, 8
    jz .Lfinalize_max
    mov rax, [r12+56]
    add [r12+32], rax
.Lfinalize_max:
    test r13b, 16
    jz .Lfallback_bytes
    mov rax, [r12+64]
    cmp rax, [r12+48]
    jbe .Lfallback_bytes
    mov [r12+48], rax
.Lfallback_bytes:
    test r13b, 1
    jz .Lclose_success
    cmp qword ptr [r12+16], 0
    jne .Lclose_success
    cmp qword ptr [r12+88], 0
    je .Lclose_success
    mov [r12+16], r14
.Lclose_success:
    mov qword ptr [r12+80], 1
    mov edi, ebx
    call close@PLT
    jmp .Lprocess_done
.Lread_error:
    call __errno_location@PLT
    cmp dword ptr [rax], ABI_EINTR
    je .Lread_next
    mov rdi, r15
    call free@PLT
.Lclose_failed:
    mov edi, ebx
    call close@PLT
.Lprocess_done:
    add rsp, 24
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

.macro EMIT_FIELD mask, off, label
    test r14b, \mask
    jz 9f
    mov rsi, [r12+\off]
    test rsi, rsi
    jz 9f
    lea rdi, [rip+\label]
    add rdi, r15
    xor eax, eax
    call printf@PLT
    test eax, eax
    js .Loutput_failed
    xor r15d, r15d
9:
.endm
.Lemit_counts:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov r12, rdi
    mov r13, rsi
    mov r15d, 1
    mov r14, [rip+ripwc_flags]
    EMIT_FIELD 4, 24, .Llines
    EMIT_FIELD 8, 16, .Lwords
    EMIT_FIELD 2, 8, .Lchars
    EMIT_FIELD 1, 0, .Lbytes
    EMIT_FIELD 16, 32, .Lmax
    mov rdi, r13
    call ripwc_lossy
    mov rbx, rax
    mov rsi, rax
    lea rdi, [rip+.Lpath_format]
    xor eax, eax
    call printf@PLT
    test eax, eax
    js .Loutput_failed
    mov rdi, rbx
    call free@PLT
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

/* Match Rust's io::Error debug representation for failed counted output. */
.Loutput_failed:
    /* All callers reach this label with rsp aligned for calls. */
    call __errno_location@PLT
    mov ebx, [rax]
    lea r12, [rip+.Lkind_other]
    lea r13, [rip+.Lerror_kinds]
.Lerror_kind_next:
    mov rax, [r13]
    test rax, rax
    jz .Lerror_kind_found
    cmp eax, ebx
    je .Lerror_kind_match
    add r13, 16
    jmp .Lerror_kind_next
.Lerror_kind_match:
    lea r12, [rip+.Lkind_base]
    add r12, [r13+8]
.Lerror_kind_found:
    mov edi, ebx
    call strerror@PLT
    mov r8, rax
    mov rcx, r12
    mov edx, ebx
    lea rsi, [rip+.Loutput_error]
    mov rdi, [rip+stderr@GOTPCREL]
    mov rdi, [rdi]
    xor eax, eax
    call fprintf@PLT
    mov edi, 1
    call exit@PLT

.section .rodata
.Llines: .asciz " lines: %llu"
.Lwords: .asciz " words: %llu"
.Lchars: .asciz " chars: %llu"
.Lbytes: .asciz " bytes: %llu"
.Lmax: .asciz " max line length: %llu"
.Lpath_format: .asciz " %s\n"
.Lprocessing: .asciz "Processing: %s\n"
.Ltotal: .asciz "total"
.Loutput_error: .asciz "Error: Os { code: %d, kind: %s, message: \"%s\" }\n"
.Lkind_base:
.Lkind_other: .asciz "Uncategorized"
.Lkind_pipe: .asciz "BrokenPipe"
.Lkind_full: .asciz "StorageFull"
.Lkind_invalid: .asciz "InvalidInput"
.Lkind_permission: .asciz "PermissionDenied"
.Lkind_directory: .asciz "IsADirectory"
.Lkind_large: .asciz "FileTooLarge"
.Lkind_again: .asciz "WouldBlock"
.Lkind_interrupted: .asciz "Interrupted"
.Lkind_memory: .asciz "OutOfMemory"
.p2align 3
.Lerror_kinds:
    .quad ABI_EPIPE, .Lkind_pipe-.Lkind_base
    .quad ABI_ENOSPC, .Lkind_full-.Lkind_base
    .quad ABI_EINVAL, .Lkind_invalid-.Lkind_base
    .quad ABI_EACCES, .Lkind_permission-.Lkind_base
    .quad ABI_EISDIR, .Lkind_directory-.Lkind_base
    .quad ABI_EFBIG, .Lkind_large-.Lkind_base
    .quad ABI_EAGAIN, .Lkind_again-.Lkind_base
    .quad ABI_EINTR, .Lkind_interrupted-.Lkind_base
    .quad ABI_ENOMEM, .Lkind_memory-.Lkind_base
    .quad 0, 0
.bss
.p2align 4
.Ltasks: .zero 8
.Ltask_count: .zero 8
.Ltask_next: .zero 8
.Ltask_capacity: .zero 8
.Ltotals: .zero 64
.section .note.GNU-stack,"",@progbits
