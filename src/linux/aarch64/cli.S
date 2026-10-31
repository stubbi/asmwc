// Linux/glibc AArch64 argument parser, ported from src/cli.S. The option model deliberately follows the
// pinned clap derive declaration, including duplicate errors and typo hints.
.text
.p2align 2
.globl ripwc_parse
ripwc_parse:
    stp x29, x30, [sp, #-96]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    stp x23, x24, [sp, #48]
    stp x25, x26, [sp, #64]
    stp x27, x28, [sp, #80]
    mov w19, w0
    mov x20, x1
    mov x23, #0
    mov x25, #0
    mov x28, #0
    adrp x9, L_order_count
    str xzr, [x9, :lo12:L_order_count]
    adrp x9, L_stdout
    adrp x10, :got:stderr
    ldr x10, [x10, :got_lo12:stderr]
    ldr x10, [x10]
    str x10, [x9, :lo12:L_stdout]
    adrp x0, L_default_name
    add x0, x0, :lo12:L_default_name
    cbz w19, L_name_ready
    ldr x9, [x20]
    cbz x9, L_name_ready
    ldrb w10, [x9]
    cbz w10, L_name_ready
    mov x0, x9
    bl strdup
    cbz x0, L_oom
    mov x26, x0
    bl strlen
    add x27, x26, x0
L_name_trim:
    cmp x27, x26
    b.eq L_name_default
    ldrb w9, [x27, #-1]
    cmp w9, #47
    b.ne L_name_component
    sub x27, x27, #1
    b L_name_trim
L_name_component:
    mov x10, x27
L_name_component_start:
    cmp x10, x26
    b.eq L_name_component_found
    ldrb w9, [x10, #-1]
    cmp w9, #47
    b.eq L_name_component_found
    sub x10, x10, #1
    b L_name_component_start
L_name_component_found:
    sub x11, x27, x10
    cmp x11, #1
    b.ne L_name_check_parent
    ldrb w9, [x10]
    cmp w9, #46
    b.ne L_name_finish
    mov x27, x10
    b L_name_trim
L_name_check_parent:
    cmp x11, #2
    b.ne L_name_finish
    ldrh w9, [x10]
    mov w11, #11822
    cmp w9, w11
    b.eq L_name_default
L_name_finish:
    strb wzr, [x27]
    mov x0, x26
    bl basename
    mov x26, x0
    mov x22, x0
    bl L_check_utf8
    cbz w0, L_name_default
    mov x0, x26
    b L_name_ready
L_name_default:
    adrp x0, L_default_name
    add x0, x0, :lo12:L_default_name
L_name_ready:
    adrp x9, L_name
    str x0, [x9, :lo12:L_name]
    uxtw x0, w19
    lsl x0, x0, #3
    add x0, x0, #8
    bl malloc
    cbz x0, L_oom
    mov x24, x0
    mov x21, #1
L_next:
    cmp x21, x19
    b.ge L_done
    ldr x22, [x20, x21, lsl #3]
    add x21, x21, #1
    ldrb w9, [x22]
    cmp w9, #45
    b.ne L_path
    ldrb w9, [x22, #1]
    cbz w9, L_path
    cmp w9, #45
    b.eq L_long
    add x22, x22, #1
L_short:
    ldrb w9, [x22], #1
    cbz w9, L_next
    adrp x10, L_short_chars
    add x10, x10, :lo12:L_short_chars
    mov x27, #0
L_short_find:
    ldrb w11, [x10, x27]
    cmp w11, w9
    b.eq L_short_found
    add x27, x27, #1
    cmp x27, #9
    b.lt L_short_find
    // clap reports one Unicode scalar from a short-option cluster.
    sub x22, x22, #1
    bl L_check_utf8
    mov x26, x0
    mov x0, x22
    bl L_lossy
    cbz x26, L_short_invalid_tail
    mov x11, x0
    adrp x10, L_short_bad
    add x10, x10, :lo12:L_short_bad
    mov x12, #1
    ldrb w9, [x11], #1
    strb w9, [x10, x12]
    add x12, x12, #1
L_short_scalar:
    ldrb w9, [x11]
    and w13, w9, #192
    cmp w13, #128
    b.ne L_short_scalar_end
    strb w9, [x10, x12]
    add x11, x11, #1
    add x12, x12, #1
    b L_short_scalar
L_short_scalar_end:
    strb wzr, [x10, x12]
    mov x22, x10
    mov x28, #1
    b L_unknown
L_short_invalid_tail:
    mov x22, x0
    bl strlen
    add x0, x0, #2
    bl malloc
    cbz x0, L_oom
    mov x10, x0
    mov w9, #45
    strb w9, [x10], #1
L_short_invalid_copy:
    ldrb w9, [x22], #1
    strb w9, [x10], #1
    cbnz w9, L_short_invalid_copy
    mov x22, x0
    mov x28, #1
    b L_unknown
L_short_found:
    bl L_validate_paths
    cmp x27, #7
    b.eq L_help
    cmp x27, #8
    b.eq L_version
    bl L_record
    b L_short
L_long:
    ldrb w9, [x22, #2]
    cbnz w9, L_long_option
    bl L_validate_paths
L_after_separator:
    cmp x21, x19
    b.ge L_done
    ldr x22, [x20, x21, lsl #3]
    add x21, x21, #1
    str x22, [x24, x25, lsl #3]
    add x25, x25, #1
    b L_after_separator
L_long_option:
    mov x0, x22
    bl L_lossy
    cbz x0, L_oom
    mov x22, x0
    mov x26, #0
    mov x9, x22
L_equal_scan:
    ldrb w10, [x9]
    cbz w10, L_long_find_start
    cmp w10, #61
    b.eq L_equal
    add x9, x9, #1
    b L_equal_scan
L_equal:
    strb wzr, [x9]
    add x26, x9, #1
L_long_find_start:
    mov x27, #0
L_long_find:
    mov x0, x22
    bl L_option_ptr
    mov x1, x0
    mov x0, x22
    bl strcmp
    cbz w0, L_long_found
    add x27, x27, #1
    cmp x27, #9
    b.lt L_long_find
    mov x28, #0
    b L_unknown
L_long_found:
    cbnz x26, L_unexpected_value
    bl L_validate_paths
    cmp x27, #7
    b.eq L_help
    cmp x27, #8
    b.eq L_version
    bl L_record
    b L_next
L_path:
    str x22, [x24, x25, lsl #3]
    add x25, x25, #1
    b L_next
L_done:
    bl L_validate_paths
    cbz x25, L_missing
    str xzr, [x24, x25, lsl #3]
    and x9, x23, #31
    mov x10, #13
    cmp x9, #0
    csel x9, x10, x9, eq
    adrp x10, ripwc_flags
    str x9, [x10, :lo12:ripwc_flags]
    ubfx x9, x23, #5, #1
    adrp x10, ripwc_recursive
    str x9, [x10, :lo12:ripwc_recursive]
    ubfx x9, x23, #6, #1
    adrp x10, ripwc_verbose
    str x9, [x10, :lo12:ripwc_verbose]
    adrp x10, ripwc_nargs
    str x25, [x10, :lo12:ripwc_nargs]
    adrp x10, ripwc_paths
    str x24, [x10, :lo12:ripwc_paths]
    ldp x27, x28, [sp, #80]
    ldp x25, x26, [sp, #64]
    ldp x23, x24, [sp, #48]
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #96
    ret

// x27 is the option index. Append it to the insertion-order usage list.
L_record:
    mov x9, #1
    lsl x9, x9, x27
    tst x23, x9
    b.ne L_duplicate
    orr x23, x23, x9
L_record_usage:
    adrp x9, L_order_count
    ldr x10, [x9, :lo12:L_order_count]
    adrp x11, L_order
    add x11, x11, :lo12:L_order
    str x27, [x11, x10, lsl #3]
    add x10, x10, #1
    str x10, [x9, :lo12:L_order_count]
    ret

// Get the preferred visible spelling of option x27.
L_option_ptr:
    adrp x9, L_options
    add x9, x9, :lo12:L_options
    ldr x0, [x9, x27, lsl #3]
    ret

// Emit x0 literally, so user-provided paths and flags are never format strings.
L_emit:
    adrp x9, L_stdout
    ldr x1, [x9, :lo12:L_stdout]
    b fputs

L_help:
    adrp x9, :got:stdout
    ldr x9, [x9, :got_lo12:stdout]
    ldr x9, [x9]
    adrp x10, L_stdout
    str x9, [x10, :lo12:L_stdout]
    adrp x0, L_help_intro
    add x0, x0, :lo12:L_help_intro
    bl L_emit
    adrp x9, L_name
    ldr x0, [x9, :lo12:L_name]
    bl L_emit
    adrp x0, L_help_rest
    add x0, x0, :lo12:L_help_rest
    bl L_emit
    mov w0, #0
    bl exit
L_version:
    adrp x9, :got:stdout
    ldr x9, [x9, :got_lo12:stdout]
    ldr x9, [x9]
    adrp x10, L_stdout
    str x9, [x10, :lo12:L_stdout]
    adrp x0, L_version_text
    add x0, x0, :lo12:L_version_text
    bl L_emit
    mov w0, #0
    bl exit
L_missing:
    adrp x0, L_missing_text
    add x0, x0, :lo12:L_missing_text
    bl L_emit
    mov x28, #0
    b L_error_usage
L_duplicate:
    adrp x0, L_duplicate_intro
    add x0, x0, :lo12:L_duplicate_intro
    bl L_emit
    bl L_option_ptr
    bl L_emit
    adrp x0, L_duplicate_rest
    add x0, x0, :lo12:L_duplicate_rest
    bl L_emit
    mov x28, #1
    b L_error_usage
L_unexpected_value:
    adrp x0, L_value_intro
    add x0, x0, :lo12:L_value_intro
    bl L_emit
    mov x0, x26
    bl L_emit
    adrp x0, L_value_middle
    add x0, x0, :lo12:L_value_middle
    bl L_emit
    bl L_option_ptr
    bl L_emit
    adrp x0, L_value_rest
    add x0, x0, :lo12:L_value_rest
    bl L_emit
    // clap uses a group-style usage if another flag was already consumed.
    cbnz x23, L_value_group
    bl L_record_usage
    mov x28, #0
    b L_error_usage
L_value_group:
    mov x28, #2
    b L_error_usage
L_unknown:
    adrp x0, L_unknown_intro
    add x0, x0, :lo12:L_unknown_intro
    bl L_emit
    mov x0, x22
    bl L_emit
    adrp x0, L_unknown_rest
    add x0, x0, :lo12:L_unknown_rest
    bl L_emit
    cbnz x28, L_unknown_no_hint
    add x0, x22, #2
    bl L_suggest
    cmp x0, #0
    b.lt L_unknown_no_hint
    mov x27, x0
    adrp x0, L_hint_intro
    add x0, x0, :lo12:L_hint_intro
    bl L_emit
    bl L_option_ptr
    bl L_emit
    adrp x0, L_hint_end
    add x0, x0, :lo12:L_hint_end
    bl L_emit
    mov x9, #1
    lsl x9, x9, x27
    tst x23, x9
    b.ne L_hint_usage
    bl L_record_usage
L_hint_usage:
    mov x28, #0
    b L_error_usage
L_unknown_no_hint:
    adrp x0, L_pass_intro
    add x0, x0, :lo12:L_pass_intro
    bl L_emit
    mov x0, x22
    bl L_emit
    adrp x0, L_pass_middle
    add x0, x0, :lo12:L_pass_middle
    bl L_emit
    mov x0, x22
    bl L_emit
    adrp x0, L_hint_end
    add x0, x0, :lo12:L_hint_end
    bl L_emit
    // Short-flag errors always show generic usage. A pristine parser does too.
    cbnz x28, L_error_usage
    cbnz x23, L_error_usage
    cbnz x25, L_error_usage
    mov x28, #1
L_error_usage:
    adrp x0, L_usage_intro
    add x0, x0, :lo12:L_usage_intro
    bl L_emit
    adrp x9, L_name
    ldr x0, [x9, :lo12:L_name]
    bl L_emit
    cmp x28, #1
    b.eq L_usage_generic
    cmp x28, #2
    b.eq L_usage_group
    mov x26, #0
L_usage_loop:
    adrp x9, L_order_count
    ldr x9, [x9, :lo12:L_order_count]
    cmp x26, x9
    b.ge L_usage_file
    adrp x9, L_order
    add x9, x9, :lo12:L_order
    ldr x27, [x9, x26, lsl #3]
    adrp x0, L_space
    add x0, x0, :lo12:L_space
    bl L_emit
    bl L_option_ptr
    bl L_emit
    add x26, x26, #1
    b L_usage_loop
L_usage_generic:
    adrp x0, L_generic
    add x0, x0, :lo12:L_generic
    bl L_emit
L_usage_file:
    adrp x0, L_file
    add x0, x0, :lo12:L_file
    bl L_emit
    b L_error_end
L_usage_group:
    cmp x27, #7
    b.lt L_group_only
    adrp x0, L_space
    add x0, x0, :lo12:L_space
    bl L_emit
    bl L_option_ptr
    bl L_emit
L_group_only:
    adrp x0, L_group
    add x0, x0, :lo12:L_group
    bl L_emit
L_error_end:
    adrp x0, L_error_tail
    add x0, x0, :lo12:L_error_tail
    bl L_emit
    mov w0, #2
    bl exit
L_oom:
    mov w0, #1
    bl exit

// clap resolves a pending positional group before processing a recognized flag.
// Unknown flags fail first, even if that pending group contains malformed UTF-8.
L_validate_paths:
    stp x29, x30, [sp, #-32]!
    str x22, [sp, #16]
L_validate_next:
    cmp x28, x25
    b.ge L_validate_done
    ldr x22, [x24, x28, lsl #3]
    bl L_check_utf8
    cbz w0, L_utf8_error_emit
    add x28, x28, #1
    b L_validate_next
L_validate_done:
    ldr x22, [sp, #16]
    ldp x29, x30, [sp], #32
    ret

// Return 1 if the string in x22 is valid UTF-8, otherwise 0.
L_check_utf8:
    mov x9, x22
L_utf8_next:
    ldrb w10, [x9], #1
    cbz w10, L_utf8_ok
    cmp w10, #128
    b.lo L_utf8_next
    cmp w10, #194
    b.lo L_utf8_bad
    cmp w10, #224
    b.lo L_utf8_two
    cmp w10, #240
    b.lo L_utf8_three
    cmp w10, #245
    b.hs L_utf8_bad
    ldrb w11, [x9], #1
    cmp w11, #128
    b.lo L_utf8_bad
    cmp w11, #192
    b.hs L_utf8_bad
    cmp w10, #240
    b.ne L_utf8_not_f0
    cmp w11, #144
    b.lo L_utf8_bad
L_utf8_not_f0:
    cmp w10, #244
    b.ne L_utf8_more_two
    cmp w11, #144
    b.hs L_utf8_bad
    b L_utf8_more_two
L_utf8_three:
    ldrb w11, [x9], #1
    cmp w11, #128
    b.lo L_utf8_bad
    cmp w11, #192
    b.hs L_utf8_bad
    cmp w10, #224
    b.ne L_utf8_not_e0
    cmp w11, #160
    b.lo L_utf8_bad
L_utf8_not_e0:
    cmp w10, #237
    b.ne L_utf8_two
    cmp w11, #160
    b.hs L_utf8_bad
    b L_utf8_two
L_utf8_more_two:
    ldrb w11, [x9], #1
    sub w11, w11, #128
    cmp w11, #64
    b.hs L_utf8_bad
L_utf8_two:
    ldrb w11, [x9], #1
    sub w11, w11, #128
    cmp w11, #64
    b.lo L_utf8_next
L_utf8_bad:
    mov w0, #0
    ret
L_utf8_error_emit:
    adrp x0, L_utf8_error
    add x0, x0, :lo12:L_utf8_error
    bl L_emit
    mov x28, #1
    b L_error_usage
L_utf8_ok:
    mov w0, #1
    ret

// Rust's to_string_lossy spelling for option diagnostics. Each maximal valid
// prefix of a malformed UTF-8 sequence is replaced by one U+FFFD scalar.
.globl ripwc_path_lossy
.type ripwc_path_lossy, %function
ripwc_path_lossy:
L_lossy:
    stp x29, x30, [sp, #-64]!
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    mov x19, x0
    bl strlen
    mov x9, #3
    madd x0, x0, x9, x9
    bl malloc
    cbz x0, L_oom
    mov x20, x0
    mov x21, x0
L_lossy_next:
    ldrb w9, [x19]
    cbz w9, L_lossy_done
    mov x22, #1
    cmp w9, #128
    b.lo L_lossy_copy
    cmp w9, #194
    b.lo L_lossy_replace
    cmp w9, #245
    b.hs L_lossy_replace
    ldrb w10, [x19, #1]
    cmp w10, #128
    b.lo L_lossy_replace
    cmp w10, #192
    b.hs L_lossy_replace
    cmp w9, #224
    b.lo L_lossy_valid_two
    cmp w9, #224
    b.ne L_lossy_not_e0
    cmp w10, #160
    b.lo L_lossy_replace
L_lossy_not_e0:
    cmp w9, #237
    b.ne L_lossy_not_ed
    cmp w10, #160
    b.hs L_lossy_replace
L_lossy_not_ed:
    cmp w9, #240
    b.ne L_lossy_not_f0
    cmp w10, #144
    b.lo L_lossy_replace
L_lossy_not_f0:
    cmp w9, #244
    b.ne L_lossy_valid_second
    cmp w10, #144
    b.hs L_lossy_replace
L_lossy_valid_second:
    mov x22, #2
    ldrb w10, [x19, #2]
    sub w10, w10, #128
    cmp w10, #64
    b.hs L_lossy_replace
    mov x22, #3
    cmp w9, #240
    b.lo L_lossy_copy
    ldrb w10, [x19, #3]
    sub w10, w10, #128
    cmp w10, #64
    b.hs L_lossy_replace
    mov x22, #4
    b L_lossy_copy
L_lossy_valid_two:
    mov x22, #2
L_lossy_copy:
    ldrb w9, [x19], #1
    strb w9, [x21], #1
    subs x22, x22, #1
    b.ne L_lossy_copy
    b L_lossy_next
L_lossy_replace:
    mov w9, #239
    strb w9, [x21], #1
    mov w9, #191
    strb w9, [x21], #1
    mov w9, #189
    strb w9, [x21], #1
    add x19, x19, x22
    b L_lossy_next
L_lossy_done:
    strb wzr, [x21]
    mov x0, x20
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #64
    ret

// Jaro similarity, the algorithm and >0.7 threshold used by clap 4.6.7.
// Long option candidates are ASCII, at most 15 bytes; a 64-bit match map and
// a small sequence buffer suffice even for arbitrarily long unknown options.
// x0 = unknown name without --; result x0 = option index or -1.
L_suggest:
    stp x29, x30, [sp, #-128]!
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    stp x23, x24, [sp, #48]
    stp x25, x26, [sp, #64]
    stp x27, x28, [sp, #80]
    str d8, [sp, #112]
    mov x19, x0
    mov x20, #0
    mov x9, x19
L_suggest_length:
    ldrb w10, [x9], #1
    cbz w10, L_suggest_length_done
    and w10, w10, #192
    cmp w10, #128
    cinc x20, x20, ne
    b L_suggest_length
L_suggest_length_done:
    mov x21, #-1
    mov x22, #0
    fmov d8, xzr
L_suggest_candidate:
    cmp x22, #6
    b.eq L_suggest_skip
    adrp x9, L_options
    add x9, x9, :lo12:L_options
    ldr x23, [x9, x22, lsl #3]
    add x23, x23, #2
    mov x0, x23
    bl strlen
    mov x24, x0
    cmp x20, x24
    csel x25, x20, x24, hi
    lsr x25, x25, #1
    subs x25, x25, #1
    csel x25, x25, xzr, hs
    mov x26, #0
    mov x27, #0
    mov x28, #0
    mov x15, #0
L_jaro_outer:
    cmp x26, x20
    b.ge L_jaro_transpose
    subs x9, x26, x25
    csel x9, x9, xzr, hs
    add x10, x26, x25
    add x10, x10, #1
    cmp x10, x24
    csel x10, x10, x24, lo
    ldrb w11, [x19, x15]
L_jaro_inner:
    cmp x9, x10
    b.ge L_jaro_next_outer
    mov x12, #1
    lsl x12, x12, x9
    tst x27, x12
    b.ne L_jaro_next_inner
    ldrb w13, [x23, x9]
    cmp w11, w13
    b.ne L_jaro_next_inner
    orr x27, x27, x12
    add x14, sp, #96
    strb w11, [x14, x28]
    add x28, x28, #1
    b L_jaro_next_outer
L_jaro_next_inner:
    add x9, x9, #1
    b L_jaro_inner
L_jaro_next_outer:
    add x15, x15, #1
L_jaro_skip_continuation:
    ldrb w11, [x19, x15]
    and w11, w11, #192
    cmp w11, #128
    b.ne L_jaro_scalar_done
    add x15, x15, #1
    b L_jaro_skip_continuation
L_jaro_scalar_done:
    add x26, x26, #1
    b L_jaro_outer
L_jaro_transpose:
    cbz x28, L_suggest_skip
    mov x9, #0
    mov x10, #0
    mov x11, #0
L_jaro_transpose_loop:
    cmp x9, x24
    b.ge L_jaro_score
    lsr x12, x27, x9
    tbz x12, #0, L_jaro_transpose_next
    ldrb w12, [x23, x9]
    add x13, sp, #96
    ldrb w13, [x13, x10]
    cmp w12, w13
    cinc x11, x11, ne
    add x10, x10, #1
L_jaro_transpose_next:
    add x9, x9, #1
    b L_jaro_transpose_loop
L_jaro_score:
    lsr x11, x11, #1
    ucvtf d0, x28
    ucvtf d1, x20
    fdiv d1, d0, d1
    ucvtf d2, x24
    fdiv d2, d0, d2
    fadd d1, d1, d2
    sub x9, x28, x11
    ucvtf d2, x9
    fdiv d2, d2, d0
    fadd d1, d1, d2
    fmov d2, #3.0
    fdiv d1, d1, d2
    adrp x9, L_threshold
    ldr d2, [x9, :lo12:L_threshold]
    fcmp d1, d2
    b.le L_suggest_skip
    // Stable score sorting makes the later option win exact ties.
    fcmp d1, d8
    b.lt L_suggest_skip
    fmov d8, d1
    mov x21, x22
L_suggest_skip:
    add x22, x22, #1
    cmp x22, #9
    b.lt L_suggest_candidate
    mov x0, x21
    ldr d8, [sp, #112]
    ldp x27, x28, [sp, #80]
    ldp x25, x26, [sp, #64]
    ldp x23, x24, [sp, #48]
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #128
    ret

.section .rodata
L_default_name: .asciz "ripwc"
L_short_chars: .asciz "cmlwLrvhV"
L_bytes: .asciz "--bytes"
L_chars: .asciz "--chars"
L_lines: .asciz "--lines"
L_words: .asciz "--words"
L_max: .asciz "--max-line-length"
L_recursive: .asciz "--recursive"
L_verbose: .asciz "-v"
L_help_option: .asciz "--help"
L_version_option: .asciz "--version"
L_help_intro: .asciz "A rewrite of the GNU coreutils 'wc' tool.\n\nUsage: "
L_help_rest: .asciz " [OPTIONS] <FILE>...\n\nArguments:\n  <FILE>...  The file or folder to read\n\nOptions:\n  -c, --bytes            Print the byte counts\n  -m, --chars            Print the character counts\n  -l, --lines            Print newline counts\n  -w, --words            Print word counts\n  -L, --max-line-length  Print maximum display width\n  -r, --recursive        Recursively search through folders and files\n  -v                     Print verbose output\n  -h, --help             Print help\n  -V, --version          Print version\n"
L_version_text: .asciz "ripwc 1.0.0\n"
L_missing_text: .asciz "error: the following required arguments were not provided:\n  <FILE>...\n"
L_duplicate_intro: .asciz "error: the argument '"
L_duplicate_rest: .asciz "' cannot be used multiple times\n"
L_unknown_intro: .asciz "error: unexpected argument '"
L_unknown_rest: .asciz "' found\n\n"
L_value_intro: .asciz "error: unexpected value '"
L_value_middle: .asciz "' for '"
L_value_rest: .asciz "' found; no more were expected\n"
L_hint_intro: .asciz "  tip: a similar argument exists: '"
L_hint_end: .asciz "'\n"
L_pass_intro: .asciz "  tip: to pass '"
L_pass_middle: .asciz "' as a value, use '-- "
L_usage_intro: .asciz "\nUsage: "
L_space: .asciz " "
L_generic: .asciz " [OPTIONS]"
L_file: .asciz " <FILE>..."
L_group: .asciz " <FILE|--bytes|--chars|--lines|--words|--max-line-length|--recursive|-v>"
L_error_tail: .asciz "\n\nFor more information, try '--help'.\n"
L_utf8_error: .asciz "error: invalid UTF-8 was detected in one or more arguments\n"

.data
.p2align 3
L_options: .quad L_bytes, L_chars, L_lines, L_words, L_max, L_recursive, L_verbose, L_help_option, L_version_option
L_threshold: .double 0.7
L_short_bad: .byte 45
    .space 7
.p2align 3
L_stdout: .quad 0
L_name: .quad 0
L_order_count: .quad 0
L_order: .space 72
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

.section .note.GNU-stack,"",%progbits
