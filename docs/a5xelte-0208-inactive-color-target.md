# 0208: supply downsample_8 color target 1

## Observed blocker

0207d backboardd requests `downsample_blur_vert_lph` / `downsample_8_frag_lph`
with RT1 format Invalid (0), default write mask All. The authenticated profile100
requires BGRA8 (80) for RT1, with write mask None (0), and emits one native pass
for logical target0. The exact format mismatch aborts pipeline construction.

## Implementation

- Try the existing exact authenticated selector first. Only the named pair,
  same-device/same-library functions, absent RT1 and default inactive blend state
  may use an internal descriptor copy with BGRA8/None. The selector rechecks
  constants, all other attachments, vertex layout, sample/depth/raster state.
  Require profile100, one pass and target0. The caller descriptor stays intact.
- For this route, retain a real caller RT1 when present. Otherwise allocate a
  private BGRA8 IOSurface-backed texture matching target0 dimensions, once per
  render encoder. Reject wrong formats, dimensions, devices and backing aliases.
- Query17 maps source, target0 and the auxiliary target. Validate exact returned
  identity, access, dimensions, row stride, format and subresource span. The
  runtime also rejects source/target/job overlap and invalid GPU spans.
- Submit18 includes all three tokens and mapping epoch, read mask7, write mask2.
  The auxiliary texture is captured by the queued block until its synchronous
  terminal fence. Only target0 is a writeback: RT1 remains disabled as required
  by the compiled shader contract. No CPU pixel generation is added.
- The existing exact profile99/other attachment routes remain unchanged.

This supplies the missing inactive target; it is **not general active MRT** or
proof that the iOS home screen now renders. Further format/state/shader
rejections remain explicit errors.

## Local evidence

The complete16-binary native render suite passes, including the new profile100
case using a real Mac IOSurface and the actual released-Mesa native emitter.
Only kernel transport is mocked. Checks cover caller descriptor immutability,
wrong format/mask/blend/layout/function/device rejection, internal allocation,
caller-provided RT1, three mapped tokens, read7/write2, invalid span/alias,
allocation failure, terminal-fence failure and resource release. The provider
also cross-compiles for ARM64 iOS/Cortex-A53 with warnings as errors.

The signed iOS bundle builds; actual kernel payload preflight passes. BOOT
packaging/install details are recorded after completion. Physical acceptance
and resulting UI behavior require the next phone run. The four failing0207d
pixel-suite cases have not been repaired by this attachment change.

## Runtime checkpoints

1. `pipeline: accepted profile=100 ... internal BGRA8 color1 writeMask=0`
2. `blur-query17`, `blur-inactive-color1`, `blur-emitter`, `blur-submit18`
   for profile100 with result0, followed by a genuine completed command buffer.
3. Inspect subsequent backboardd errors and visible UI separately. A successful
   query or matching result alone does not establish GPU-rendered UI progress.
