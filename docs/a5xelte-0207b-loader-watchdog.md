# 0207 Samsung-logo restart: loader watchdog handoff

## Verdict: CONCERNS — physical correction pending

0207 did not reach XNU. The recovered reserved-RAM loader record identifies
the kernel copy/zero/cache-clean stage; S-Boot records repeated watchdog resets.
The new loader takes over the bootloader timer before copying the kernel and
uses bounded aligned 64-bit accesses instead of only byte accesses. The entire
0207 kernel, ADT, arguments and DTBH remain byte-identical in 0207b.

| Evidence | Observation |
| --- | --- |
| SYSTEM flush336 | Still the old0206 log; no0207 kernel records |
| TWRP last_kmsg, reserved marker offset0x1b0b71 | A5XNU002, EL1, MMUoff, FDT0x48000000, loader0x40205000 |
| Loader status10 | -3; validated RAM base0x80000000/size0x20000000 already recorded; entry/status5 absent |
| S-Boot | Correct kernel/ramdisk lengths and kernel entry; repeated RST_STAT0x20000000 |
| Explicitly authorized first12,800BOOTbytes | ANDROID!/ARMd/SWEETXNU in expected positions; installed loader bytes match local loader, no hash comparison |

## Finding and correction

**P1:** The restored source loader leaves S-Boot's watchdog active while copying
30,753,392 bytes plus zeroing5,406,096 bytes with MMUoff. Its prior uninstrumented
status does not distinguish individual segments or copy/zero/cache-clean.
Watchdog reset is confirmed; the precise instruction at expiry is not known.

The working downstream reference is Cosmic-Kernel/android_kernel_samsung_a5xelte
commit738375813823cb33918102af385bdd5d82225e17:
`arch/arm64/boot/dts/exynos7580.dtsi:804–811` identifies WDT0x101b0000;
`drivers/watchdog/s3c2410_wdt.c:117–124` clears WTCON ENABLE and RSTEN.
The register header confirms bits5/0. The loader follows that same read-modify-write
and records WTCON before/after. No clock, PMU, radio or persistent configuration
is changed. Segment and copy/zero/cache-clean phase records identify later stalls.

## Validation and limitations

- Actual copy/zero functions pass12,800 ASan/UBSan alignment, exact-tail and
  surrounding-guard checks, including page boundaries and unaligned fallbacks.
- ARMv8-A freestanding loader compilation/link passes; Image9,344bytes.
- Existing payload and DTBH are retained exactly; BOOT31,418,384bytes fits p10.
- Header observation is not a whole-image readback; no BOOT backup was taken.
- Native hardware execution, watchdog readback and XNU entry still require the
  corrected boot's physical screen/log. No GPU or UI result is claimed.

Next checkpoint: loader display/XNU console, then recovered segment/WTCON records
if startup fails again.
