# 0226 readout and 0227 packed vertex correction

## Why 0226 still failed

Complete SYSTEM flush58 recovers 783,675 bytes / 9,481 lines without ring
overwrite. The previous missing-UV check is passed, but the same compact
vertex/fragment pair now rejects color index3: actual Half4 offset8, expected
offset32 (lines 3709–3711). Backboardd aborts at line3713. SpringBoard separately
aborts after an AttentionAwareness connection/proxy exception at line3813.

The exact complete failed pipeline snapshot was recovered through bounded HFS
reads of the project's shader spool. It uses Float2 position at byte0, Half4
color at byte8, buffer1, stride16, per-vertex step/rate1. The 0226 tests varied
field presence but retained the legacy byte offsets and stride48. They did not
cover this actual packed descriptor. Thus the previous repair was incomplete.

The capture contains 68 Completed/error0 CB results, eight matching sampled
source/panel pixel comparisons, 75 touch and 386 HID key records. No recorded
kernel panic, MMU fault or failed import explains this pipeline abort. Later,
the next fragment reaches translator EXEC_OBSERVED but no compilation completion
is captured before recovery. Zero-swap intervals accompany that wait. These
facts do not establish responsive UI or complete graphics support.

## 0227 correction through the whole draw path

Dynamic pipeline profiles now carry the application's field offsets and stride,
while retaining reflected field semantics/formats and Metal index mapping.
The independent native gate checks required fields, ordered unique indices,
buffer1, format alignment, full field spans inside stride8..2048/aligned4, and
per-vertex step/rate1. Unsupported formats and bindings still reject.

The producer snapshot, indexed maximum-vertex bounds and native attribute
descriptors all use the same exact span:

```text
bytes = (vertex_count - 1) * stride + maximum_field_end
```

No dynamic draw retains a count*48 snapshot assumption. Legacy static profiles
keep their existing 48-byte contract. Old diagnostic readers that assume that
packing are excluded from dynamic draws to avoid reading past packed buffers.

The exact recovered descriptor is reconstructed and its entire serialized
descriptor compared with the capture. It passes the real cache/factory/emitter.
Both non-indexed and indexed production command buffers submit a 64-byte packed
vertex buffer through a mock native transport. Decoded GPU descriptors have
stride16, position0/color8 and the submitted vertex bytes match exactly. No
physical GPU execution is claimed by these host submissions.

Across four packing arrangements, all16 field masks, Float2/Float4, target80/43
and copy/source-over, real compact/single-UV/dual-UV stages pass 224 valid and
reject 1,312 missing-field combinations. Malformed alignment/bindings/formats,
extra fields, invalid strides and one-byte-short native spans reject. Existing
static602–606/dynamic format, blend/preload/bounds and untextured/fetch regression
tests pass. Tests that formerly treated every aligned repacking as invalid now
use genuinely unaligned or unsupported input shapes instead.

## Next captured fragment

The late pending function was compiled by the genuine Mac request worker into
2,464 native bytes. Reflection shows UV2 plus color4 inputs with zero sampled
images. The previous zero-texture heuristic incorrectly treated every such
fragment as color-only. Classification now checks actual reflected lanes and
uses an explicit no-textures/interpolants contract. Native submission clears
texture/sampler pointers and counts while retaining real UV/color varyings.
Resource/UBO and source authentication checks remain intact.

This genuine stage passes production cache/factory/native emission with a
compatible single-UV vertex across 64 valid / 448 rejected layout combinations.
The complete publication is included as the 30th persistent stage, avoiding its
first compilation wait on the next boot. Its physical pixels remain unverified.

## Build and installation

Actual installer preflight validates all367 files. Relative to0226, the signed
provider changes and three files for the new stage are added; prior29 stages,
compiler helpers, launchd cache and selected apps/metadata remain unchanged.
Full XNU make exits0. BOOT25,669,648 bytes, kernel25,002,656 bytes, provider963,760
bytes; 4 KiB signature pages, every embedded file and linked segment verify.
Loader/ADT/DTBH/arguments remain exact0226, with safe complete-FDT staging.

Guarded recovery/model/p10/capacity checks pass. Direct offset-zero write
acknowledges all25,669,648 bytes, sync succeeds and reboot is requested. No BOOT
backup/readback/full USERDATA transfer. The actual corrected pipeline, subsequent
shader pixels and responsive UI require the next device observation/capture.
AttentionAwareness resilience and any later failures are not claimed repaired.
