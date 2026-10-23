# 0206: compile and bind previously unlisted QuartzCore shader stages

## Scope

0205's first backboardd abort followed a coord0/image17 specialization absent
from the fixed602–606 list.0206 adds a real dynamic stage path instead of a607
recipe. The source remains the locally installed, identified QuartzCore
metallib and the target remains the actual T720. An unknown typed specialization
can now be translated, compiled, published, loaded and submitted without
adding its constants or module fingerprint to the driver.

This is not universal Metal support. Execution still requires a resource,
varying and render-state ABI implemented by the native emitter. New memory
operations, depth/MRT/compute, unsupported system values or texture interfaces
receive errors. PosterBoard's separate switcher-state assertion is unchanged.

## End-to-end implementation

1. The provider forwards the complete typed single-function request. Known
   static specializations retain their fast path. A cache miss in the enabled
   dynamic path waits for actual code or a terminal compiler failure, without
   holding provider resource locks or returning a placeholder function. There
   is no fixed compile time limit.
2. The worker validates source, stage, constants, caller ownership and request
   identity. It supports standalone vertex and fragment requests, including
   newly eligible old unsupported requests; genuine failures are preserved.
   The current AIR tool requires a render-pair translation scaffold. Only the
   requested native stage is published; the companion is not declared to be
   the application's actual linked shader.
3. The new Midgard dynamic CLI consumes validated SPIR-V plus an ABI manifest
   derived from translator reflection. It has no native-module allowlist.
   Actual optimized-NIR reads determine live UBO extents, texture indices and
   input/output lanes. Unimplemented storage/system operations and hardware
   limits reject before publication. Known602–606 compilation remains intact.
4. Schema2 root publications contain stage code, semantic reflection and native
   metadata bound to the exact typed function request. The loader checks
   identity, digests, bounds, ownership, file modes and link behavior, then owns
   immutable code/resource arrays. A failed compilation produces an accessible
   terminal receipt so the synchronous provider stops waiting with an error.
5. Dynamic functions are genuine provider instances retaining their stage
   owner. Pipeline composition validates actual stage IO, supported float2D
   texture/sampler semantics, original QC vertex packing and actual Metal
   descriptor. Linked functions and unsupported descriptor features reject.
   Known and dynamic stages can be combined; each stage's own bindings are
   retained and dead buffers/push offsets are removed.
6. The emitter admits the supported reflected ABI rather than shader hashes:
   uniform buffers, Texture3/Sampler0, UV and optional color varying, BGRA
   output, copy/source-over, supported viewport/index/scissor behavior. It
   independently validates the complete resource graph, table bounds and
   attachment contract. Kernelpatch0201 adds the stable generic wire identity
   65536, retaining mapped-resource, partition and job-chain checks.

The initial executable dynamic ABI is the existing QC textured packing:
Metal attributes0/1/3 map to native position/UV/color slots0/1/2; position,
point-size and UV/color output lanes must match the emitter. Uniform access
must be bounded, with no TLS/WLS or live storage side effects. This accepts
previously unlisted variants sharing supported semantics, not arbitrary new
resource features merely because they compiled.

## Verified host/package evidence

| Check | Result |
| --- | --- |
| Actual previously unlisted coord0/image17 | AIR translation, SPIR-V validation, dynamic Midgard compilation and publication pass;864B fragment, distinct from606's896B code. No new fixed profile is registered. |
| Standalone vertex | Real2192B vertex compilation/publication and loader pass. |
| Backend | Four real stage cases,11 malformed/resource manifest negatives, an actual modified SPIR-V reading unsupported UBO0 space, and known pair byte identity pass. |
| Worker | Typed-stage request handling, eligible unsupported retry, invalid identity/constants and real nonexistent-function failure/restart publication pass. iOS Cortex-A53 Werror passes. |
| Stage loader | Actual unlisted publication loads; ASan/UBSan ownership, mode, link, corruption, bounds and lifetime tests pass. Overlapping compatible varying reads are retained, changed bases rejected. |
| Metal and submission | Real publication to provider function, pipeline, resource snapshots, Query17/Submit18 and fences passes copy/source-over/SPI and error cases. Both known VS + dynamic FS and dynamic VS + dynamic FS pass. These use mock transport and do not establish device pixels. |
| Admission negatives | Linked functions, changed original vertex packing, writable resources, out-of-range UBO tables and unsupported profile flags reject. |
| Regression | Full prior native transport suite and non-registry resource/linear-buffer tests pass; production Cortex-A53 provider builds and signatures verify. |
| Compiler package | Current dynamic runner/backend, six retained recipes and five signed executables pass provenance/signature/4KiB page checks; dynamic helper hashes are included in provenance. |

## Device image

Preserve the existing25 GPU cases byte-identically and append two real dynamic
fixtures. The fixtures load the actual root-published864B shader through the
production Metal API, produce profile65536 through real composition, and use
the production emitter. They check the dead FB1/live4-byte FB2 contract and
provide independent full4096-byte asymmetric A8 copy/source-over pixel oracles.
Targets start poisoned or with a known preload; the CPU does not render them.
Total27 cases are embedded; the two new physical results remain pending.

The final19-file payload is39,733,216 raw/9,514,601 packed bytes. Actual kernel
preflight, exact zero-fuzz patch reproduction, repository validation and full
XNU make pass. BOOT is30,459,920 bytes, within33,554,432-byte p10. Tested four
CPUs, touch, orientation, logging and0204 storage batching remain in place.

On first use, a new shader can take minutes on the A53. Look for `STAGE
PUBLISHED` and provider dynamic acceptance before concluding compilation has
finished. Successful compile is separate from pipeline admission, GPU pixels
and visible iOS progress. Recover the next SYSTEM log to check all four.

## Installation

Source `08efcbb` was pushed before flashing. Exact recovery/model/TWRP, BOOTp10
mapping and33,554,432-byte capacity checks passed. Direct streaming acknowledged
30,459,920 bytes; sync completed and reboot was requested. No BOOT backup,
post-write hash/readback, formatting or whole USERDATA transfer was performed.
Device-stage publication, native compositor receipts, new physical pixels and
visible UI remain pending.
