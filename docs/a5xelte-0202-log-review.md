# 0202: startup advances beyond the earlier RPC waits

Read-only SYSTEM recovery: flush38, 152,620 recorded bytes, 152,375 decoded
bytes / 1,760 lines, no overwrite. Framebuffer windows total409,570ms
(about6.8minutes). Raw captures and shared-cache symbolication remain private.

## Observed result

- All23 private GPU pixel cases pass (197); incremental installer18 completes.
- Backboardd binds both phone-compiled602/603 caches (1016/1024). Three command
  buffers complete six native jobs with status0/header1/MMU0 and returning
  callbacks. No crash, kernel panic, GPU fault or failed pipeline is captured.
- Two GPU and one CPU full-panel copies complete, each8,294,400bytes.
  The logged4,096 source/panel samples have zero RGB/alpha differences.
- CB4 draws an all-black target from actually black input vertices. Its
  subsequent surface-less swap6 is replaced by surface-less swap7, followed
  by display-off (ignored by keep-on). This does not establish a failed GPU
  command or prove why iOS has not sent the later home-screen frames.
- No live604/605 request or new compiler publication appears. Compiler service
  startup is logged; existing cache use is distinct from new compilation.

## New sampler verified

Five rounds,74 thread records, complete split `SMP`/`SBT` output. Maximum
record length including newline is131bytes; the old255-byte clipping does
not affect these records. No process hits its thread capture cap.

SpringBoard main-thread samples change through dyld section loading (round0),
ObjC image mapping (1), ObjC category loading (2), UIScreen metrics/display
initialization (3), then an `open` during localized MobileGestalt data access
inside `-[SBPlatformController init]` (4). Preferred final addresses include
`__CFReadBytesFromFile`0x186e90218, `__MGSCopyLocalizedString`0x1a2e99ba4,
and `-[SBPlatformController init]`0x1c59ad4cc. The call chain is resolved from
the exact local stock shared cache using the captured slide.

Thus the UserManagement/CacheDelete main-thread calls from0201 are not a
persistent common deadlock across these trials. Usermanagerd is in normal
CFRunLoop waits. Misagent performs a SQLite WAL checkpoint in round3, then
has idle dispatch workers in round4; dispatch_main's main-thread retirement
sleep is not itself a service failure. Deleted starts after the last sample
(1721), so its server thread state is not captured. PosterBoard starts at1737
without a later sample or crash; assetsd does not start in this capture.

Backboardd main briefly executes state-description capture in round3, then
returns to its normal CFRunLoop in4. SpringBoard workers retain DND, Powerlog
and telephony XPC waits; UIEventFetcher runs its message loop. These are
waiting contexts, not demonstrated causal faults. Final queued key events
do not prove the whole system deadlocked.

## Storage candidate and limit

The actual Samsung root driver still resets the FIFO and issues CMD17/CMD24
for every512-byte sector under one mutex, even for large filesystem requests.
The new stack samples make this path a concrete performance investigation
target, but do not measure its share of boot time. There is no eMMC command
error in this capture. Usermanagerd's foreground/session warnings and a failed
swap-file open are also recorded; neither is established as the UI blocker.

The user requests faster read/write followed by a long run.0203 implements
bounded multi-block transfers with timings; no service bypass or assertion
suppression is justified by this capture.
