# 0234 full runtime readout and0235 source follow-up

## What ran on the phone

The complete unwrapped SYSTEM ring recovers787,706 bytes/9,180 lines.
Installer receipts confirm the new999,360-byte provider and182,912-byte worker.
All106 recorded GPU fences complete with zero nonzero MMU status fields.
There are no recorded process crashes or kernel panics. Of222 framebuffer
measurement intervals185 have no swaps; the highest interval reports3.3fps.
Those counters describe this run, not a sustained frame-rate guarantee.

Two compiler publication markers explicitly record new1136/1376-byte fixed
fragments, followed by actual provider acceptance. Other dynamic stages are
accepted from cache; a bounded private read additionally verifies a newly
published1936-byte stage. These are genuine native programs, not proof of a
complete or responsive UI.

## Three concrete blockers

1. **Software command-list capacity.** All19 rejected command buffers have
   exactly64 queued draws+clear operations. Examples include54draws+10clears,
   58+6 and51+13. The private command list rejects its65th operation in all
   five enqueue APIs. That explains indexed draw rejections without a resource
   mismatch and render-encoder rejections when another clear exceeds the cap.
   Some of these buffers also contain independently unsupported line draws;
   removing the queue limit alone does not make those frames valid.
2. **Line primitives and geometry bounds.**36 explicit nonindexed rejections
   use Metal primitive1 (lines), with counts including164/176/186/196/312/330.
   The provider and native emitter currently allow triangles/triangle strips
   only. Counts above256 also exceed the existing vertex workspace contract.
   The one recorded primitive3/count6 rejection occurs after queue saturation.
   No unsupported line is silently converted to a triangle or discarded.
3. **Plain variable-blur translation and terminal delivery.** Backboardd now
   forwards `variable_blur_downsample_frag_lph`, with no function constants,
   rather than aborting immediately at plain-function lookup. Its private
   worker status is failed, while the public publication is absent and
   backboardd keeps reporting waiting. Replaying that exact request against
   the actual current translator on Mac reproduces `UnmatchedVarying` with
   the fixed translation companion. The shader needs a compatible companion
   interface; ordinary discovery/forwarding is no longer the immediate gap.

##0235 source changes, not installed

- Replace the arbitrary64-operation software list cap with one shared4096
  operation retention bound across all five enqueue paths. Kernel ioctl batch
  limits and the ordered per-job submission/fence path are unchanged.
- Retain the validated active dynamic request during real compilation. If the
  compiler/validator fails, atomically publish its existing typed failed-stage
  receipt before the worker exits, in addition to its private status. It
  contains no native program and does not pretend the shader succeeded.
- Preserve that actual terminal error through plain-name, nil-constant and
  descriptor library calls. Previously the wrapper replaced it with the
  generic `function is not compiled` error.

Verification:

- The actual software command list accepts96 and4096 mocked native operations,
  preserves order/nonzero fence ordering, rejects4097, releases captures after
  completion and rejects a second commit. This is **mocked GPU** coverage.
- The actual phone variable-blur request fails real AIR translation on Mac;
  the modified worker exits1 only after both private status and public failure
  receipt exist. There is no native file in that publication.
- The production Metal descriptor API consumes that genuine failed publication
  immediately and preserves ENOTSUP and the compiler reason. No fake shader,
  GPU transport call or successful function is created.
- The real288-byte plain-fragment positive publication still loads via name,
  descriptor and empty constants. Asynchronous library contracts still pass.

Line rendering, geometry larger than the native workspace, and a correct
variable-blur companion remain unimplemented here. The current phone remains
on0234; this readout/source follow-up performs no device writes and prepares
no new BOOT image. Raw logs, actual request/publication files and Apple inputs
remain private.
