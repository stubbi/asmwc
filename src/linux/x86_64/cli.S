// Linux x86-64 SysV parser. Diagnostics deliberately follow pinned clap.
.intel_syntax noprefix
.text
.equ P_ARGC, -48
.equ P_ARGV, -56
.equ P_INDEX, -64
.equ P_CUR, -72
.equ P_FLAGS, -80
.equ P_PATHS, -88
.equ P_NARGS, -96
.equ P_TMP, -104
.equ P_OPT, -112
.equ P_MODE, -120
.equ P_BASE, -128
.equ P_END, -136
.p2align 4
.globl ripwc_parse
.type ripwc_parse,@function
ripwc_parse:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 136
    movsxd rax, edi
    mov [rbp+P_ARGC], rax
    mov [rbp+P_ARGV], rsi
    mov qword ptr [rbp+P_FLAGS], 0
    mov qword ptr [rbp+P_NARGS], 0
    mov qword ptr [rbp+P_MODE], 0
    mov qword ptr [rip+.L_order_count], 0
    mov rax, [rip+stderr@GOTPCREL]
    mov rax, [rax]
    mov [rip+.L_stream], rax
    lea rax, [rip+.L_default_name]
    cmp qword ptr [rbp+P_ARGC], 0
    je .L_name_ready
    mov rsi, [rbp+P_ARGV]
    mov rdi, [rsi]
    test rdi, rdi
    je .L_name_ready
    cmp byte ptr [rdi], 0
    je .L_name_ready
    call strdup@PLT
    test rax, rax
    je .L_oom
    mov [rbp+P_BASE], rax
    mov rdi, rax
    call strlen@PLT
    add rax, [rbp+P_BASE]
    mov [rbp+P_END], rax
.L_name_trim:
    mov rax, [rbp+P_END]
    cmp rax, [rbp+P_BASE]
    je .L_name_default
    cmp byte ptr [rax-1], 47
    jne .L_name_component
    dec qword ptr [rbp+P_END]
    jmp .L_name_trim
.L_name_component:
    mov rdx, rax
.L_name_component_start:
    cmp rdx, [rbp+P_BASE]
    je .L_name_component_found
    cmp byte ptr [rdx-1], 47
    je .L_name_component_found
    dec rdx
    jmp .L_name_component_start
.L_name_component_found:
    sub rax, rdx
    cmp rax, 1
    jne .L_name_check_parent
    cmp byte ptr [rdx], 46
    jne .L_name_finish
    mov [rbp+P_END], rdx
    jmp .L_name_trim
.L_name_check_parent:
    cmp rax, 2
    jne .L_name_finish
    cmp word ptr [rdx], 11822
    je .L_name_default
.L_name_finish:
    mov rax, [rbp+P_END]
    mov byte ptr [rax], 0
    mov [rbp+P_TMP], rdx
    mov rdi, rdx
    call .L_check_utf8
    test eax, eax
    je .L_name_default
    mov rax, [rbp+P_TMP]
    jmp .L_name_ready
.L_name_default:
    lea rax, [rip+.L_default_name]
.L_name_ready:
    mov [rip+.L_name], rax
    mov rdi, [rbp+P_ARGC]
    lea rdi, [rdi*8+8]
    call malloc@PLT
    test rax, rax
    je .L_oom
    mov [rbp+P_PATHS], rax
    mov qword ptr [rbp+P_INDEX], 1
.L_next:
    mov rcx, [rbp+P_INDEX]
    cmp rcx, [rbp+P_ARGC]
    jge .L_done
    mov rax, [rbp+P_ARGV]
    mov rax, [rax+rcx*8]
    inc qword ptr [rbp+P_INDEX]
    mov [rbp+P_CUR], rax
    cmp byte ptr [rax], 45
    jne .L_path
    movzx edx, byte ptr [rax+1]
    test edx, edx
    je .L_path
    cmp edx, 45
    je .L_long
    inc qword ptr [rbp+P_CUR]
.L_short:
    mov rax, [rbp+P_CUR]
    movzx edx, byte ptr [rax]
    inc qword ptr [rbp+P_CUR]
    test edx, edx
    je .L_next
    lea rsi, [rip+.L_short_chars]
    xor ecx, ecx
