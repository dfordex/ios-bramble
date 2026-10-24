# 0218 clock-transition stall and backboardd restart

## Verdict: two concrete blockers; hardware correction pending

Full SYSTEM capture flush90 contains736,393logical bytes (decoded736,148bytes/7,922lines). The user reports a spinner after repeated Home presses, then the clock moving upward before stopping partway. Button delivery and visible movement are distinct from completing the unlock transition.

| Evidence | Conclusion |
| --- | --- |
| First backboardd CB2–8 | Native GPU commits complete with status4/error0; the prior producer-flock wait is passed |
| New1888-byte fragment | Actual dynamic-stage acceptance is logged |
| Factory failure immediately before crash | attachment0.pixelFormat actual43, expected80; function code was accepted but target storage contract was missing |
| Crash record | backboardd SIGABRT, Metal failed to build render pipeline; backboardd/SpringBoard restart follows |
| Second-process later sample | Render thread is after nanosleep in newFunctionWithName:constantValues:error:, awaiting another genuine specialization |
| Compiler samples | Retirement/read/publication/snapshot work continues instead of dispatching the new function; no child compilation is captured |
| Exactly1024 backboardd tee chunks | Boot-global diagnostic quota stops after second-process misc-query17/profile605; absence of subsequent emitter logs is not evidence of an emitter hang |

The actual SDK defines43 as packed16 BGR5A1Unorm, not RGBA8 or sRGB. Texture allocation/bridge/kernel resource identities already understand2bytes/B5A1. The dynamic profile and misc SFBD/preload paths were still limited to BGRA8 target80. Other unrelated filesystem/service warnings are not treated as the cause of this captured abort.

## 0219 corrections

1. Dynamic profile carries the descriptor's exact supported target80 or43.43 uses2-byte bounds, SFBD internalR5G5B5A1/writebackR5G5B5A1/BGRA swizzle and a genuine released-Mesa preload program with RGB5_A1_UNORM sampling. Format80 remains unchanged. Unsupported formats and format43 application texture inputs remain rejected; unknown inputs cannot reach an R8 fallback. Factory/emitter tests cover copy/source-over, packed row/span bounds, SFBD/preload fields and negative formats. Physical43 pixels remain unverified.
2. The one newly recovered fragment compiles through the actual Mac production worker to2128bytes. Real cache identity/reflection validation and factory/emitter replay with static603 pass. It becomes the23rd persistent stage; physical execution is pending.
3. Worker snapshots/authenticates up to64requests perUID, services fresh functions before older function statuses/publications and pipeline bookkeeping, then attempts at most one authenticated retirement per completed scan. Tests compile a genuine1808-byte vertex before62old pipeline/status rows and an old failed function, preserve an unsafe leaf, prove one retirement per scan and no recompilation on the next scan. An already running archival I/O can still delay the next scan; no claim of an I/O latency bound.
4. Backboardd diagnostics get up to1024chunks for each of four distinct process lifetimes, at most4096perboot. Saturation never resets unboundedly. The actual helper passes a12-writer concurrency test, lifetime separation and global-cap checks.

## Remaining evidence

Normal UI boot continues with optional shader/downsample suites explicitly0, native GPU4CPU/32-sector storage and actual persistent shader cache retained. No new successful physical-pixel fixture claim is made. The next phone capture must show43factory/GPU acceptance, progression past the new stage, and visible input transitions. Raw logs, shader programs, requests and Apple artifacts remain private.
