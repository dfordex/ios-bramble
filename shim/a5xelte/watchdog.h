/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef A5XELTE_LOADER_WATCHDOG_H
#define A5XELTE_LOADER_WATCHDOG_H
#include <stdint.h>

/* Exynos7580 s3c2410_wdt: reload WTCNT from the existing WTDAT.
 * Keep servicing S-Boot's timer while an attempted stop is unconfirmed.
 * The registers are WTCON +0, WTDAT +4, WTCNT +8.
 */
static inline void a5_watchdog_reload(volatile uint32_t *regs)
{
    uint32_t count = regs[1] & 0xffffU;
    regs[2] = count ? count : 0xffffU;
}

static inline void a5_watchdog_keepalive(void)
{
    a5_watchdog_reload((volatile uint32_t *)0x101b0000UL);
    __asm__ volatile("dsb sy" : : : "memory");
}
#endif
