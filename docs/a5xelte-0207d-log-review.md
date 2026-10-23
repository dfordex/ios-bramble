# 0207d device log review

## Verdict: partial rendering progress; compositor still aborts

Read-only SYSTEM recovery obtains flush156 and all1,197,230recorded ring bytes;
decoded text is1,196,985bytes/12,065lines. No oldest data was overwritten.
The new kernel reaches userland, all four CPUs initialize with SGI1 verified,
and the19-file installer completes with sync0. No new device write or reboot
was performed during this review. The earlier Samsung-logo reset is absent;
no kernel panic or nonzero logged GPU MMU fault appears in this capture.

## Physical GPU suite:27/31 pass

All31cases complete terminal vertex/fragment fences with status0, header1,
MMU0 and immutable guards intact. Pixel agreement fails in four cases:

| Case | Result |
| --- | --- |
|runtime_raw204_inline_source_over_nonzero|2368/4096 elements; first_bad514, actual0x3000/expected0x3500|
|runtime_r8_partial_scissor_source_over_nonzero|864/1024; first_bad264, actual0xc0/expected0x40|
|ordered_fetch_noise_full_target|1024/4096; first_bad0, actual0x28/expected0x20|
|ordered_fetch_noise_same_job_overlap|1024/4096; same first mismatch|

The two plain ordered-fetch cases, including overlapping draws in one job,
pass all4096bytes at tolerance1. This is physical proof for those contracts;
the noise/FragCoord/immutable second-texture contract is not correct yet.
The first two failures are reconstructed older fixtures. Their original private
payload hashes were unavailable, so a production regression cannot yet be
distinguished from a restoration/oracle mismatch. Neither failure is waived.
Relevant evidence: loglines123–128,215–229.

## Phone compiler and actual Metal acceptance

Supportgeneration2 retires/retries the old fetch failures and publishes four
real fragment stages:2720,2448,4672and912bytes. The exact prior4672-byte
framebuffer-fetch request is published atline5880, loaded by backboardd at6106
and accepted into a dynamic65536pipeline at6107. The former compiler capability
rejection is therefore passed on the phone. No live dynamic65536 submission
appears before the subsequent compositor abort; pipeline acceptance must not
be reported as completed fetch rendering by backboardd.

The first AIR translation takes777.906wallseconds but13.925CPUseconds; its
backend takes21.894wall/10.701CPU. Subsequent AIR/backend stages complete in
10–30wallseconds each. The long initial wall time is not evidence of equivalent
CPU computation. Three later requests terminate UNSUPPORTED, without a detailed
reason in this console capture. Their publication files remain to be inspected.

## Confirmed next compositor blocker

Five backboardd SIGABRTs report namespace13/code4:
`Metal failed to build render pipeline`.

The first exact rejected request immediately precedes the first abort at
lines6110–6115:

- Vertex: `downsample_blur_vert_lph`.
- Fragment: `downsample_8_frag_lph`.
- Profile100 gate: `attachment1.pixelFormat actual=0 expected=80`.
- iOS has attachment1 disabled; the authenticated profile requires BGRA8Unorm80.

Later heap captures repeat this same rejection family. This is a concrete
render-target contract mismatch, not the earlier fragment-specialization
failure. The correct next change must establish a real single-target shader/
resource contract or support optional inactive output semantics; blindly
ignoring the check is not an implementation of that rendering behavior.

## Working live drawing and presentation

The bounded detailed log contains36successful miscellaneous Submit18 calls,
19command-buffer completions(status4/error0) and19completed callback sequences.
Detailed native records cover profiles602,603and605 plus clears; later detailed
records are budget-limited. Eight4096sample panel/source checks have zero RGB
or alpha mismatches. Framebuffer metric windows later show roughly13–17shown
frames/second during active periods, with GPU presentation active. These may
be repeated spinner frames; they do not establish a working home screen.

296framebuffer metric windows sum1,588,063ms(about26m28s) of interval coverage.
Final storage counters:340,663requests,7,132,964,864read bytes,
266,695,680write bytes,0errors. This is not a matched throughput comparison.

## Other startup behavior and limits

PosterBoard traps once at the known first-time-switcher family. Its heap again
contains `Invalid condition not satisfying: !_stateLock_switcherConfiguration`
and no-home/lock-poster-path text. This remains independently unresolved.

No assetsd execution/crash, PhotosService failure, AttentionAwareness error or
SpringBoard crash appears in this capture. Only a tccd op5 trace is observed;
there is no successful extension issue/consume result. Consequently the TCC
repair is **not physically verified** by this log. Absence of the former error
is not proof it was exercised successfully. Home/gpio and HID events remain
visible at the end.

Next work: correct the single-target downsample contract, investigate all four
pixel failures against released Panfrost plus independently regenerated oracles,
and inspect the three terminal compiler publications. Preserve the now-working
strict-alignment loader while doing so.
