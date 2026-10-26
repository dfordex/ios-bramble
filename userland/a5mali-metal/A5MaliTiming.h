/* SPDX-License-Identifier: MIT
 * CPU wall-clock diagnostics. These are never exposed as GPU timestamps.
 */
#ifndef A5_MALI_TIMING_H
#define A5_MALI_TIMING_H
#include <stdint.h>
#include <time.h>
static inline uint64_t A5MaliWallUS(void)
{
    struct timespec value;
    if(clock_gettime(CLOCK_MONOTONIC,&value))return 0;
    return (uint64_t)value.tv_sec*UINT64_C(1000000)+(uint64_t)value.tv_nsec/1000;
}
static inline uint64_t A5MaliElapsedUS(uint64_t before,uint64_t after)
{ return before && after>=before ? after-before : 0; }
/* Independent of success/failure receipt budgets. Keep late interactive
 * activity observable without logging each draw or filling the disk ring. */
static inline int A5MaliTimingSample(unsigned serial)
{ return serial && (serial<=8 || (serial<=16384 && serial%64==0)); }
#endif
