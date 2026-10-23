# 0200 long run: compilation finishes, UI transition still stalls

## Verdict: CONCERNS

The longer run proves that the automatic phone compiler finishes and publishes
profile 603. Waiting for that compilation does not restore the home screen in
this trial. The private GPU suite again passes 23/23, existing live rendering
and presentation complete, and no backboardd crash, kernel panic or GPU/MMU
fault is captured. PosterBoard later hits a known state assertion, while
assetsd separately aborts; neither event alone proves the initial cause of
the stalled home-screen transition.

## Recovery and comparison

Read-only SYSTEM recovery in TWRP, exact A5XELTE/model/mapping checks. Flush
207 recovers all 295,445 recorded bytes: 295,200 decoded bytes, 3,897 lines,
without ring overwrite. The raw capture remains private outside Git. No
device write or reboot was performed during this analysis.

This is a separate boot capture, not an append to the previous flush-73 log:
ASLR, process IDs, installer existing/written decisions and command sequence
differ. Compare outcomes, not byte prefixes or an assumed shared timeline.
Its 395 framebuffer windows sum to 2,100,177 ms (about 35 minutes). Event
times below use those interval sums, not wall-clock timestamps.

## Complete result census

| Boundary | Capture evidence | Interpretation |
| --- | --- | --- |
| GPU suite | 197: evaluated 23, passed 23 | Both new 604/605 actual pixel oracles pass again; no compositor coverage claim |
| Installation | 270: complete 18, sync 0 | Current provider/compiler/recipes are available |
| Prior phone cache | 997: bound 602, source phone-compiled | Backboardd actually consumes the previously published 602 program |
| Live jobs | CB2/3/4 result at 1037/1222/1834 | Three CBs, six successful native jobs: clear twice, 602 three times, 603 once; status 0/header 1/MMU 0, CB status 4/error 0 |
| Callbacks/presentation | All three callback pairs return; 15 SwapWait returns succeed | No captured outstanding Metal or framebuffer wait at the final logged boundary |
| Panel transport | One CPU and one GPU full-panel copy, 8,294,400 bytes each | Existing drawing reaches the panel; sampled RGB/alpha source/panel differences are zero |
| AIR compile | 1294: status 0, wall 69.704 s, CPU 5.857 s | Actual phone translator completes |
| Midgard compile | 1437: status 0, wall 80.365 s, CPU 9.668 s | Actual phone native compiler completes |
| Publication | 1479: PUBLISHED profile 603 | Real persistent result publication in this boot; approximately 415 s of metric time. No later 603 cache-bound receipt is present |
| New variants | No live specialization/pipeline 604/605 | Their independent GPU pixels pass, but live iOS acceptance is still not exercised |
| Process crashes | PosterBoard once, assetsd once | Distinct crash families; backboardd and SpringBoard each execute once with no crash header |

At approximately 590 s, CB4 completes another clear/602 draw. Its following
all-zero swap is selected and iOS requests display off, which keep-on ignores.
No further live Metal commit follows through the end of the capture. The
user reports no visible progress after waiting. Compilation has already
finished before CB4, so an unfinished 603 compiler child cannot explain this
later lack of progress.

## PosterBoard assertion, confirmed by address and existing disassembly

At 2843–2846 (approximately 1,058 s of metric time), PosterBoard gets SIGTRAP:
runtime PC `0x20f790268` minus shared-cache slide `0x4e018000` equals preferred
VA `0x1c1778268`. This exactly matches the instruction and state assertion
independently analyzed in the [0183 full review](a5xelte-0183-log-review.md):

`-[PBFPosterExtensionDataStore _stateLock_setupSwitcherConfigurationForFirstTime]`

The retained exact disassembly loads `self+0x98` at `0x1c1777ab0`, branches
to the fatal path when nonzero at `0x1c1777ab4`, records its crash message at
`0x1c1778264`, then executes `brk #0` at `0x1c1778268`. The assertion is
`!_stateLock_switcherConfiguration` (source line 3431): first-time setup was
called with a switcher configuration already present. The next log executes
PosterBoard again (2848).

This is a repeated initialization/state failure, not a captured unsupported
CPU instruction, shader rejection or Mali job failure. It now persists with
the earlier backboardd restart loop absent. Its cause still needs the state
transition/prewarm context. It occurs well after the last live draw and does
not by itself prove why the earlier home-screen transition stopped. Do not
delete configuration or replace the assertion with success without tracing
the intended initialized-state path and completion obligations.

## assetsd and other workload

At 3487–3490 (approximately 1,600 s), assetsd SIGABRTs with namespace 2/code 6,
then restarts. Subtracting the same slide gives PC `0x1c2617198`
(`__pthread_kill+8`) and LR `0x1d1ba65f8` (`pthread_kill+208`), the same
terminate/Objective-C/dispatch backtrace family retained in the 0183 review.
The originating exception text is absent, so no specific missing asset or
API can be selected from this unwind.

Background services continue throughout the run. A vmd CPU-use warning and
existing swap/preboot/persona warnings occur, but the capture does not link
them causally to the UI transition. Repeated xpcproxy/bluetoothd/fairplayd
execution receipts are not independent backboardd crash evidence.

## Findings and next steps

| Priority | Finding | Next bounded investigation |
| --- | --- | --- |
| P1 | UI remains stalled after compiler publication and successful native callbacks | Capture SpringBoard/backboardd waiting-thread/startup state after CB4; waiting longer for this compiler is not a sufficient repair |
| P1 | PosterBoard repeats first-time setup despite existing switcher state | Observe its setup/update/prewarm calls, state and completion path; this is now a persistent independent crash candidate |
| P2 | assetsd terminates without its originating exception text | Capture its stderr/exception reason before choosing a repair |

The next instrumentation should include PosterBoard/assetsd exception output
and bounded startup/wait-state evidence for the UI processes. Preserve all
successful shader/presentation tests. There is no evidence in this run that
another uncompiled GPU specialization is blocking the transition.
