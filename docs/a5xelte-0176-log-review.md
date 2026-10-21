# 0176 recovered log review — 2026-10-22

## Capture and verified installation

Read-only recovery of the SYSTEM log area yielded flush26,130063 raw bytes and
1382 decoded lines, without ring overwrite. The complete capture was scanned
for crashes, pipeline errors, GPU completion/faults and presentation counters;
backboardd startup and every repeated crash were reviewed together.

The installer wrote the436000-byte provider, Info.plist and signature metadata;
all13 installer entries completed with sync=0. The log shows4/4 CPUs initialized.
The provider loads in backboardd, initializes the device, limits and feature
queries, and the separate probe reports STOCK DEVICE ACCEPTED and queue creation.
Those establish installation/discovery, not successful rendering.

## backboardd: repeated pipeline creation abort

Nine executions terminate with SIGABRT and the same backtrace/reason:

```
namespace13 code0x4: Metal failed to build render pipeline
```

There is no kernel panic, recorded SIGILL or missing-selector exception in this
capture. The immediate failure is at pipeline creation, before any logged native
GPU submission. There are zero `G3D native: profile=` completions and all54
framebuffer metric windows have swaps=0. One SpringBoard execution is recorded;
that does not establish a drawn home screen.

### Source-proven descriptor mismatch

The UUID-pinned QuartzCore warmup row67 is
`PBGRABsovXm_Tds4A2Xhf_Isrc`. Static token decoding at0x188487630 writes the A2
attachment count into Spec.byte0xc bits5..6. The create_pipeline_state loop at
0x188381740..0x1883817cc configures RT0 and RT1 as Metal80/BGRA8. Default S=0
sets RT1 writeMask=None, but its pixelFormat remains80. Current DS4/blur registry
records only RT0=[80]; A5MaliSelectCompiledProfile compares all attachment
formats and rejects RT1=80. Its nonpath mask rule also requires All on every
configured format, rejecting the genuine disabled RT1 even if the format alone
were added.

This is a concrete incompatibility with an actual stock warmup descriptor.
It is not proof that row67 caused each recorded abort: warmup runs asynchronously
and the current provider drops the selection error and does not log the exact
failed function pair, attachment state or vertex layout. That missing dynamic
evidence prevents attributing all nine aborts to this one mismatch.

Further static comparison identifies the same issue beyond the first row:

| Family | Genuine descriptor | Current mismatch |
| --- | --- | --- |
|Blur99–108 and home206|A2 retains RT1 format equal to RT0, generally RT1 writes disabled|Registry omits RT1 entirely|
|Misc200/202/204|A3 retains all three formats; default S0 disables RT1/RT2 writes|Nonpath selector requires All masks on configured formats|
|Clear207, row166|A2S1 enables only RT1, disables RT0|Selector requires both configured targets writable|
|RGBA16 blit204, row280|Premultiplied source-over on RAW64 output|Profile lacks source-over flag; runtime explicitly rejects this blend|

These source-proven contract gaps must be corrected as complete descriptor and
execution semantics, including which passes actually write. Accepting a pipeline
while silently replaying disabled outputs would not implement the stock contract.

## Four new GPU oracle cases

None of the four new cases passes. This does not invalidate the older21-case0175
checkpoint; these use changed viewport/blend programs and new test descriptors.

| Case | Terminal execution | Pixel result |
| --- | --- | --- |
|Rect additive R32|Both fences complete, header1/MMU0; immutable checks pass|Fails at byte64, pixel(16,0): initial/expected0x3e800000, actual0x5a5a5a5a|
|Cubic additive R32|Both fences complete, header1/MMU0; immutable checks pass|Same first incorrect byte64|
|Stroke half source-over|Both fences complete, header1/MMU0; immutable checks pass|Fails at byte7296, pixel(16,28): initial/expected half0x3400, actual0|
|Dynamic viewport blur|Vertex completes; fragment faults, pixels unevaluated|AS0fault0x0b0002c2 at VA0x0603e000|

The path mismatches are checked outside-geometry pixels with nonzero prior
destination values, not row padding. Masked-out elements count as automatic
matches in the printed totals; those totals must not be presented as independent
pixel-validation counts. Correct initial payload values, intended linear row
strides and SHA pins were verified. The exact path failure cause is unresolved.
Released Mesa26.2.4 v4 uses pan_preload_fb/textured preload tiler jobs; our direct
framebuffer preload interpretation therefore still needs validation before
blaming shader arithmetic or claiming destination preservation.

### Exact dynamic-fixture fault cause

Framebuffer PARAMETERS clear_color and color_load_address occupy overlapping
union bits. The fixture relocates its old load address0x04000000 to0x0203e000,
but retains clear_color_0=0x04000000 from pan_unpack. Repacking ORs the fields:

```
0x04000000 | 0x0203e000 = 0x0603e000
```

That exact value occurs in the published payload at offset0x380 and matches the
phone fault. This is proven for fixture relocation. Production emitters start
with fresh structures, so this particular stale-union defect is not established
there.

The fault leaves the shared hardware queue unavailable until reboot. However,
NativeQuery capability advertisement and supportsNativePrograms depend on the
boot opt-in, not queue health. The poisoned queue is a later execution blocker;
it does not by itself explain why the earlier pipeline factory returned nil.

## Next corrections

Preserve the real inactive attachment formats and write masks in profile
selection rather than discarding them or weakening exact matching. Add bounded
pipeline rejection logging for the actual function pair, formats/masks/blends,
vertex layout and rejection reason. Clear inactive union fields when relocating
the dynamic fixture, and implement/validate the released v4 preload path for
preserving prior destination pixels. Re-test changed GPU code before claiming
stock compositor execution.

The native compiler helper is still running in the saved window; no completed
compiler self-test is established. Other recorded warnings include absent SEP,
preboot/FactoryData paths, user-session setup, virtual random, logd privilege and
swap-file creation. None is identified as the immediate cause of the repeated
Metal pipeline abort. Raw logs, device identifiers, generated payloads and Apple
binaries remain outside Git. This review performs no build, flash or root update.
