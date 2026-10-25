# 0240 runtime: comparison removed, approximately5copy/s remains

## Verdict: CONCERNS

The requested no-comparison mode is confirmed on the phone. Presentation-path cost is substantially lower, but the peak measured rate of actual panel copies remains approximately5/s. The final transfer is therefore not sufficient to explain the continuing slow UI. Bounded native batches still mostly contain one item, resource mapping/queue admission failures occur, and PosterBoard repeats its known state assertion.

## Evidence scope

Read-only TWRP/a5xelte/SYSTEM verification, then the8193-sector diagnostic region: flush95,778937raw bytes,8175 decoded lines/778692UTF-8 bytes, no overwrite. Three exact waiting shader requests' project files were separately fetched through bounded read-only HFS traversal:271872physical bytes. All raw logs, request identities and shader binaries remain outside git in private research build0240/runtime.

## Controlled comparison

The image reuses0239's kernel/provider and changes only the damage-mode boot argument. Workload, runtime duration and cache warmth differ; this is not a perfectly replayed benchmark.

| Measurement |0239 comparison on|0240 comparison off|
| --- | ---: | ---: |
| Reconstructed presentation cost per actual copy |54.94ms|12.74ms|
| Peak actual GPU+CPU panel copy rate |5.05/s|5.13/s|
| Peak reported shown rate, including no-ops |10.0/s|10.0/s|
| GPU presentations |584|412|
| GPU presentation bytes |449971200|3417292800|
| Partial comparison records |Present|None|

The presentation estimate is `sum(avg_copy_us * shown) / real GPU+CPU copies`; it includes CPU/scheduling/no-op costs and is not isolated GPU execution time. Its76.8% reduction does not imply a76.8% overall FPS improvement. Different run lengths mean total bytes cannot be compared as equal workloads.0240's412GPU copies each account for8294400B, confirming full-frame transfer. No comparison records plus the live `a5fb_damage=0` argument confirm the mode change.

184intervals include133zero-shown startup/idle intervals;832shown includes414self/missing-source records.412GPU/3CPU copies, one GPU fallback are recorded. The bounded eight4096-point panel/source grids have zero RGB/alpha mismatch. There is no captured kernel panic or SpringBoard/backboardd crash.

## Remaining findings

| Finding | Evidence | Interpretation / next step |
| --- | --- | --- |
| P1: drawing/admission/pacing before final transfer still limits progression | Peak real copy5.13/s despite12.74ms estimated presentation cost; same native code as0239 | Final copy cost alone is not the limiting explanation. Retain no-comparison baseline while addressing upload/resource lifetime and instrumenting render submission, completion and swap cadence separately. Do not promise a specific FPS from these counters. |
| P1: batches are normally cut short |90 sampled group receipts:78count1,11count2,1count3, none4; last group counter5184 | Known per-draw temporary create/upload/release barriers remain. A bounded command-buffer upload arena and fence-based retirement are still needed. The sampled mix is not the exact distribution of all5184groups. |
| P1: transient admission failure is exposed as a frame error | Private log6049/6064/6096: Query17 returns NoResources on cb64/67/80.6087: group1385,count2,completed0,status2;6088 resource-upload reportsBusy | Native batch status2 comes from failure to acquire the shared runtime queue before START. That acquisition checks readiness/power/clock and queue reservation; the exact failing check is not logged. AS1 mapping also collapses a pre-start MMU-update Busy into a false map result and then NoResources. Shared AS0 presentation/AS1 resource contention is a concrete source-level candidate, not yet proved for all three query errors. Add bounded reason detail and preserve/retry definite pre-start busy requests through proper arbitration; never retry uncertain started jobs. |
| P1: PosterBoard's known state assertion recurs | Private log4084..4133: SIGTRAP/namespace2/code5; extracted text `Invalid condition not satisfying: !_stateLock_switcherConfiguration` | This is separate from a GPU fence fault. No evidence proves disabling comparison caused it. Investigate state/config initialization with an exact stack before changing preferences or suppressing the assertion. |
| P2: cold shader variants still pause rendering, then complete | Three waiting requests; one logged8.961s AIR+13.967s backend produces a3904B fragment | Bounded disk verification finds all three genuine complete publications3904/2624/2624B with matching native/reflection sizes and hashes. Do not call the final compiler permanently stuck. Keep persistent results; shader prewarm alone will not solve the approximately5copy/s baseline. |

All64 captured early backboardd command-buffer results are Completed/error0; later errors outlive that logger's64-receipt budget.32native status/MMU receipts pass.828captured AS0 fence receipts complete/MMU0. Of90sampled batch receipts89complete/status0; one rejected Busy group starts no items. No native fault/timeout or uncertain-queue poison marker is captured. One CPU fallback does not establish corruption.

35touch and18key HID records reach the kernel. Four iPhone10,5/D211AP sysctls remain correct. One driverkitd per-process memory-limit kill persists. Final storage counters show2985731072B reads/131602432B writes/0errors,573449ms cumulative active and814ms log I/O. Parallel lock-wait aggregates are not wall time or proof of the current frame bottleneck.

## Next step

Keep the reduced-cost presentation baseline. Implement bounded upload reuse/deferred resource retirement and explicit shared-queue arbitration for definite pre-start Busy. Log the exact mapping rejection rather than treating all NoResources as exhaustion. Investigate PosterBoard separately. This readout makes no device modification and packages no new BOOT.
