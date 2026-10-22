# 0189: new textured fragment specialization blocks command-buffer commit

## Complete capture

Read-only SYSTEM capture: flush58,204,255 recorded/recovered bytes,2,711 lines,
204,010 decoded text bytes, no overwritten history. No device writes, new
build or flash during this readout. Raw log and extracted constant captures
remain private.

## Installed fixes and observed boundaries

- Lines234-260: actual15-file preflight succeeds; provider614,032 bytes and
  patched translator14,391,888 bytes written; complete files15/sync0.
- Lines1013-1016: existing fragment601 and vertex602 specialize successfully;
  complete actual602 BGRA8/copy/packing0 pipeline is accepted.
- No unrecognized-selector exception is recorded in this boot. However there
  is also no indexed-submission marker, command-buffer commit, native phase,
  Query17 or Submit18. Indexed GPU execution is therefore still unverified.
- Line189: all21 independent GPU test cases pass;44 terminal fences have
  header1/MMU0. They are private regression jobs, not live compositor work.
- 114 framebuffer windows total606,306ms, all swaps/shown/presentation bytes0.

## Exact current crash: unsupported textured fragment constants

Lines1018-1020 show a new194x237 BGRA IOSurface, then a new request for the
same function name `fixed_frag_lph_cph`. It is a distinct specialization.
Both full58-entry named constant captures at1021-1080 and1083-1142 match by
name, type and bytes; indexed constant arrays are empty. Compared with the
accepted601/602 fragment contract, exactly these six values change0→1:

| Constant | Metal type | First evidence line |
| --- | --- | --- |
| fc_has_image_0A | Bool53 |1055|
| fc_has_lod_bias | Bool53 |1061|
| fc_image_count | UChar49 |1067|
| fc_plane_count0 | UChar49 |1073|
| fc_texcoord_count0 | UChar49 |1075|
| fc_texture_function | UChar49 |1077|

All other52 constants match, including fc_attachment_count1,
fc_blend_function54 and fc_framebuffer_fetch1. This requests an image/UV/LOD
variant, whereas the current accepted specialization has no image. The source
`newFunctionWithName:constantValues:error:` strictly matches the complete
constant set and returns nil for this new variant. QuartzCore then terminates
with namespace13/code7: `Metal failed to specialize fragment function`.

There are26 backboardd signal6 crashes, all with this same reason and identical
ten-entry backtrace. First reason at1172; last at2680. No kernel panic or
GPU/MMU fault is recorded. The command buffer has not committed, so there is
no evidence that GPU rendering finished and only presentation was missing.

The new function request is queued at1019 and deduplicated at1081:
`a9111f2823b0d8fad01d6e3da6b2083e23d917855c11ad30dd83a679ad991b4e`.
All17 receipt lines represent16 unique requests: one newly queued,16 already
present/deduplicated. Request delivery is observed; completion is not.

## Additional concrete buffer gap

Line1017 rejects `newBufferWithBytesNoCopy` with length200,704/options0.
The source intentionally returns nil for this selector. This is separate from
specialization: it is not the recorded fatal reason, but it is an observed
resource request that must be handled for the upcoming draws. Implement true
retained external memory and the deallocator lifetime, with commit-time reads;
a one-time copy would lose the requested shared-buffer semantics.

## On-phone compiler now advances, but does not publish

- One service starts at763 with no_time_limit1.
- Corrected translator/validator are authorized at862/864.
- Line1330: metal2vulkan status0, wall55.598s, CPU0.467s, peak9,572,352bytes.
  The previous unrecognized --no-timeout option error is absent.
- Legacy midgard-compile starts afterward and remains RUNNING through line2700
  (wall321.6s). No terminal success/error is recorded before recovery.
- No PUBLISHED or cache-bound result exists in the capture.

Source main runs both legacy read_surf/downsample_4 selftests before a5Serve
scans requests. Moreover a5Known602 only accepts the exact known602 pipeline;
it does not compile arbitrary new fragment-only specializations. Therefore
waiting for the baseline job alone cannot add this textured variant. Current
on-phone evidence proves successful AIR-stage execution, not automatic shader
publication or live pipeline binding.

## Next implementation targets

1. Compile the exact captured textured fragment with a compatible real vertex
   variant; reflect its image/sampler/uniform/LOD ABI and implement that binding
   contract in the native emitter and Metal profile. The pairing/vertex/target
   state for this new pipeline is not yet observed because fragment creation
   fails first; do not relabel the no-image602 bytes as this specialization.
2. Add genuine shared no-copy buffer ownership/read semantics and deallocator
   lifetime. Keep unsupported storage modes explicit.
3. Let actual requests be processed independently of slow startup selftests,
   then extend the worker/cache contract to the verified textured family.
4. Verify actual indexed/native submit and fences, then presentation and
   backboardd survival on the device. The prior missing-selector crash is gone
   but full indexed execution has not reached a visible receipt.
