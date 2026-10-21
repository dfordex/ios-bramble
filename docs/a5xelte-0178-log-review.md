# 0178 recovered log review — 2026-10-22

Read-only SYSTEM recovery yielded flush40,101687 raw bytes and1301 decoded
lines, without overwrite. The complete capture was scanned; raw logs remain
private.

## Sampler alignment retry

All16 hardware fences, including the existing control, terminate with status0,
header1 and MMU IRQ0. The previous fragment DATA_INVALID_FAULT is absent after
moving only the preload sampler address/data to a32-byte boundary. Six of seven
new GPU oracle cases pass; all seven are evaluated with immutable regions
intact. Shader bytes, expected values and masks are unchanged from0177.

| Case | Actual checked values passing | Result |
| --- | --- | --- |
|Rect additive coverage with prior destination|768/768|Pass|
|Cubic additive coverage with prior destination|697/697|Pass|
|Stroke half source-over with prior destination|3328/3328|Pass|
|Dynamic32x32 blur|2962/4096|Pixel mismatch|
|RAW204 half source-over|4096/4096|Pass|
|R8 partial-scissor source-over|1024/1024|Pass|
|Standalone physical RG8 preload/copy|2048/2048|Pass|

The standalone RG8 case is not evidence of an active stock RG8 Metal profile.
Masked-out path elements are excluded from the checked counts above.

The blur job completes normally but first differs at output byte384, actual64
versus expected0, tolerance1. It is not a fence timeout, MMU fault or unevaluated
test. The runtime hardware queue now reports ready despite this pixel mismatch;
readiness is a completion/lifetime condition, not proof of rendering correctness.
Source comparison explains the blur mismatch exactly: the legacy fixture input
contains RGBA bytes and uses texture swizzle0x688. The new fixture copies those
bytes unchanged but describes them as BGRA; the production runtime correctly
uses BGRA swizzle0x60a. Red/blue exchange predicts the observed2962/4096 matches
and first_bad384 actual64/expected0 exactly. Correct the fixture source to BGRA,
preserving expected pixels, native shaders and production emitter. This source
explanation still needs a corrected-input GPU replay.

## Native compiler and green line

The native helper reads the read_surf cache twice, genuinely compiles
downsample_4, then reads its cache. Translation and Midgard stages exit0;
downsample compilation takes22.200 wall seconds. The helper logs cache
verification, GREEN LINE and DONE. This corroborates the user's first visible
green line. The line is a CPU-drawn compiler status marker, not GPU pixels.

The protocol's printed verified_pairs=3 field is not a count of distinct shader
pairs compiled in this capture: the selftest loop names two pairs, read_surf and
downsample_4. No broader compiler coverage is inferred from that field.

## iOS integration and display

The458688-byte provider installs successfully; all13 installer entries finish
with sync0. Stock discovery/probe accepts the device. Backboardd again accepts14
pipeline factory calls across12profiles. There is one backboardd and one
SpringBoard execution, with no CRASH, kernel panic, pipeline rejection or
missing-selector record in this capture.

There is no G3D native completion after the startup suite. Existing diagnostics
do not establish whether command encoding/resource creation returned early or
whether the compositor has yet submitted work; absence of a completion is not
proof that no draw was attempted.

Across80 framebuffer windows (426827ms summed intervals), swaps total4 and shown
frames total2. All CPU/GPU presentation counters and bytes remain0. The printed
swap references console/default surface1; a separate full-panel BGRA surface2
is created. No successful stock iOS render-to-display transfer is established.
Two key transitions are saved. Later service activity continues to the capture
end, so the log does not indicate a fully stopped kernel.

Selector55 returns success through the current framebuffer default branch and
does no implemented operation. Its0x0 result alone is not presentation proof.

## Next capture

The user requested logging of silent paths: texture/sampler factory rejections,
the first encoding error with selector, command-buffer commit begin/result and
NativeQuery17 outcomes. These bounded phase records must preserve return values
and resource lifetimes. Without them the capture cannot identify which
unsupported resource/encoding contract is actually requested by iOS.
