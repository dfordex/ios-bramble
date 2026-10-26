/* SPDX-License-Identifier: GPL-2.0-only
 * SM-A720F Samsung legacy Image wrapper for XNU, adapted from
 * shim/a5xelte/xnu_boot.S. No storage accesses. Errors request TWRP.
 */
#include "board.h"

.section .text.head, "ax"
.global _start
_start:
    b entry
    .long 0
    .quad 0x1000             /* text_offset of the stock A720F kernel */
    .quad 0
    .quad 0
    .quad 0, 0, 0
    .byte 0x41, 0x52, 0x4d, 0x64
    .long 0

entry:
    msr daifset, #15
    mov x19, x0
    mrs x20, CurrentEL
    cmp x20, #4
    b.ne halt
    mrs x21, SCTLR_EL1
    tbnz x21, #0, halt
    ldr x13, =A7_LOG_BASE
    mov x14, x13
    add x15, x13, #4096
zero_log:
    stp xzr, xzr, [x14], #16
    cmp x14, x15
    b.lo zero_log
    ldr x14, =0x323030554e583741 /* "A7XNU002" */
    str x14, [x13]
    str x20, [x13, #8]
    str x21, [x13, #16]
    str x19, [x13, #24]
    adr x14, _start
    str x14, [x13, #32]
    mov x14, #1
    str x14, [x13, #80]
    adr x14, a7_boot_stack_top
    mov sp, x14
    mov x0, x19
    mov x1, x13
    bl a7_prepare_xnu
    ldr x13, =A7_LOG_BASE
    cbz x0, fail
    mov x16, x0
    ldr x0, [x13, #136]       /* boot_args physical address */
    /* C cleaned copied ranges and the log. XNU's entry needs MMU off. */
    mrs x14, SCTLR_EL1
    bic x14, x14, #1
    bic x14, x14, #4
    bic x14, x14, #0x1000
    msr SCTLR_EL1, x14
    isb
    br x16
fail:
    ldr x14, =A7_LKMSG_MAGICKEY
    ldr x15, =A7_LKMSG_MAGIC_PA
    str x14, [x15]
    dmb sy
    mov x14, x13
    add x15, x13, #4096
flush_log:
    dc cvac, x14
    add x14, x14, #32
    cmp x14, x15
    b.lo flush_log
    dsb sy
    ldr x0, =A7_PMU_BASE
    ldr w14, =A7_SEC_POWER_RESET
    str w14, [x0, #A7_PMU_INFORM2]
    ldr w14, =A7_REBOOT_RECOVERY
    str w14, [x0, #A7_PMU_INFORM3]
    dsb sy
    mov w14, #1
    str w14, [x0, #A7_PMU_SWRESET]
    dsb sy
halt:
    wfe
    b halt
    .ltorg

.section .data, "aw"
.balign 16
a7_boot_stack:
    .space 4096
a7_boot_stack_top:
