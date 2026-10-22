# 0198: normalized603 shader and actual SwapWait completion

This follows the [complete0197 readout](a5xelte-0197-log-review.md). The
colored603 input and its black output are separate from the overwritten
SwapEnd records; both boundaries are addressed in this trial.

## Shader and resources

- Compile the genuine603 fragment with normalized SamplerState word0. Compile
  words2/4/6 as well and require byte-identical output for every admitted
  nearest/linear min/mag combination. Pixel-coordinate samplers stay unsupported.
- The vertex remains2192bytes/reg8. The fragment changes976→880bytes/reg6→5;
  it consumes interpolated normalized UV directly. Remove the obsolete synthetic
  width/height UBO writes and assertions. Keep texture/sampler0 and the actual
  MetalTexture3 mapping.
- Change emitter, registry, phone compiler and loaded-cache native pins together.
  The old976-byte code is rejected rather than substituted into the new profile.
- The worker authenticates the exact old603 publication before atomically
  renaming its directory out of the request-ID path. Recompilation can resume
  after interruption; unknown publications are not replaced. Actual host
  old976→new880 publication and forced-exit/restart tests pass, alongside602
  and cache identity/owner/mode/symlink/lifetime regressions.
- Log at most eight actual603 CPU snapshot transforms: VB3float4, transformed
  UVbounds, finite-coordinate count and the sampler's normalize/min/mag/mip
  state. Bounds are checked against retained commit-time snapshots. This records
  the missing transform without changing vertex data or guessing an image.

## SwapWait protocol

Local iOS16 IOMFB disassembly sends selector6 three scalar inputs:
`[swapID, mode, timeoutMilliseconds]`. Its timed wrapper multiplies seconds
by1000 before integer conversion. Zero is the untimed form. Mode is preserved
and logged; no unverified interpretation of its bits is introduced.

Kernel patch0193 implements a bounded64-entry exact-ID state under the
framebuffer lock. SwapBegin allocates an ID. Overwriting an unshown pending
record marks that ID dropped and wakes waiters. Vsync completes its selected
ID only after `present` returns; waiting releases the lock atomically. The
client and framebuffer are retained while sleeping, and client close wakes
and aborts waits. A real deadline returns timeout.

Completed presentation requires every enabled nonzero external layer to be
copied; direct physical-panel aliases and zero-ID layers are handled explicitly.
Partial aggregate byte counts cannot make a failed multi-layer presentation
successful. Possibly active GPU DMA fails the completion. Dropped, failed,
unknown and timed-out IDs are distinct errors rather than unconditional success.

This does not force a new surface into a client's request, discard surface1,
change the mailbox to a FIFO, or strip unknown SwapEnd mask bits. Whether the
real caller waits between its surface23 and surface1 records will be visible
in the new bounded SwapWait log;0197 did not prove that ordering.

## Local checks and next device evidence

- Full native Metal/resource/transport suite passes with the new26-profile
  registry, including real603 buffer-backed texture snapshots. These use mocked
  transport and do not establish GPU pixel correctness.
- Production Cortex-A53 iOS provider compilation and4KiB signature checks pass.
- Source-extracted swap state tests exercise wait-before/after-completion,
  finite timeout, terminal drop preservation, DMA failure and bounded history
  under ASan/UBSan. Host condition variables exercise the state predicate;
  this is not an IOKit emulation or a phone call-sequence test.
- Patch0193 exactly reproduces the staged framebuffer source. The complete
  XNU build including symbols passes with the new SwapWait implementation.
- The final15-file payload passes the actual kernel installer preflight over
  all39,515,958raw/9,450,154packed bytes. The final full XNU build including
  this payload passes. BOOT is30,308,368bytes, within the32MiB p10 boundary.

The next phone capture must establish transformed UVs, nonblack603 target
pixels, actual SwapWait calls and a completed source-to-panel presentation.
Visible iOS output is still required before claiming the black screen fixed.
