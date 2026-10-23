# 0207b readout and 0207c watchdog keepalive

## Verdict: CONCERNS — hardware correction pending

The previous watchdog-stop correction was not verified by hardware. The new
readout shows substantial progress, but does not establish that WTCON stopped.
0207c services the existing timer during long loader work and logs individual
DSIM/DCS steps. Its XNU, ADT, arguments and DTBH remain exactly those of0207.

| Evidence from TWRP last_kmsg | Observation |
| --- | --- |
| A5XNU002 offset0xa155f | EL1/MMUoff, correct loader/FDT/initrd |
| status10=5, segment18=10, phase19=4 | All ten segments copied, zeroed and cache-cleaned; boot arguments prepared |
| entry15=0x81e02488, bootargs17=0x83283000 | Kernel entry computed, not proof of entry execution |
| WTCON21/22 | Both0x8021: the attempted stop was not observed in readback |
| display64=3, result77=0, XNU marker absent | Display handoff had begun but did not return in this record |
| S-Boot reset cause | Repeated RST_STAT0x20000000 watchdog resets |

The old status-3 copy checkpoint was passed. The retained initial display state
does not identify which DSIM/DCS operation was active when the reset occurred.
The report therefore corrects the earlier inference that stopping the watchdog
had succeeded. Why WTCON remained enabled is not yet established.

## Correction

Use the actual downstream `s3c2410wdt_keepalive` register contract: reload WTCNT
(base+8) from existing WTDAT(base+4), preserving the control word and timer
configuration. WTDAT's low16bits define the reload; zero uses bounded0xffff.
Service every64KiB during kernel copy/zero/cache-clean, every256poll iterations,
and periodically during framebuffer clear/cache-clean. This remains runtime
state only. The existing stop attempt is retained, with no success assumption.
New loader fields23/24 capture reload data/count; display field79 distinguishes
the DSIM reset stages, column/page DCS setup and address-mode stages.

## Validation and limits

- Actual copy/zero helpers pass12,800ASan/UBSan bounds/alignment/guard cases.
- Actual reload helper passes all65,536low16bit values, high-bit masking,
  zero fallback and untouched adjacent/control register assertions.
- ARMv8-A freestanding compile/link succeeds; loader10,320bytes.
- BOOT31,420,432bytes fitsp10; full kernel/ADT/arguments payload and DTBH
  are byte-identical to0207, with only the loader/header sizing replaced.
- Timer reload effectiveness, DSIM completion and XNU entry require the next
  physical run. The precise reset instruction and a working UI remain unproved.
