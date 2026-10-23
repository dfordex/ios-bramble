# 0207c reboot: unaligned DCS read in restored loader

## Verdict: FAIL for0207c; corrected loader awaits physical execution

The restored loader has a concrete early-boot compiler defect. It was rebuilt
with Clang while older images reused the previously working loader binary.
The build command omitted `-mstrict-align`. Clang combined four ordinary byte
reads from a DCS command into one unaligned32-bit load. The phone enters with
alignment checking enabled and the MMU disabled. The source buffer address
violates that instruction's alignment requirement.

| Evidence | Value |
| --- | --- |
|0207c reserved A5XNU002 marker|offset0x1f0ec in private last_kmsg capture|
|SCTLR_EL1|0x30c5183e; A=1, M=0|
|Loader status|5, all10segments/phase4 completed, kernel entry prepared|
|Display substep79|5: DSIM handoff returned; first column DCS command not completed|
|Linked `column` symbol|0x16fa relative to loader, actualPA0x402066fa; modulo4=2|
|Actual0207c instruction|offset0xf60: `ldr w14, [x0]`, with x0 pointing to column|
|Corrected linked instructions|five `ldrb` reads at offsets0..4, no widened source read|

The instruction causes an alignment fault before the kernel is entered.
No exception PC was saved, so this is a static, hardware-state-backed cause;
the exact final exception vector behavior is not captured. Watchdog reset was
the observed eventual outcome, not sufficient evidence that normal copying or
DSIM polling alone exhausted the timer. Previous b/c timer mitigations did not
repair this illegal memory access. Their ineffective physical outcome is kept
in the progress log rather than reported as successful fixes.

## Correction and validation

Add `-mstrict-align` to the actual Samsung loader build script, applying to all
its C compilation units. The kernel/provider/compiler payload, ADT, arguments
and DTBH remain byte-identical to0207. No shader or XNU rebuild is involved.

`tools/check-a5xelte-loader-isa.py` inspects the actual linked ELF's five-byte DCS
source reads and fails on widened accesses or unexpected compiler lowering.
The saved0207c ELF fails this check; the rebuilt0207d ELF passes it. Both source
commands remain deliberately byte arrays; the fix does not rely on placing one
specific array at a convenient address. Existing12,800copy/zero and65,536reload
ASan/UBSan cases remain passing. The actual build script completes with the
ARMv8-A target; new Image10,336bytes.

This is not a proof that the corrected phone boot or the new GPU features work.
The next physical checkpoint is the loader's display labels and XNU console.
