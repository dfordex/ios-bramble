# 0204 long run: storage works; live rendering reaches the next missing shader

## Verdict and physical result

The user observes the Apple logo followed by a smoothly rotating spinner,
then a black screen. This is a physical animation checkpoint, not a working
home-screen result. The recovered log supports startup progressing past the
previous main-thread waits and into real604/605 draws. Backboardd later
aborts on fragment specialization; an A8 texture request is also rejected.

Read-only SYSTEM recovery obtains flush2062, all3,972,418 recorded bytes
(3,972,173 decoded bytes /41,928 lines), without overwrite. Framebuffer
interval totals cover20,657,582ms, about5h44m18s. The ring is nearly full,
but still includes the initial boot and first failure. Raw captures and
extracted request/symbolication artifacts remain private outside Git.
No device write, reboot or new build is performed during this review.

## Storage correction verified on the device

Initial successful read/write batches (238–241) each move4096 bytes while
reporting `TCBCNT=2048`, `TBBCNT=4096`. This confirms that0203's equality
requirement would reject a physically completed transfer on this controller.
0204 mounts HFS and completes the18-file installer with sync0 (279).
No batch fallback/error, HFS root mount failure or poisoned-I/O marker follows.

Last cumulative metrics (41784–41786):

| Counter | Result |
| --- | ---: |
| BSD root requests |578,708|
| Read bytes |9,614,569,472|
| Write bytes |477,694,976|
| I/O errors |0|
| Successful multi-block reads / sectors |725,709 /18,772,000|
| Successful multi-block writes / sectors |37,872 /713,544|
| Aggregate active controller time |1,938,687ms|
| Maximum active BSD request |68ms|
| Aggregate mutex wait |47,945,882ms|
| Logger write time |6,669ms|

Useful root bytes divided by aggregate active time is about4.96MiB/s.
This is a driver service-time metric, not a benchmark or a measured speedup
ratio against0202. Read batches average25.87 sectors and writes18.84 sectors.
Concurrent request wait times add together: the13.3-hour aggregate mutex wait
is not13.3hours of boot wall time. The early windows show nearly continuous
controller activity and queued I/O, so storage contention remains material.
Polled PIO and a single controller mutex are still present; batching does not
turn this into DMA or asynchronous I/O. Zero transport errors and successful
stock code execution do not substitute for a complete filesystem byte audit.

## GPU, presentation and compiler

- All23 private GPU pixel cases pass again (197).
- Stock Metal accepts the device. Existing phone-compiled602 and603 programs
  bind (995/1001);602 binds again after backboardd restarts (3654).
- Actual604 is accepted, dispatched and completes (3289–3297), with nonzero
  output reaching the panel and zero differences in4,096 sampled source/
  panel pixels (3309). Actual605 also executes successfully; this is their
  first recorded live compositor-use checkpoint beyond private pixel tests.
- Bounded logs contain26 command-buffer Completed/error0 receipts and32
  successful native receipts: clear4,602×14,603×3,604×1,605×10. These are
  observed receipts, not an exhaustive count after output budgets expire.
- Cumulative presentation windows count18,786,816,000 GPU-copy bytes and
  58,060,800 CPU-copy bytes. No nonzero sampled panel mismatch, MMU fault or
  kernel panic is captured. Copy bytes and fences are not render FPS.
- The phone compiler publishes605 (15209) and604 (15249), after successful
  translator/backend exits. No later604/605 cache-binding receipt is captured;
  their earlier live draws use the already embedded programs. Publication
  must not be conflated with consumption in this run.
- Three other request identities report UNSUPPORTED, including the captured
  fragment below. The compiler currently admits exact recognized602–605
  pairs; it is not a universal compiler for arbitrary Metal requests.

## First concrete rendering gap

At3318–3320, backboardd requests an A8Unorm texture (Metal pixel format1):
576×301, row576, offset64, active image173,376 bytes, backing176,128 bytes.
Linear-view and allocation paths both reject `pixel-format`. The local Xcode
Metal header independently identifies format1 as `MTLPixelFormatA8Unorm`.
R8 support is not automatically the correct A8 channel mapping.

At3323–3445, two complete untruncated58-constant captures reject
`fixed_frag_lph_cph`. Both captures are identical. Compared with the exact
profile603 constant set, only these values differ:

| Constant |603| New request |
| --- | ---: | ---: |
| `fc_coord_function0` |0|5 (`05`) |
| `fc_image_function0` |0|17 (`11`) |

All typed widths and the other56 values match. Request fingerprint begins
`9be0d54f`; its compiler response is also UNSUPPORTED (15250).
The first backboardd then aborts at3446, exit namespace13/code7,
`Metal failed to specialize fragment function` (3511).

The next implementation needs a genuine translation/compilation of this
constant combination, its actual coordinate/image/resource contract, A8
allocation plus linear-buffer alias and native sampling/channel semantics,
and corresponding compiler/cache/registry/pipeline admission. Aliasing an
existing fragment or ignoring specialization failure would not implement it.
The pairing and output pixels must be tested on Mali before claiming this
unblocks the home screen. Other unsupported request fingerprints lack full
captured contents here and must not be assumed equivalent.

## Crash and thread census

Five backboardd SIGABRT records occur at3446,6484,8946,15546,41895. All carry
the same namespace13/code7 specialization reason. Only the first failure has
the full new constant capture; later specialization identities are not proved
identical because the bounded process output budget is exhausted.

PosterBoard SIGTRAPs once (7340). Preferred PC is again0x1c1778268, the known
first-time switcher-configuration assertion. This time its heap scan also
captures `Invalid condition not satisfying: !_stateLock_switcherConfiguration`
(7387) and prewarm/updateExtensions context. It restarts. This remains a
separate state bug, not an unsupported CPU instruction. ScreenTimeAgent
SIGABRTs once (17031), without an originating reason; assetsd has no crash
record. SpringBoard has no crash header, though it executes again alongside
service restarts; absence of a crash header is not proof it never restarted.

All32 sampler rounds are present. Two SpringBoard headers exceed the32-thread
capture cap (maximum46); their worker sets are incomplete. In round31,
SpringBoard's main thread (22239–22241) is in normal `CFRunLoopRunSpecific`
through `GSEventRunModal`, `-[UIApplication _run]`, `UIApplicationMain` and
`SBSystemAppMain`. Exact local shared-cache symbolication verifies this chain.
The earlier UserManagement/CacheDelete startup wait is no longer the common
explanation. The final sample precedes much of the long run; it does not
establish a coherent all-thread state at the last crash.

## Next work

Preserve the now device-verified multi-block storage path. Address the exact
new fragment and A8 resource path together, keeping explicit failures for
unimplemented semantics. Trace/fix PosterBoard's repeated initialization
separately; do not suppress its assertion or delete its state speculatively.
The physical spinner is progress, while the home-screen transition remains
incomplete.
