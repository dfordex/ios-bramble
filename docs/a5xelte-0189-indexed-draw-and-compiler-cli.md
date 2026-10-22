# 0189: indexed QuartzCore draw and compiler CLI compatibility

## Evidence addressed

0188b installed the new payload and accepted the actual specialized vertex602,
fragment601 and complete BGRA8/copy/packing0 pipeline. Backboardd then aborted
on its first `drawIndexedPrimitives:indexCount:indexType:indexBuffer:indexBufferOffset:`
call. The automatic compiler runner separately exited before scanning requests:
its packaged translator rejected `--no-timeout`.

## Implementation

- Implemented the public indexed selector and its instance/base overloads for
  authenticated profile602. UInt16/UInt32 indices, triangle/triangle-strip,
  one instance, baseVertex0/baseInstance0; unsupported state is an explicit
  command-buffer error. Limits:256 referenced vertices and1536 indices per draw.
- Retain actual index and vertex bindings at encode time; read their contents
  at commit. Nonzero Metal index offsets are applied exactly once. Validate
  every index and the resulting vertex byte window. Private index buffers use
  the existing ReadBuffer15 transport while the connection lock is held,
  avoiding recursive lock acquisition and public transfer-lock inversion.
- Copy the immutable index snapshot into the mapped job arena. Set real v4
  PRIMITIVE index_type, indices and index_count, then execute genuine vertex,
  tiler and fragment jobs with Query17/Submit18 and terminal fences. No CPU
  rasterization or fabricated completion is introduced. Compute vertices0..max
  with base0, retaining index order; degenerate indexed triangles are valid.
- Compared with released Mesa26.2.4 Panfrost: pan_cmdstream.c3382-3395 derives
  the indexed vertex range; pan_jm.c737-755 sets PRIMITIVE index fields;
  pan_jm.c839-850,954-978,1008-1027 use the vertex-count invocation template
  for both vertex and tiler. Our bounded zero-based range may run unused
  earlier vertices, without changing referenced vertex identities.
- Retain the pipeline/cache owner through synchronous submission and fence,
  so cached native shader bytes outlive encoder release.
- Package the existing pinned no-timeout patched translator instead of the
  incompatible optimized binary. Packaging validates the exact source/patch
  manifest, host+iOS artifact identity and paired host CLI option. Provenance
  metadata stays outside the exact phone payload member list. Validation is
  unchanged; there is no compile deadline. Existing automatic compilation is
  still restricted to the verified602 contract; other requests stay explicit.

## Local verification

- Full native Metal API harness passes, including the new indexed602 test.
  Real shader registry, actual v4 descriptor emitter and mocked kernel transport:
  u16/u32 order, offsets, late writes, rebinding/lifetime, three overloads,
  256/1536 boundaries, malformed/bounds/device/state rejection, private buffer
  reads and failure, terminal/error fences. A timed asynchronous private-buffer
  test checks that commit does not deadlock. These are not GPU pixel results.
- Released-descriptor C tests include indexed u16/u32 and degenerate triangles;
  rejected input clears the output. Cortex-A53/iOS16 Werror production build
  and4096-byte signature-page validation pass.
- Actual patched host compiler pair accepts the exact602 request and publishes
  validated VS/FS output. Packaging tests reject missing/mismatched patch proof,
  wrong host/iOS bytes and missing CLI option, including the previous binary.
- Actual staged kernel installer preflight passes all15 payload streams:
  39,375,426 raw /9,409,248 packed bytes. Existing bounds are sufficient.
- Full XNU make including symbol sets exits0. BOOT is30,257,168 bytes,
  fitting the existing32MiB BOOTp10. Provider614,032 bytes; runner127,664;
  corrected translator14,391,888. Existing HFS applications/root are retained.

## Device evidence still required

Confirm installer complete15/sync0; accepted602 followed by `Metal indexed`,
commit and misc-query17/emitter/submit18 results and terminal fences. Check
backboardd crash reason, framebuffer swaps and actual displayed output. For
phone compilation check PUBLISHED/cache-bound after the legacy selftests finish.
Host tests, matching and private GPU fixtures do not establish successful live
compositing or a functioning on-phone compiler service.

## Installation

Implementation `fe9943a` was pushed to GitHub, then explicit Mac ADB rechecked
A5XELTE/TWRP3.3.0-0 and BOOTp10/capacity. Direct streaming acknowledged
30,257,168 bytes; sync completed and reboot was requested. No BOOT backup,
post-write hash/readback or whole root image transfer. Runtime remains pending.
