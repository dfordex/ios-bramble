# 0225 device log review

## Capture

Complete SYSTEM flush 82 recovers 1,263,896 logical bytes / 13,667 lines without
ring overwrite. Recovery/model/partition guards preceded the read of the first
8,193 SYSTEM sectors. A bounded read-only HFS lookup also recovered seven of
nine exact project shader files (two absent), reading 221,184 physical bytes
including catalog nodes. No partition write or reboot occurred in this review.
Raw logs, device identifiers, requests and compiled programs remain outside git.
Line references below refer to the private complete capture.

## Confirmed first compositor blocker

Both compiled stages are accepted at lines 4365–4366. Pipeline composition then
rejects twice at lines 4370–4374:

```text
predicate=descriptor.contract
vertex attribute1 actual={format:0,offset:0,buffer:0}
expected={format:29,offset:16,buffer:1}
```

`vertexABI` in `A5MaliDynamicPipeline.m` correctly classifies the compact
two-input position/color native vertex. Pipeline construction at lines 419–437
nevertheless creates four attributes at offsets 0/16/24/32 and sets
`attributeCount=4`. It demands a UV attribute absent from the actual descriptor.
This is a generated vertex-layout mismatch after successful shader compilation.
The repair must map reflected native inputs to actual Metal attribute indices
through validation and native emission; ignoring descriptor errors is inadequate.
Exact stages and the failing descriptor are available privately for replay.

## Crashes and diagnostic limits

Six backboardd SIGABRTs occur at lines 4375, 7483, 10701, 12405, 13198 and 13484.
All exit reasons say `Metal failed to build render pipeline`. Only the first
has its exact terminal descriptor rejection captured. The later five cannot
confidently be assigned the same missing-attribute cause.

The provider stdout tee allows four process lifetimes with 1,024 chunks each;
the compiler has a separate 128-chunk allowance. Missing later diagnostics
therefore do not establish that an operation never ran or that it stalled.

SpringBoard separately aborts at line 7588. Line 7581 explicitly records an
uncaught `NSInvalidArgumentException`: AttentionAwareness configuration fails
after its service connection/proxy is interrupted. This differs from 0224's
verified FrontBoardServices null-processIdentity SIGTRAP. Provider death precedes
it; ordering alone does not prove the GPU caused the service failure.

## GPU, residency and input

- 195 captured CB results are Completed (`status=4`), `error=0`, `submitted=1`,
  across four logged provider lifetimes. These are not distinct displayed frames.
- Eight sampled 4,096-pixel source/panel comparisons have zero RGB/alpha
  mismatches. Some native compositor output reaches the panel before failure;
  this does not verify all UI elements or pixels.
- All 1,236 raw AS0 fence records complete with MMU status zero. Those include
  panel/transfer/startup work, not a count of native AS1 compositor submissions.
  No kernel panic is recorded.
- 207 HID touch and 160 HID key records prove input arrival, not responsive UI.
- Presentation is irregular, with zero-swap intervals. One 5.878-second interval
  has 100 shown records but only 50 GPU panel copies (about 8.5 copies/second).
  Its printed `fps=17.0` is not proof of 17 distinct rendered frames/second.
- No failed import or 128-entry high-water marker is captured. Threshold reports
  reach 33 and 64, not exact final peak counts. Repeated restarts and bounded
  provider logging prevent a clean residency comparison with 0224. Idle
  eviction/reimport remains physically unverified. `closed=0` is client state,
  not a released-import count.

## Compiler, apps and storage

The updated backend installs and executes. A new fragment automatically passes
AIR translation in 11.081 seconds and native compilation in 8.125 seconds,
publishing 3,968 bytes at line 13193. Its complete program, receipt and reflection
were recovered. Later acceptance/drawing with it is not captured.

Two `UNSUPPORTED` records are full pipeline requests handled by the older
exact-pair compiler route. Recovered statuses explicitly state that route's
typed-pair restriction. They do not mean the successful new single-function
fragment compilation failed. The prepared 1,120/1,536/3,632-byte publications
install/validate at lines 522–528; later consumption is not explicitly captured.
Quiet backend execution is confirmed, but its reduced output byte count was
not separately recovered.

Settings (`Preferences.app`), Clock (`MobileTimer.app`) and Safari
(`MobileSafari.app`) install through HFS VFS: 282 directory operations,
`error=0` at line 529; overall payload completion reports 364 files and `sync=0`
at line 531. This verifies installation, not icon registration or app launches.

Storage counters report zero I/O errors. Aggregate lock waiting remains high;
overlapping wait totals are not an isolated throughput benchmark.

## Next correction

Replay and repair the compact vertex attribute mapping first, preserving checks
for genuinely unsupported layouts. Then verify later pipeline cases/new fragment,
retain terminal diagnostics across provider restarts, and test import reuse with
a long-lived compositor. AttentionAwareness resilience and application icon
registration remain separate checks. No new image was built or installed by
this log review.