.L_short_find:
    cmp byte ptr [rsi+rcx], dl
    je .L_short_found
    inc rcx
    cmp rcx, 9
    jl .L_short_find
    dec qword ptr [rbp+P_CUR]
    mov rdi, [rbp+P_CUR]
    call .L_check_utf8
    mov [rbp+P_TMP], rax
    mov rdi, [rbp+P_CUR]
    call ripwc_lossy
    cmp qword ptr [rbp+P_TMP], 0
    je .L_short_invalid_tail
    lea rdx, [rip+.L_short_bad]
    mov ecx, 1
    movzx esi, byte ptr [rax]
    inc rax
    mov [rdx+rcx], sil
    inc rcx
.L_short_scalar:
    movzx esi, byte ptr [rax]
    mov edi, esi
    and edi, 192
    cmp edi, 128
    jne .L_short_scalar_end
    mov [rdx+rcx], sil
    inc rax
    inc rcx
    jmp .L_short_scalar
.L_short_scalar_end:
    mov byte ptr [rdx+rcx], 0
    mov [rbp+P_CUR], rdx
    mov qword ptr [rbp+P_MODE], 1
    jmp .L_unknown
.L_short_invalid_tail:
    mov [rbp+P_CUR], rax
    mov rdi, rax
    call strlen@PLT
    lea rdi, [rax+2]
    call malloc@PLT
    test rax, rax
    je .L_oom
    mov rdx, rax
    mov byte ptr [rdx], 45
    inc rdx
    mov rsi, [rbp+P_CUR]
.L_short_invalid_copy:
    movzx ecx, byte ptr [rsi]
    inc rsi
    mov [rdx], cl
    inc rdx
    test ecx, ecx
    jne .L_short_invalid_copy
    mov [rbp+P_CUR], rax
    mov qword ptr [rbp+P_MODE], 1
    jmp .L_unknown
.L_short_found:
    mov [rbp+P_OPT], rcx
    call .L_validate_paths
    cmp qword ptr [rbp+P_OPT], 7
    je .L_help
    cmp qword ptr [rbp+P_OPT], 8
    je .L_version
    call .L_record
    jmp .L_short
.L_long:
    cmp byte ptr [rax+2], 0
    jne .L_long_option
    call .L_validate_paths
.L_after_separator:
    mov rcx, [rbp+P_INDEX]
    cmp rcx, [rbp+P_ARGC]
    jge .L_done
    mov rax, [rbp+P_ARGV]
    mov rax, [rax+rcx*8]
    inc qword ptr [rbp+P_INDEX]
    mov rdx, [rbp+P_PATHS]
    mov rcx, [rbp+P_NARGS]
    mov [rdx+rcx*8], rax
    inc qword ptr [rbp+P_NARGS]
    jmp .L_after_separator
.L_long_option:
    mov rdi, [rbp+P_CUR]
    call ripwc_lossy
    mov [rbp+P_CUR], rax
    mov qword ptr [rbp+P_TMP], 0
.L_equal_scan:
    movzx edx, byte ptr [rax]
    test edx, edx
    je .L_long_find_start
    cmp edx, 61
    je .L_equal
    inc rax
    jmp .L_equal_scan
.L_equal:
    mov byte ptr [rax], 0
    inc rax
    mov [rbp+P_TMP], rax
.L_long_find_start:
    mov qword ptr [rbp+P_OPT], 0
.L_long_find:
    call .L_option_ptr
    mov rsi, rdi
    mov rdi, [rbp+P_CUR]
    call strcmp@PLT
    test eax, eax
    je .L_long_found
    inc qword ptr [rbp+P_OPT]
    cmp qword ptr [rbp+P_OPT], 9
    jl .L_long_find
    mov qword ptr [rbp+P_MODE], 0
    jmp .L_unknown
.L_long_found:
    cmp qword ptr [rbp+P_TMP], 0
    jne .L_unexpected_value
    call .L_validate_paths
    cmp qword ptr [rbp+P_OPT], 7
    je .L_help
    cmp qword ptr [rbp+P_OPT], 8
    je .L_version
    call .L_record
    jmp .L_next
