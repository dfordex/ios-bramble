/* SPDX-License-Identifier: GPL-2.0-only
 * SM-A720F (a7y17lte, Exynos7880) loader constants.
 * Sources: the phone's live device tree and dmesg read from TWRP on
 * 2026-10-26, and the Exynos7880 kernel (drivers/soc/samsung/pwrcal/S5E7880,
 * drivers/staging/samsung/sec_reboot.c, drivers/trace/exynos-ss.c).
 */
#ifndef A720F_BOARD_H
#define A720F_BOARD_H

#ifdef __ASSEMBLER__
#define A7_UL(x) x
#else
#define A7_UL(x) x##UL
#endif

/* exynos7-wdt; WTCON +0, WTDAT +4, WTCNT +8. 0x101b0000 is the MCT here. */
#define A7_WDT_BASE        A7_UL(0x10170000)

/* PMU_ALIVE. sec_reboot: INFORM2 = SEC_POWER_RESET, INFORM3 = prefix|mode. */
#define A7_PMU_BASE        A7_UL(0x106b0000)
#define A7_PMU_SWRESET     0x0400
#define A7_PMU_INFORM2     0x0808
#define A7_PMU_INFORM3     0x080c
#define A7_SEC_POWER_RESET A7_UL(0x12345678)
#define A7_REBOOT_RECOVERY A7_UL(0x12345674)   /* REBOOT_MODE_PREFIX | 4 */

/* exynos-snapshot log_kernel is 0x46800000 + 2 MiB. The loader owns its
 * last page. The kernel's last_kmsg copies the whole buffer only when the
 * buffer's final u64 holds SEC_LKMSG_MAGICKEY; otherwise it copies only up
 * to the previous kernel's write pointer and this page is lost. */
#define A7_LOG_BASE        A7_UL(0x469ff000)
#define A7_LKMSG_MAGIC_PA  A7_UL(0x469ffff8)
#define A7_LKMSG_MAGICKEY  A7_UL(0x0000000a6c6c7546)

/* Upper DRAM bank is 0x80000000-0x100000000. Linux reserves the first
 * 0x3c00000 bytes as video_scaler, so XNU starts above it. 960 MiB keeps the
 * window inside one 1 GiB block; the bank's only other carveout is Linux's
 * default CMA at 0xff000000 (live DT, dmesg). */
#define A7_RAM_BASE        A7_UL(0x84000000)
#define A7_RAM_END         A7_UL(0xc0000000)

/* decon_f@0x14830000 runs the S6E3FA3 panel in command mode with the TE
 * hardware trigger (live DT psr_mode=2, trig_mode=0; dmesg "command mode,
 * hw trigger"). Frames reach the panel only while HW_TRIG_MASK is clear
 * (decon_7880/regs-decon.h, decon_reg_set_trigger()). */
#define A7_DECON_BASE        A7_UL(0x14830000)
#define A7_DECON_TRIG_CTRL   0x0070
#define A7_DECON_HW_TRIG_EN   (1 << 4)
#define A7_DECON_HW_TRIG_MASK (1 << 5)

/* Lowest accepted initrd. S-Boot put TWRP's initrd at 0x42200000. */
#define A7_INITRD_MIN      A7_UL(0x40000000)

#endif
