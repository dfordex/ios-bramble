/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef A720F_LOADER_WATCHDOG_H
#define A720F_LOADER_WATCHDOG_H
#include <stdint.h>
#include "board.h"

/* Exynos7880 exynos7-wdt: reload WTCNT from the existing WTDAT.
 * Keep servicing S-Boot's timer while an attempted stop is unconfirmed.
 * The registers are WTCON +0, WTDAT +4, WTCNT +8.
 */
static inline void a7_watchdog_reload(volatile uint32_t *regs)
{
    uint32_t count = regs[1] & 0xffffU;
    regs[2] = count ? count : 0xffffU;
}

static inline void a7_watchdog_keepalive(void)
{
    a7_watchdog_reload((volatile uint32_t *)A7_WDT_BASE);
    __asm__ volatile("dsb sy" : : : "memory");
}
#endif