.L_path:
    mov rdx, [rbp+P_PATHS]
    mov rcx, [rbp+P_NARGS]
    mov rax, [rbp+P_CUR]
    mov [rdx+rcx*8], rax
    inc qword ptr [rbp+P_NARGS]
    jmp .L_next
.L_done:
    call .L_validate_paths
    mov rcx, [rbp+P_NARGS]
    test rcx, rcx
    je .L_missing
    mov rdx, [rbp+P_PATHS]
    mov qword ptr [rdx+rcx*8], 0
    mov rax, [rbp+P_FLAGS]
    and eax, 31
    mov esi, 13
    test rax, rax
    cmovz rax, rsi
    mov [rip+ripwc_flags], rax
    mov rax, [rbp+P_FLAGS]
    shr rax, 5
    and eax, 1
    mov [rip+ripwc_recursive], rax
    mov rax, [rbp+P_FLAGS]
    shr rax, 6
    and eax, 1
    mov [rip+ripwc_verbose], rax
    mov [rip+ripwc_nargs], rcx
    mov [rip+ripwc_paths], rdx
    add rsp, 136
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
.size ripwc_parse,.-ripwc_parse

// Private parser helpers use rbp's parser frame and ordinary SysV arguments.
.L_record:
    mov rcx, [rbp+P_OPT]
    mov eax, 1
    shl rax, cl
    test [rbp+P_FLAGS], rax
    jne .L_record_duplicate
    or [rbp+P_FLAGS], rax
.L_record_usage:
    mov rcx, [rip+.L_order_count]
    lea rdx, [rip+.L_order]
    mov rax, [rbp+P_OPT]
    mov [rdx+rcx*8], rax
    inc qword ptr [rip+.L_order_count]
    ret
.L_record_duplicate:
    add rsp, 8
    jmp .L_duplicate
.L_option_ptr:
    mov rax, [rbp+P_OPT]
    lea rdi, [rip+.L_options]
    mov rdi, [rdi+rax*8]
    ret
.L_emit:
    mov rsi, [rip+.L_stream]
    jmp fputs@PLT
.L_help:
    mov rax, [rip+stdout@GOTPCREL]
    mov rax, [rax]
    mov [rip+.L_stream], rax
    lea rdi, [rip+.L_help_intro]
    call .L_emit
    mov rdi, [rip+.L_name]
    call .L_emit
    lea rdi, [rip+.L_help_rest]
    call .L_emit
    xor edi, edi
    call exit@PLT
.L_version:
    mov rax, [rip+stdout@GOTPCREL]
    mov rax, [rax]
    mov [rip+.L_stream], rax
    lea rdi, [rip+.L_version_text]
    call .L_emit
    xor edi, edi
    call exit@PLT
.L_missing:
    lea rdi, [rip+.L_missing_text]
    call .L_emit
    mov qword ptr [rbp+P_MODE], 0
    jmp .L_error_usage
.L_duplicate:
    lea rdi, [rip+.L_duplicate_intro]
    call .L_emit
    call .L_option_ptr
    call .L_emit
    lea rdi, [rip+.L_duplicate_rest]
    call .L_emit
    mov qword ptr [rbp+P_MODE], 1
    jmp .L_error_usage
.L_unexpected_value:
    lea rdi, [rip+.L_value_intro]
    call .L_emit
    mov rdi, [rbp+P_TMP]
    call .L_emit
    lea rdi, [rip+.L_value_middle]
    call .L_emit
    call .L_option_ptr
    call .L_emit
    lea rdi, [rip+.L_value_rest]
    call .L_emit
    cmp qword ptr [rbp+P_FLAGS], 0
    jne .L_value_group
    call .L_record_usage
    mov qword ptr [rbp+P_MODE], 0
    jmp .L_error_usage
.L_value_group:
    mov qword ptr [rbp+P_MODE], 2
    jmp .L_error_usage
