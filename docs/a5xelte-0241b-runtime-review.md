# 0241b runtime: shader wait and active-AS0 admission gap

## Verdict: CONCERNS

Captured GPU work and sampled panel pixels pass, but interactive throughput is still low. A new fragment specialization is requested near the end; backboardd repeatedly waits while the phone compiler enters translation, and no terminal publication is present in the recovered project files. One queue-admission diagnostic also exposes a source defect: an active AS0 GPU job is treated as unavailable rather than transient contention. PosterBoard separately repeats its switcher-state assertion.

## Evidence scope

The connected device was verified as a5xelte in TWRP3.3.0-0 with SYSTEMp20. Read the8193-sector diagnostic area: flush51,543364recovered bytes,6129decoded lines/543119UTF-8 bytes, no ring overwrite. A bounded147968B read-only HFS traversal fetched only the new request and checked its exact project status/publication paths. Raw logs, request identities, native programs and machine-readable analyses are retained privately in research build0241b/runtime.

| Measurement | 0241 | 0241b |
| --- | ---: | ---: |
| Captured completed CB results/error0 |17|61|
| Peak actual GPU+CPU panel copy rate |0.936/s|4.285/s|
| Reconstructed presentation cost/copy |12.743ms|12.717ms|
| Actual GPU/CPU panel copies |15/2|56/2|
| Sampled native group receipts |14|17|
| Last sampled group counter |384|576|
| Captured shader waits |0|1 distinct request|

These runs differ in duration, input and cache activity. The numbers are not a replay-controlled speedup estimate. Reported8.5shown/s includes no-ops; the peak paired actual-copy rate is4.285/s. 101intervals contain83zero-shown windows,118shown and57self/missing-source records. GPU bytes464486400 equal56full8294400B copies; CPU bytes16588800 and zero GPU fallbacks are recorded. Continuous damage comparison remains off.

All17 sampled groups complete/status0:12count1,4count2,1count3; no count4 sample. Logger sampling does not establish the exact distribution of all576groups. Eight sampled arena summaries total8creates/41writes/20resets/3424256stagedB; all result0/uncertain0. Initialization/growth also increments reset.128captured native-phase receipts are zero; no nonzero Query17 result/mapping-failure line.32native status0/MMU0 and116AS0fence receipts complete/MMU0. Eight4096-point panel/source comparisons have zero RGB/alpha mismatch. There is no recorded kernel panic or SpringBoard/backboardd crash. These observations do not prove every frame or all possible workloads.

## Findings

| Priority | Finding and evidence | Action/status |
| --- | --- | --- |
| P1 | Private log5852 first shader wait;5875 dispatch;5945 workspace mkdir ends;5977..5981 translator spawns/executes;6129 still waiting. Six subsequent FB windows total31.837s with zero shown. Exact status, receipt, reflection and native-stage paths are absent on disk; only3836B request exists. | The requested variant has no durable terminal result in this readout. It is not evidence of an unsupported lowering or a permanent compiler hang. Mac replay using the actual worker and released backend now produces4048B real native fragment; production cache loader accepts the authenticated publication. Keep it private for a later payload. No physical GPU execution of this new program is established. |
| P1 | Log5210 reports admission unavailable/sleeps0/state1 between completed AS0fences77/78. `A5XELTEGPU.cpp` defines state1 as active GPU and state3 as CPU staging, but the waiter only retries3. AS0 submit changes3to1 until its terminal job. | Patch0221 waits for1or3 before this caller starts work, preserving the2s bound, poisoned/unavailable rejection and real fences. Actual helper ASan/UBSan tests now cover both contention states, fault during another job and both deadlines. The old helper fails the new active-GPU recovery case; strict patch reverse/apply matches staged bytes. This occurrence did not produce a captured CB failure; it is not established as the dominant FPS cause. |
| P1 | Peak actual copy4.285/s despite12.717ms final-presentation estimate; sampled groups remain mostly one item. No phase duration measurements exist. | Measure CB/query/upload/native execution and boundary reasons separately before another batching rewrite. Presentation estimate is sum(avg_copy_us*shown)/(GPU+CPUcopies), not isolated hardware time. Existing immutable upload/fence correctness is retained. |
| P2 | PosterBoard SIGTRAP namespace2/code5, log4208: `Invalid condition not satisfying: !_stateLock_switcherConfiguration`. Log also contains55SpringBoard nil-layer warnings. | Same prior PosterBoard state/config failure; distinct from a reported GPU fault. No assertion suppression or preference mutation is made. Causal link between this crash, nil-layer warnings and low FPS is not established. |

There are13touch and26key HID records. Keys continue entering a nonfull HID queue during the shader wait; kernel input reception is not proof of compositor response. One driverkitd SIGKILL namespace1/code7 is again a per-process memory-limit termination. Final storage counters2426531328B read/87235584B written/0errors, cumulative active466410ms/max request86ms/log636ms; summed concurrent lock wait is not wall time or process attribution. The long metadata/translation sequence deserves I/O timing, but no per-process I/O ownership is proved here.

## Prepared follow-up and limits

The exact captured fragment compiles on the Mac through the production worker: SPIR-V validator passes; AIR wall0.647s and backend0.532s; genuine native4048B/reflection hashes and production cache loading pass under ASan/UBSan. This is a compiler/cache result, not an executed phone pixel result or a generalized all-shader proof. The new program includes framebuffer fetch and no actual textures, which existing typed-stage reflection represents.

Patch0221 and the expanded admission regression are source-ready. The staged kernel source contains the change, but the linked kernel/installed0241b do not. No full XNU build, payload integration, BOOT package or device write was performed in this readout turn. The next image must include the validated private publication and linked admission correction; its performance and rendering require a fresh phone run.
