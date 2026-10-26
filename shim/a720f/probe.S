/* SPDX-License-Identifier: GPL-2.0-only
 * SM-A720F stage-0 entry probe. Not device tested.
 * Proves that S-Boot runs this Image from BOOT p10 and that the reserved
 * log page survives into TWRP's /proc/last_kmsg. No storage, display, EFS or
 * watchdog writes. Ends by requesting recovery through the Exynos7880 PMU
 * (the same INFORM2/INFORM3/SWRESET sequence as `reboot recovery`).
 *
 * Log page 0x469ff000, little-endian u64:
 * 0 signature "A7XNU001"; 1 CurrentEL; 2 SCTLR_EL1; 3 incoming FDT (x0);
 * 4 actual Image address; 5 MPIDR_EL1; 6 ID_AA64MMFR0_EL1;
 * 7 ID_AA64PFR0_EL1; 8 CNTFRQ_EL0; 9 FDT magic (raw word);
 * 10 result (1=entry, 2=registers captured, 3=FDT magic valid);
 * 11 ID_AA64ISAR0_EL1; 12 MIDR_EL1; 13 WTCON at entry; 14 WTCNT at entry;
 * 32.. text "A7XNU001 probe reached" for grep.
 * The page's final u64 is SEC_LKMSG_MAGICKEY (see board.h).
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
    mrs x21, sctlr_el1
    tbnz x21, #0, halt
    ldr x13, =A7_LOG_BASE
    mov x14, x13
    add x15, x13, #4096
inval:
    dc ivac, x14
    add x14, x14, #32
    cmp x14, x15
    b.lo inval
    dsb sy
    mov x14, x13
zero:
    stp xzr, xzr, [x14], #16
    cmp x14, x15
    b.lo zero
    ldr x14, =0x313030554e583741 /* "A7XNU001" */
    str x14, [x13, #0]
    str x20, [x13, #8]
    str x21, [x13, #16]
    str x19, [x13, #24]
    adr x14, _start
    str x14, [x13, #32]
    mov x14, #1
    str x14, [x13, #80]
    mrs x14, mpidr_el1
    str x14, [x13, #40]
    mrs x14, id_aa64mmfr0_el1
    str x14, [x13, #48]
    mrs x14, id_aa64pfr0_el1
    str x14, [x13, #56]
    mrs x14, cntfrq_el0
    str x14, [x13, #64]
    mrs x14, id_aa64isar0_el1
    str x14, [x13, #88]
    mrs x14, midr_el1
    str x14, [x13, #96]
    ldr x16, =A7_WDT_BASE
    ldr w14, [x16]
    str x14, [x13, #104]
    ldr w14, [x16, #8]
    str x14, [x13, #112]
    mov x14, #2
    str x14, [x13, #80]
    /* Readable marker for `strings /proc/last_kmsg | grep A7XNU`. */
    adr x16, banner
    add x17, x13, #256
    mov x15, #(banner_end - banner)
copy_banner:
    ldrb w14, [x16], #1
    strb w14, [x17], #1
    subs x15, x15, #1
    b.ne copy_banner
    cbz x19, magic
    tst x19, #7
    b.ne magic
    ldr w14, [x19]
    str x14, [x13, #72]
    rev w14, w14
    ldr w15, =0xd00dfeed
    cmp w14, w15
    b.ne magic
    mov x14, #3
    str x14, [x13, #80]
magic:
    ldr x14, =A7_LKMSG_MAGICKEY
    ldr x15, =A7_LKMSG_MAGIC_PA
    str x14, [x15]
    dmb sy
    mov x14, x13
    add x15, x13, #4096
flush_line:
    dc cvac, x14
    add x14, x14, #32
    cmp x14, x15
    b.lo flush_line
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

banner:
    .ascii "\nA7XNU001 probe reached\n"
banner_end:
    .balign 4