.L_unknown:
    lea rdi, [rip+.L_unknown_intro]
    call .L_emit
    mov rdi, [rbp+P_CUR]
    call .L_emit
    lea rdi, [rip+.L_unknown_rest]
    call .L_emit
    cmp qword ptr [rbp+P_MODE], 0
    jne .L_unknown_no_hint
    mov rdi, [rbp+P_CUR]
    add rdi, 2
    call .L_suggest
    test rax, rax
    js .L_unknown_no_hint
    mov [rbp+P_OPT], rax
    lea rdi, [rip+.L_hint_intro]
    call .L_emit
    call .L_option_ptr
    call .L_emit
    lea rdi, [rip+.L_hint_end]
    call .L_emit
    mov rcx, [rbp+P_OPT]
    mov eax, 1
    shl rax, cl
    test [rbp+P_FLAGS], rax
    jne .L_hint_usage
    call .L_record_usage
.L_hint_usage:
    mov qword ptr [rbp+P_MODE], 0
    jmp .L_error_usage
.L_unknown_no_hint:
    lea rdi, [rip+.L_pass_intro]
    call .L_emit
    mov rdi, [rbp+P_CUR]
    call .L_emit
    lea rdi, [rip+.L_pass_middle]
    call .L_emit
    mov rdi, [rbp+P_CUR]
    call .L_emit
    lea rdi, [rip+.L_hint_end]
    call .L_emit
    cmp qword ptr [rbp+P_MODE], 0
    jne .L_error_usage
    cmp qword ptr [rbp+P_FLAGS], 0
    jne .L_error_usage
    cmp qword ptr [rbp+P_NARGS], 0
    jne .L_error_usage
    mov qword ptr [rbp+P_MODE], 1
.L_error_usage:
    lea rdi, [rip+.L_usage_intro]
    call .L_emit
    mov rdi, [rip+.L_name]
    call .L_emit
    cmp qword ptr [rbp+P_MODE], 1
    je .L_usage_generic
    cmp qword ptr [rbp+P_MODE], 2
    je .L_usage_group
    mov qword ptr [rbp+P_TMP], 0
.L_usage_loop:
    mov rax, [rbp+P_TMP]
    cmp rax, [rip+.L_order_count]
    jge .L_usage_file
    lea rdx, [rip+.L_order]
    mov rax, [rdx+rax*8]
    mov [rbp+P_OPT], rax
    lea rdi, [rip+.L_space]
    call .L_emit
    call .L_option_ptr
    call .L_emit
    inc qword ptr [rbp+P_TMP]
    jmp .L_usage_loop
.L_usage_generic:
    lea rdi, [rip+.L_generic]
    call .L_emit
.L_usage_file:
    lea rdi, [rip+.L_file]
    call .L_emit
    jmp .L_error_end
.L_usage_group:
    cmp qword ptr [rbp+P_OPT], 7
    jl .L_group_only
    lea rdi, [rip+.L_space]
    call .L_emit
    call .L_option_ptr
    call .L_emit
.L_group_only:
    lea rdi, [rip+.L_group]
    call .L_emit
.L_error_end:
    lea rdi, [rip+.L_error_tail]
    call .L_emit
    mov edi, 2
    call exit@PLT
.L_oom:
    mov edi, 1
    call exit@PLT

// Validate pending positional arguments at the same point clap resolves them.
.L_validate_paths:
    sub rsp, 8
.L_validate_next:
    mov rcx, [rbp+P_MODE]
    cmp rcx, [rbp+P_NARGS]
    jge .L_validate_done
    mov rax, [rbp+P_PATHS]
    mov rdi, [rax+rcx*8]
    call .L_check_utf8
    test eax, eax
    je .L_utf8_error_emit
    inc qword ptr [rbp+P_MODE]
    jmp .L_validate_next
.L_validate_done:
    add rsp, 8
    ret
.L_utf8_error_emit:
    add rsp, 16
    lea rdi, [rip+.L_utf8_error]
    call .L_emit
    mov qword ptr [rbp+P_MODE], 1
    jmp .L_error_usage

// rdi=zero-terminated string, eax=valid UTF-8. Leaf, volatile registers only.
.L_check_utf8:
    mov rdx, rdi
.L_utf8_next:
    movzx eax, byte ptr [rdx]
    inc rdx
    test eax, eax
    je .L_utf8_ok
    cmp eax, 128
    jb .L_utf8_next
    cmp eax, 194
    jb .L_utf8_bad
    cmp eax, 224
    jb .L_utf8_two
    cmp eax, 240
    jb .L_utf8_three
    cmp eax, 245
    jae .L_utf8_bad
    movzx ecx, byte ptr [rdx]
    inc rdx
    cmp ecx, 128
    jb .L_utf8_bad
    cmp ecx, 192
    jae .L_utf8_bad
    cmp eax, 240
    jne .L_utf8_not_f0
    cmp ecx, 144
    jb .L_utf8_bad
.L_utf8_not_f0:
    cmp eax, 244
    jne .L_utf8_more_two
    cmp ecx, 144
    jae .L_utf8_bad
    jmp .L_utf8_more_two
.L_utf8_three:
    movzx ecx, byte ptr [rdx]
    inc rdx
    cmp ecx, 128
    jb .L_utf8_bad
    cmp ecx, 192
    jae .L_utf8_bad
    cmp eax, 224
    jne .L_utf8_not_e0
    cmp ecx, 160
    jb .L_utf8_bad
.L_utf8_not_e0:
    cmp eax, 237
    jne .L_utf8_two
    cmp ecx, 160
    jae .L_utf8_bad
    jmp .L_utf8_two
.L_utf8_more_two:
    movzx ecx, byte ptr [rdx]
    inc rdx
    sub ecx, 128
    cmp ecx, 64
    jae .L_utf8_bad
.L_utf8_two:
    movzx ecx, byte ptr [rdx]
    inc rdx
    sub ecx, 128
    cmp ecx, 64
    jb .L_utf8_next
.L_utf8_bad:
    xor eax, eax
    ret
.L_utf8_ok:
    mov eax, 1
    ret

// Rust to_string_lossy: replace each maximal malformed prefix with U+FFFD.
.p2align 4
.globl ripwc_lossy
.type ripwc_lossy,@function
ripwc_lossy:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov rbx, rdi
    call strlen@PLT
    lea rdi, [rax+rax*2+3]
    call malloc@PLT
    test rax, rax
    je .L_lossy_oom
    mov r12, rax
    mov r13, rax
.L_lossy_next:
    movzx eax, byte ptr [rbx]
    test eax, eax
    je .L_lossy_done
    mov r14d, 1
    cmp eax, 128
    jb .L_lossy_copy
    cmp eax, 194
    jb .L_lossy_replace
    cmp eax, 245
    jae .L_lossy_replace
    movzx edx, byte ptr [rbx+1]
    cmp edx, 128
    jb .L_lossy_replace
    cmp edx, 192
    jae .L_lossy_replace
    cmp eax, 224
    jb .L_lossy_valid_two
    cmp eax, 224
    jne .L_lossy_not_e0
    cmp edx, 160
    jb .L_lossy_replace
.L_lossy_not_e0:
    cmp eax, 237
    jne .L_lossy_not_ed
    cmp edx, 160
    jae .L_lossy_replace
.L_lossy_not_ed:
    cmp eax, 240
    jne .L_lossy_not_f0
    cmp edx, 144
    jb .L_lossy_replace
.L_lossy_not_f0:
    cmp eax, 244
    jne .L_lossy_valid_second
    cmp edx, 144
    jae .L_lossy_replace
.L_lossy_valid_second:
    mov r14d, 2
    movzx edx, byte ptr [rbx+2]
    sub edx, 128
    cmp edx, 64
    jae .L_lossy_replace
    mov r14d, 3
    cmp eax, 240
    jb .L_lossy_copy
    movzx edx, byte ptr [rbx+3]
    sub edx, 128
    cmp edx, 64
    jae .L_lossy_replace
    mov r14d, 4
    jmp .L_lossy_copy
.L_lossy_valid_two:
    mov r14d, 2
.L_lossy_copy:
    movzx edx, byte ptr [rbx]
    inc rbx
    mov [r13], dl
    inc r13
    dec r14
    jne .L_lossy_copy
    jmp .L_lossy_next
