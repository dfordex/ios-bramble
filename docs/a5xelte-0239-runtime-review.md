# 0239 runtime review: bandwidth saving without an FPS gain

## Verdict: CONCERNS

The user reports similar extreme slowness and effectively absent animations. Fresh device evidence confirms partial presentation and native batching are active, but does not demonstrate a higher real display update rate. Presentation bandwidth is much lower while the measured presentation path costs more time. New shader demands also pause rendering; all five captured waiting requests have valid compiled publications by the end of this run.

## Read scope

Read-only TWRP/model/partition verification followed by SYSTEM's8193-sector log area: flush88,831846raw bytes,8704 decoded lines/831601UTF-8 bytes, no ring overwrite. A separate allowlisted USERDATA read fetched only nine project shader identities' request/publication/status paths:401920 physical bytes, no filesystem/device writes. Raw logs, shader programs and request details remain private outside git.

## Results

| Measurement | 0238 | 0239 |
| --- | ---: | ---: |
| GPU panel presentations in captured intervals |282|584|
| GPU panel bytes |2339020800|449971200|
| Partial presentations at last logged comparison counter |0 through256|553 of576|
| Transfer saving versus full copies for the same0239 GPU count |0%|90.71%|
| Peak reported shown/s |10.1|10.0|
| Peak actual panel copy/s |5.10|5.05|
| Approximate present time per actual GPU/CPU copy |19.53ms|54.94ms|

Runs differ in duration/workload. Rates are interval maxima, not steady FPS. The presentation-time estimate reconstructs `avg_copy_us * shown` over real GPU+CPU copies, so includes no-op overhead, scheduling and CPU work; it is not isolated Mali execution time. The comparison establishes no FPS gain, not an exact causal benchmark of each change.

0239 has165 intervals,118 with zero shown including startup/idle;1178 shown includes585 self/missing-source records.584GPU/3CPU copies and zero GPU fallback are recorded. At the comparison576 checkpoint,553 partial/0 unchanged transfers total430617600B instead of4777574400B,90.99% less. The final presentation aggregates give449971200B versus4843929600B,90.71% less.

## Evidence and material findings

| Finding | Evidence | Assessment / next step |
| --- | --- | --- |
| P1: whole-image CPU/coherency work remains despite small GPU bands | Private log2527..8443 shows partial bands; actual present path in patch0217 calls frame-map first, then flushes the entire source, compares all1920 rows and copies changed rows into its shadow. FrameMap also stores the full source even for an existing mapping. | Confirmed work exists; increased aggregate present time is measured, but no phase timings isolate its share. Replace full-image probing with validated dirty bounds/write generations where available; keep an exact fallback for unknown writers. Instrument map/cache/compare/submit separately to verify the improvement. |
| P1: batch barriers usually reduce groups to one draw |98 sampled kernel group receipts:85 count1,5 count2,8 count3, none count4. All completed/status0; last counter5760 proves at least5760 dispatched groups. `A5MaliMetalAPI.m` creates/uploads temporary BOs and releases them at the end of each native draw; `A5MaliNativeBatch.inc` flushes before any nonmatching transport call. | Source proves immediate buffer release is a barrier, not a speculative GPU defect. Move upload storage/resource retirement to a bounded command-buffer arena and retire only after terminal group fences; preserve mapping epochs and hazard barriers. Sampling does not give the exact distribution of all5760 groups. |
| P1: new shader cache misses still stop a frame | Five distinct waiting function requests. One logged AIR translation takes56.440s wall/11.139sCPU, followed by8.970s backend before a real1248B publication/acceptance. Other terminal logs are not fully captured. | All five now have genuine valid5312/1248/3840/3904/2624B native triplets on disk; do not call them currently stuck. Prewarm these exact demands on future packages and preserve the cache; capture scheduling/I/O waits for cold requests rather than claiming arithmetic compilation alone explains the wall time. |
| P1: one live resource mapping failure remains | Private log6571: backboardd cb111 clear-query17 returns`e00002be` (NoResources), after the first64 result receipts. NativeQuery's relevant failures are protected surface mapping or buffer mapping. | Exact underlying map/unmap/allocation branch is not logged. Add bounded branch/resource detail and correct the demonstrated cause; do not call this global RAM exhaustion or silently accept an unmapped resource. |
| P2: no-op pacing and reported FPS hide the real rate | Actual framebuffer timer increments shown for completed no-op records; timer re-arms16667us after callback work and copies only every second callback at30Hz. | Shown10/s is not10 new images/s. Separate changed/no-op counters and completion pacing; use an absolute deadline/real completion design without acknowledging unfinished pixels. This issue was not fixed by preserving the shadow. |

## Correctness and process state

- All64 captured backboardd command-buffer results are Completed/error0. The result logger stops at64, so cb111's later error is not contradicted by that count.
- All98 sampled batch receipts complete every listed item with status0;32 native receipts status0/MMU0;1176 captured AS0 fence receipts complete/MMU0. These are bounded receipts, not a complete global GPU fault history.
- Eight4096-point panel/source comparisons have zero RGB and alpha mismatches. Sparse pixel checks do not prove every UI image/animation correct.
-61 touch and80 key HID records; input reaches the kernel. The user still observes poor UI response.
- No recorded kernel panic or SpringBoard/backboardd/PosterBoard crash. One driverkitd SIGKILL namespace1/code7 remains a per-process memory-limit termination.
- Four identity sysctls are correct iPhone10,5/D211AP.386-file installation completes/sync0, including all36 stage publications. The four prewarmed publications remain exact on disk and have no new waiting receipts; receipt presence alone is not proof every one executed.
- No explicit new unsupported sampler, external texture or shader failure is recorded in this run; this does not prove earlier unsupported contracts implemented. A source search finds no explicit reduce-motion/animation-disable switch in the active project code.
- Final storage counters:3054967808B reads/159021056B writes/0errors; ownership and critical-path attribution remain unproved. Do not conflate aggregate lock wait with wall time.

## Recommended next implementation

Prioritize presentation CPU/coherency cost and upload lifetime barriers together with bounded phase timings. Keep real terminal fences, accurate dirty bounds, retained resource ownership and fault quarantine. Separately diagnose the Query17 mapping rejection. Warm shader outputs already produced by this run; another shader-only package will not repair the approximately5copy/s path. No new BOOT or device mutation was performed during this review.
