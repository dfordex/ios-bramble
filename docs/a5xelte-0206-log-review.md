# 0206 device log: dynamic compilation works; FramebufferFetch blocks the next stage

## Result and capture

The user reports a spinner advancing with pauses. Read-only TWRP recovery
obtains all1,369,061 recorded ring bytes at flush336,1,368,816 decoded bytes
and14,318 lines, without overwrite. Framebuffer metric intervals total
3,390,256ms (about56m30s); that sum is not an exact boot timestamp. No device
write, flash or reboot was performed during this review. Raw logs and complete
typed captures remain private, outside Git.

Verdict: dynamic compilation and admission made physical progress; visible
home-screen startup remains incomplete. The next observed graphics blocker is
an unimplemented rendering feature, not the old fixed specialization list.

## Evidence

Line numbers refer to the private decoded capture.

| Lines | Observation |
| --- | --- |
| 207–213 | Both dynamic-unknown A8 copy/source-over fixtures pass all4096 output bytes, guards and terminal fences. All27 cases pass. These embedded fixtures are distinct evidence from phone compilation below. |
| 288 | Installer completes19 files, sync0. |
| 5068,5204,5252,5394,5461,5586,5698 | Seven actual fragment stage publications:1120,896,1120,896,880,864 and3072 bytes. |
| 5586–5590 | The previously missing coord0/image17 stage publishes864B, is accepted by backboardd and creates a dynamic65536 pipeline. |
| 5698–5702 | A further3072B fragment publishes, is accepted and creates another dynamic65536 pipeline. Its capture changes image_function0 to0 and texture_function to20 decimal relative to the864B stage. |
| 5216–5221 | An older queued request fails actual AIR translation for unsupported FramebufferFetch; the worker restarts and publishes a terminal failure, then continues serving. |
| 5704–5895 | Backboardd forwards and waits on another complete58-constant request; two captured attempts are identical. Blend_function=41 decimal, dest_count=1, noise_scale/noise_tex enabled and noise_width=32. |
| 5898–5905 | AIR exits status512 (child exit2), wall4.911s. Exact error: unsupported FramebufferFetch at fixed_frag_lph_cph argument31/color attachment0. Required capabilities are RasterizationOrderColorAttachmentAccess, or FragmentShaderPixelInterlock together with FragmentStoresAndAtomics. |
| 5974–6063,10701–10789 | Two backboardd SIGABRTs, namespace13/code7, Metal fragment-specialization failure. First follows the captured FramebufferFetch rejection. |
| 4095–4144,7277–7332 | PosterBoard repeats the preferred0x1c1778268 state assertion; heap text includes `!_stateLock_switcherConfiguration`. |
| 9328–9382 | assetsd SIGABRT: NSInternalInconsistencyException, `assetsd requires TCCPhotosService access`. |
| 10793–10802,11510 | SpringBoard NSInvalidArgumentException/SIGABRT after setConfiguration fails with NSCocoaErrorDomain4099: its com.apple.AttentionAwareness XPC connection was interrupted and the additional proxy became invalid. |
| 14241 | Storage406,278 requests,8,586,776,064 read bytes,323,778,560 write bytes,0 errors. |

## What is established

- Previously unlisted shaders really compile on the phone and become Metal
  functions/pipelines. The additional3072B publication demonstrates the route
  proceeds beyond the specific864B host-tested request without another BOOT.
- The supported dynamic unknown-stage bytecode really executes on the GPU in
  the two embedded pixel tests. This does not establish GPU execution of every
  phone-published stage or a complete compositor frame.
- Bounded logs contain34 successful misc-submit18 records:602x17,603x3,604x1,
  605x13. Sixteen command buffers log Completed/error0. There is no recorded
  live65536 submission before the subsequent specialization abort. Dynamic
  pipeline acceptance must not be reported as a completed live dynamic draw.
- Eight4096-sample source/panel comparisons have zero RGB/alpha mismatches.
  No kernel panic or nonzero GPU MMU fault appears. The spinner alone did not
  identify the fault; actual compiler stderr now does.

## Remaining findings

### P1: FramebufferFetch semantics are not implemented end to end

The requested fragment needs to read the current destination pixel as part of
its shader computation. The translator correctly refuses the unavailable
ordered attachment-read/interlock capability. General function compilation
cannot supply a missing rendering operation. The next repair must implement
the actual attachment read, ordering and native resource/lowering path; merely
advertising a feature bit or returning successful compilation would be wrong.
The request also enables noise-related constants and precedes a256x1
RGBA16Float texture allocation; its full live resource contract must be
derived rather than guessed from those flags.

### P1: independent userland startup failures remain

PosterBoard's known state assertion persists. SpringBoard now supplies a
specific AttentionAwareness XPC configuration exception; the underlying
service failure is not established by this capture. assetsd separately aborts
for missing TCCPhotosService access. These need their own source/service-state
analysis; repairing the framebuffer-fetch stage alone does not prove that
home-screen startup will complete.

The next useful work is the real framebuffer-fetch translation/native path,
with ordered destination-read pixel tests, followed by investigation of the
identified service/state failures. No new image is prepared in this readout.
