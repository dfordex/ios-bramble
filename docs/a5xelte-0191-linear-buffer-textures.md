# 0191: linear buffer textures and compiler status restart repair

## Implementation

The public `newTextureWithDescriptor:offset:bytesPerRow:` and actual iOS
`newLinearTextureWithDescriptor:offset:bytesPerRow:bytesPerImage:` now share a
real retained buffer-backed texture implementation. Shared/no-copy storage is
aliased; view creation neither allocates a blank IOSurface nor copies pixels.
CPU get/replace accesses the original buffer with the requested row stride and
offset. Descriptor values are copied and the texture retains the buffer, so
the no-copy deallocator cannot run before the view and its queued work release
ownership.

The checked contract is single-level, single-slice Shared ShaderRead 1D/2D,
using the nine already supported typed formats. Offset and row alignment are
64 bytes, matching the device's advertised minimum; row/image/size overflow
and backing bounds are checked. Unsupported GPU-writable/private/mipmap
aliases fail explicitly. Bounded accept/reject metadata identifies the actual
incoming descriptor and strides during the next phone trial.

Native miscellaneous/textured rendering accepts these source views. Under
the command buffer's commit lock it reads the current parent bytes, uploads a
real temporary native buffer through Create8/BulkWrite19, queries its actual
GPU mapping and builds the texture descriptor from bufferVA+viewOffset and
the actual row stride. Submit18 marks this buffer for reads instead of
inventing a surface token. Normal render targets remain real mapped surfaces.
Temporary GPU buffers follow the existing completion/error release policy;
failed releases retain ownership rather than claiming an unsafe free.

This implements a sampled source path. GPU-writable buffer-texture aliases
and every blit/renderer family are not advertised as supported. The actual
603 vertex/pipeline pairing still needs the next recovered phone evidence.

## Compiler repair

The status directory uses idempotent POSIX mkdir followed by a no-follow
open and real-directory/root-owner/exact0700 validation. An existing valid
directory is accepted. Status file creation uses directory-relative exclusive
no-follow opens, owner/type/link/mode checks for existing files, complete writes
and synchronization. Filesystem failure reports directly and exits, avoiding
recursive failure-status recording. The service can process later requests
and restart with its existing status directory.

## Verification

- Resources/no-copy/linear-view tests pass: nine formats, both selectors,
  1D/2D, offsets/padded rows, external late writes, CPU subregions, descriptor
  ownership, once-only deallocator lifetime and invalid states/bounds.
- Full native API harness passes, including existing rendering families and
  the new actual603 buffer-texture path. The dedicated test verifies no-copy
  data changed after encoding, full commit-time upload over two bulk chunks,
  Query17 buffer mapping, real shader descriptor address+offset, Submit18
  read-buffer mask, terminal fences and upload/query/submit failure cleanup.
- Worker host test processes two unsupported requests, compiles/publishes
  the genuine603 shader pair and stays alive across restart. Symlink,
  non-directory and wrong-mode status paths are rejected.
- Production Cortex-A53/iOS16 provider and runner compile with warnings as
  errors; 4KiB signature-page validation passes.
- Actual staged kernel preflight accepts all16files and streams:
  39,425,008 raw /9,421,365 packed bytes. Existing payload limits suffice.
- Fresh XNU make completes including dSYM, CTF and symbol sets. BOOT is
  30,273,552 bytes, within the32MiB partition capacity; provider649,520 bytes,
  runner127,856 bytes. Existing21GPU oracle jobs and root/apps are retained.

The API transport tests mock hardware. They prove resource/descriptor/control
flow, not physical T720 pixels or stock backboardd success. Device installation
and runtime evidence are recorded separately in A5XELTE_PROGRESS.md.
