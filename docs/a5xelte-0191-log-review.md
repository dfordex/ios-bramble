# 0191: textured shaders accepted; source-over pipeline contract rejected

## Verdict

FAIL for live compositor submission. The actual603 vertex/fragment pairing now
specializes successfully. The fatal condition is the pipeline's premultiplied
source-over blend state, which the current603 profile only admits as copy.
The compiler status-directory restart defect is absent. A separate too-strict
linear image-stride check also rejects the incoming buffer texture.

## Complete capture

Read-only SYSTEM recovery: flush31; all161,028 recorded bytes recovered, no
overwrite; decoded160,783bytes/1,631lines. Raw log stays private. No device
writes or reboot during this readout.

| Recovered log lines | Evidence |
| --- | --- |
|230-259|Updated649,520-byte provider and127,856-byte runner; installercomplete16/sync0.|
|189|All21 independent GPU cases pass;44 terminal fences header1/MMU0.|
|992-995|Old601fragment/602vertex and complete602pipeline still accepted.|
|996,1177|Linear texture rejected for image stride: BGRA8,194x237,row832,image197128,buffer200704,offset0,Shared/ShaderRead.|
|997|iOS subsequently creates a194x237 IOSurface fallback. The rejected linear view alone is not the fatal exception.|
|998-999,1179-1180|Actual textured603 fragment and matching603 vertex both accepted.|
|1001-1002,1182-1185|Pipeline rejects attachment0.blendEnabled actual1 expected0. Live RT0 BGRA8/allchannels uses ADD,sourceONE,destinationONE_MINUS_SOURCE_ALPHA for RGB and alpha.|
|1003-1571|Seven backboardd signal6 crashes, one identical ten-frame backtrace; all reasons namespace13/code4, Metal failed to build render pipeline.|
|760-1618|One compiler service start; six unsupported requests recorded, then real metal2vulkan/spirv-val authorized; AIR stage still RUNNING through90.4s. No FAILED/status-directory error/restart/publication/cache-bound.|

## P1: actual premultiplied source-over needs a real native contract

The old candidate vertex constants are now observed to specialize on the
phone. The full603 pipeline contract was previously a checked copy candidate;
iOS requests blending enabled instead. The immediate rejection is therefore
an attachment-state mismatch, not a shader compiler failure or GPU/MMU fault.

The registry currently has one copy-only603 attachment contract. The native
emitter additionally requires603 flags0/copy-only state and explicitly rejects
non-copy generic textured draws. Repair both the exact attachment contract
and executable native blending route, retaining the requested destination
content/preload and real source-over equation. Merely suppressing the factory
error would move failure to the emitter. Test nonzero source/destination and
alpha, plus unsupported blend factors, before calling it implemented.

No stock command-buffer commit/native phase/Query17/Submit18 appears. All64
framebuffer windows (340,381ms total) have zero swaps/shown/presentationbytes.
Thus the GPU has not completed a hidden stock frame awaiting presentation.

## P1: bytesPerImage describes the final active byte, not padded row footprint

For the actual request:

- Row832, width194*4=776 active bytes, height237.
- Minimal active span=(237-1)*832+776=197128 bytes, exactly the incoming image.
- Padded row footprint=237*832=197184 bytes; backing buffer200704 fits both.

The current factory incorrectly requires bytesPerImage>=row*height and64-byte
image-stride alignment. This rejects a valid final-row-trimmed source. Keep
row/offset alignment and overflow/backing checks; validate the declared image
against the final active byte. The internal GPU view can still use the padded
footprint when it fits the actual backing. Cover this exact194x237 request and
short/overflow neighbors in regression tests.

## Compiler result and limits

Status-directory repair is observed: multiple unsupported requests no longer
kill/restart the service. Unsupported here means the automatic worker's exact
602/603 recipe coverage excludes those other queued families, including some
already available embedded shader families. It does not mean all embedded
pipelines are rejected.

The later AIR job has neither a success nor failure result before TWRP. It
must not be called a successful phone compilation/publication yet. The
source-over pipeline rejection is independent of waiting for this job: the
existing admission/emitter contract does not permit the incoming blend state.

No unrecognized-selector crash, kernel panic or other process crash report is
recorded. Next changes are the real603 source-over path and corrected linear
image-span validation; then verify live commit, native fences and pixels.