.L_lossy_replace:
    mov byte ptr [r13], 239
    mov byte ptr [r13+1], 191
    mov byte ptr [r13+2], 189
    add r13, 3
    add rbx, r14
    jmp .L_lossy_next
.L_lossy_done:
    mov byte ptr [r13], 0
    mov rax, r12
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.L_lossy_oom:
    mov edi, 1
    call exit@PLT
.size ripwc_lossy,.-ripwc_lossy

// Jaro similarity and >0.7 threshold used by clap's long-option suggestions.
// Candidate strings are ASCII; input positions count Unicode scalar values.
.L_suggest:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 136
    mov rbx, rdi
    xor r12d, r12d
    mov rdx, rbx
.L_suggest_length:
    movzx eax, byte ptr [rdx]
    inc rdx
    test eax, eax
    je .L_suggest_length_done
    and eax, 192
    cmp eax, 128
    je .L_suggest_length
    inc r12
    jmp .L_suggest_length
.L_suggest_length_done:
    mov r13, -1
    xor r14d, r14d
    mov qword ptr [rbp-96], 0
.L_suggest_candidate:
    cmp r14, 6
    je .L_suggest_skip
    lea rax, [rip+.L_options]
    mov r15, [rax+r14*8]
    add r15, 2
    mov rdi, r15
    call strlen@PLT
    mov [rbp-48], rax
    cmp rax, r12
    cmovb rax, r12
    shr rax, 1
    test rax, rax
    je .L_suggest_range_ready
    dec rax
.L_suggest_range_ready:
    mov [rbp-56], rax
    mov qword ptr [rbp-64], 0
    mov qword ptr [rbp-72], 0
    mov qword ptr [rbp-80], 0
    mov qword ptr [rbp-88], 0
.L_jaro_outer:
    mov rax, [rbp-64]
    cmp rax, r12
    jge .L_jaro_transpose
    mov rdx, rax
    sub rdx, [rbp-56]
    mov ecx, 0
    cmovb rdx, rcx
    add rax, [rbp-56]
    inc rax
    cmp rax, [rbp-48]
    cmova rax, [rbp-48]
    mov rsi, rax
    mov rax, [rbp-88]
    movzx r8d, byte ptr [rbx+rax]
.L_jaro_inner:
    cmp rdx, rsi
    jge .L_jaro_next_outer
    bt qword ptr [rbp-72], rdx
    jc .L_jaro_next_inner
    cmp byte ptr [r15+rdx], r8b
    jne .L_jaro_next_inner
    bts qword ptr [rbp-72], rdx
    mov rcx, [rbp-80]
    lea rdi, [rbp-128]
    mov [rdi+rcx], r8b
    inc qword ptr [rbp-80]
    jmp .L_jaro_next_outer
.L_jaro_next_inner:
    inc rdx
    jmp .L_jaro_inner
.L_jaro_next_outer:
    inc qword ptr [rbp-88]
.L_jaro_skip_continuation:
    mov rax, [rbp-88]
    movzx ecx, byte ptr [rbx+rax]
    and ecx, 192
    cmp ecx, 128
    jne .L_jaro_scalar_done
    inc qword ptr [rbp-88]
    jmp .L_jaro_skip_continuation
.L_jaro_scalar_done:
    inc qword ptr [rbp-64]
    jmp .L_jaro_outer
.L_jaro_transpose:
    cmp qword ptr [rbp-80], 0
    je .L_suggest_skip
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    lea rdi, [rbp-128]
.L_jaro_transpose_loop:
    cmp rdx, [rbp-48]
    jge .L_jaro_score
    bt qword ptr [rbp-72], rdx
    jnc .L_jaro_transpose_next
    movzx eax, byte ptr [r15+rdx]
    cmp al, byte ptr [rdi+rcx]
    je .L_jaro_transpose_match
    inc r8
.L_jaro_transpose_match:
    inc rcx
.L_jaro_transpose_next:
    inc rdx
    jmp .L_jaro_transpose_loop
