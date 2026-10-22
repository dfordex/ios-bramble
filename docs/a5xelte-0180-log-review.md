# 0180 recovered log review — 2026-10-22

Read-only SYSTEM recovery: flush30,100963raw bytes,1226decoded lines; no ring
wrap. Entire capture reviewed. Raw logs, binaries and device identifiers remain
private. No partitions were written during this readout.

## Physical GPU results

All21cases evaluated/pass/immutable1: the seven previous cases, all nine typed
resource copies and all five BGRA mip reductions. Captured1D widths3072/4096,
BGR5A1 raw copy and odd/single-axis mip shapes pass their pinned comparisons.
All48logged GPU fences complete with header1/MMU0, including presentation.
This verifies actual T720 pixels for these cases, not general compositor coverage.
Compiler cache verification records GREEN LINE/DONE; this line is a CPU-drawn
status marker and is not evidence of a rendered iOS frame.

## Stock resource setup advances

The installed501648-byte provider is confirmed by the installer receipt.
Backboardd loads it, initializes the device and creates queues and command
buffer1. The previously rejected requests now produce actual surfaces:
776x33physical mip atlases for776x24logical BGRA mip textures; BGR5A1; R16Uint
3072x1, R16Float4096x1, R32Float1024/4096x1 and RG32Float1024x1. No texture,
sampler or buffer creation rejection is recorded. Fourteen pipeline factory
calls across twelve profiles are accepted. The probe records STOCK DEVICE
ACCEPTED. AGXAccelerator matching0 remains an Apple-class lookup, not evidence
that the Mali provider failed discovery.

Command buffer1's first encoding error has changed from renderpass Unsupported
to BadArgument/e00002c2 at the full copyFromTexture:sourceSlice:sourceLevel:
sourceOrigin:sourceSize:toTexture:destinationSlice:destinationLevel:
destinationOrigin: selector. No commit, resource-op Query17/emitter/Submit18
or stock native completion is recorded. This is not an observed GPU job timeout.

## Exact remaining uncertainty

The log records the selector/error but not its source/destination descriptor,
levels, origins or rejection branch. Existing guards include object/device and
backing identity, slice/format agreement, dimensions/bounds and same-allocation
level-window overlap. It is not possible to identify the exact rejected guard
from this capture alone.

Static QuartzCore warmup disassembly at18847f2f8..18847f34c selects source and
destination from the same two textures in four combinations. Its first
combination selects the same texture for both. The current resource encoder
rejects any overlapping whole-level byte windows, even for distinct rectangles.
That is a concrete compatibility gap and a candidate for this error; runtime
arguments are not captured, so this is not a proven callsite attribution.
The776x24 command buffer also matches the known warmup flow which never commits.
Its first error must not be called the sole UI stopping cause. Resource support
has advanced, but a subsequent stock submission has not been established.

## Presentation and continuing activity

The independent final-transfer path copies full-panel IOSurface19 to the panel:
fences47/48,shown1,GPU8294400bytes,CPU0. That establishes a surface-to-panel GPU
transfer, not that the UI was rendered into that surface. No full-frame pixel
readback is available. The user reports black plus the green status line.
Across61measurement windows (325329ms summed intervals), swaps total5/shown3.
One backboardd and one SpringBoard execution are recorded; no CRASH or kernel
panic. Later daemons, SpringBoard IOKit requests and three physical key events
continue. Thus the whole kernel did not stop at the last visible console line.
Repeated fairplayd.H2/xpcproxy starts and later securityd AKS selector10
Unsupported responses remain separate observed service issues; this capture
does not establish them as the missing compositor frame's cause.

## Next code boundary

Implement correct same-texture subregion-copy semantics (disjoint rectangles
and safe temporary GPU backing where source/destination hazards require it),
with precise bounded rejection metadata. Keep actual fences, mip layouts,
permissions and retained lifetimes intact. Preserve all21passing oracles.
Then distinguish warmup-only work from a genuine submitted compositor command
before claiming native iOS UI rendering.