.L_jaro_score:
    shr r8, 1
    cvtsi2sd xmm0, qword ptr [rbp-80]
    cvtsi2sd xmm1, r12
    movapd xmm3, xmm0
    divsd xmm3, xmm1
    cvtsi2sd xmm2, qword ptr [rbp-48]
    movapd xmm1, xmm0
    divsd xmm1, xmm2
    addsd xmm3, xmm1
    mov rax, [rbp-80]
    sub rax, r8
    cvtsi2sd xmm2, rax
    divsd xmm2, xmm0
    addsd xmm3, xmm2
    divsd xmm3, qword ptr [rip+.L_three]
    ucomisd xmm3, qword ptr [rip+.L_threshold]
    jbe .L_suggest_skip
    ucomisd xmm3, qword ptr [rbp-96]
    jb .L_suggest_skip
    movsd [rbp-96], xmm3
    mov r13, r14
.L_suggest_skip:
    inc r14
    cmp r14, 9
    jl .L_suggest_candidate
    mov rax, r13
    add rsp, 136
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

.section .rodata
.L_default_name: .asciz "ripwc"
.L_short_chars: .asciz "cmlwLrvhV"
.L_bytes: .asciz "--bytes"
.L_chars: .asciz "--chars"
.L_lines: .asciz "--lines"
.L_words: .asciz "--words"
.L_max: .asciz "--max-line-length"
.L_recursive: .asciz "--recursive"
.L_verbose: .asciz "-v"
.L_help_option: .asciz "--help"
.L_version_option: .asciz "--version"
.L_help_intro: .asciz "A rewrite of the GNU coreutils 'wc' tool.\n\nUsage: "
.L_help_rest: .asciz " [OPTIONS] <FILE>...\n\nArguments:\n  <FILE>...  The file or folder to read\n\nOptions:\n  -c, --bytes            Print the byte counts\n  -m, --chars            Print the character counts\n  -l, --lines            Print newline counts\n  -w, --words            Print word counts\n  -L, --max-line-length  Print maximum display width\n  -r, --recursive        Recursively search through folders and files\n  -v                     Print verbose output\n  -h, --help             Print help\n  -V, --version          Print version\n"
.L_version_text: .asciz "ripwc 1.0.0\n"
.L_missing_text: .asciz "error: the following required arguments were not provided:\n  <FILE>...\n"
.L_duplicate_intro: .asciz "error: the argument '"
.L_duplicate_rest: .asciz "' cannot be used multiple times\n"
.L_unknown_intro: .asciz "error: unexpected argument '"
.L_unknown_rest: .asciz "' found\n\n"
.L_value_intro: .asciz "error: unexpected value '"
.L_value_middle: .asciz "' for '"
.L_value_rest: .asciz "' found; no more were expected\n"
.L_hint_intro: .asciz "  tip: a similar argument exists: '"
.L_hint_end: .asciz "'\n"
.L_pass_intro: .asciz "  tip: to pass '"
.L_pass_middle: .asciz "' as a value, use '-- "
.L_usage_intro: .asciz "\nUsage: "
.L_space: .asciz " "
.L_generic: .asciz " [OPTIONS]"
.L_file: .asciz " <FILE>..."
.L_group: .asciz " <FILE|--bytes|--chars|--lines|--words|--max-line-length|--recursive|-v>"
.L_error_tail: .asciz "\n\nFor more information, try '--help'.\n"
.L_utf8_error: .asciz "error: invalid UTF-8 was detected in one or more arguments\n"


.p2align 3
.L_threshold: .double 0.7
.L_three: .double 3.0
.section .data.rel.ro
.p2align 3
.L_options: .quad .L_bytes, .L_chars, .L_lines, .L_words, .L_max, .L_recursive, .L_verbose, .L_help_option, .L_version_option
.data
.L_short_bad: .byte 45
    .space 7
.p2align 3
.L_stream: .quad 0
.L_name: .quad 0
.L_order_count: .quad 0
.L_order: .space 72
.globl ripwc_flags
.globl ripwc_recursive
.globl ripwc_verbose
.globl ripwc_nargs
.globl ripwc_paths
ripwc_flags: .quad 13
ripwc_recursive: .quad 0
ripwc_verbose: .quad 0
ripwc_nargs: .quad 0
ripwc_paths: .quad 0
.section .note.GNU-stack,"",@progbits
