# 0193: actual stock native jobs complete; resource-method and later shader aborts

## Verdict

The0192 unwired-input kernel panic is absent, and live backboardd clear0,
indexed602 and textured/source-over603 jobs now complete with genuine terminal
fences and MMU0. This is a device-verified advance beyond host transport tests.
It is not complete UI success: the user observed a prolonged black screen.
Backboardd first aborts on the missing setPurgeableState: buffer method, then
later repeatedly aborts on fragment specialization. Visible compositor pixel
correctness is still unverified.

## Complete read-only capture

SYSTEM flush91:645334 recorded bytes, all recovered without overwrite;
decoded645089bytes/6319lines. The recovery read's94-byte dd transfer receipt
was appended after the requested4194816-byte block area. Its exact footer
acknowledged8193records/4194816bytes and was separated before decoding; the
A5XLOG1 header and ring bytes were preserved. Raw captures and identifiers
remain private. No device write/reboot or new build was performed in this turn.

| Lines | Evidence |
| --- | --- |
|189|All21 private GPU reference cases and44 terminal fences pass; not stock UI coverage.|
|1034-1041|Actual194x237,row832,image197128 Shared linear view and full602/603 pipelines accepted.|
|1044-1065|Backboardd command buffer2 submits one clear and two indexed draws. Query17 maps the actual target and then the source buffer. clear0 fence1,602 vertex2/fragment3 and603 vertex4/fragment5 all return status0,header1,MMU0. All three Submit18 phases return0; Metal reports status4/Completed,error0.|
|1066-1071|Framebuffer calls follow, including the initial full-size swap request.|
|1078-1133|First backboardd abort: A5MaliSharedReadBuffer setPurgeableState: unrecognized selector, NSInvalidArgumentException, signal6/namespace2/code6.|
|1271-1278,1471-1473,1586-1590|Three restarted clients each complete the same0/602/603 sequence again. Thus12 native job records are successful; repeated fence numbers are per-client, not a global monotonic sequence.|
|1281,1483,1632|Further backboardd signal6 records with the same backtrace as the first resource-method crash. First three runs retain the selector text; the fourth does not retain another detailed exception dump.|
|1542-1561|One SpringBoard signal6/namespace2/code6; heap text includes Unable to query displays from server(-308), after earlier backboardd failures. This is consistent with display-server loss, not an independently identified GPU shader fault.|
|1660-3244|33 additional backboardd aborts report namespace13/code7, Metal failed to specialize fragment function. Exact rejected name/constants are not retained in this capture.|
|3050-6139|1350 failed contiguous-allocation scans request84 pages. A kernel allocation hotspot exists independently of shader admission.|
|3595-3599|A real full-panel source mapping is installed and tile bounds cover1080x1920; the code itself distinguishes job completion from pixel readback.|
|3677-6152|The framebuffer counter totals22 completed full-frame GPU copies /182476800bytes,CPUcopy0. The user's black-screen observation remains the physical result.|
|6298|Automatic compiler still RUNNING in midgard-generic602 at wall663.3s. No cache publication/result completion is recorded.|

The capture contains177 framebuffer measurement windows,37 backboardd crashes,
one SpringBoard crash and no kernel panic. No native-job MMU fault/timeout or
poisoned-AS1 teardown marker appears. Matching IOAcceleratorES repeatedly is
consistent with the observed daemon restarts; matching alone is not drawing.

## P1: missing Metal resource lifetime method

A5MaliSharedReadBuffer inherits A5MaliPrivateBuffer, which inherits NSObject.
Neither class implements setPurgeableState:. The first explicit exception
therefore identifies a concrete provider API gap after successful GPU command
completion, rather than a rejected shader or kernel panic. Implement the Metal
resource contract for the actual Shared/private backing and lifetime, including
valid state transitions and return semantics; do not swallow the selector
exception or pretend discarded contents remain valid. Exercise Shared,
no-copy/deallocator and in-flight command references in the regression.

## P1: later specialization failure identity is missing

The first successful603 program is not evidence that every later function or
constant combination is implemented. The33 namespace13/code7 aborts are real,
but the exact next rejected fingerprint cannot be identified from the saved
messages. It may be another name/state or another function-construction
failure; do not label a guessed variant as the missing shader.

Source explains the diagnostic gap: bsd/dev/mem.c:sweet_null_tee uses a shared
256-write-chunk budget for selected daemons across the entire boot, separate
from the probe/compiler budgets. The last backboardd tee record is line1276,
before the later shader failures. The4MiB ring has not wrapped: increasing the
ring does not solve a producer-side budget. The provider already forwards
rejected specializations before its own four-request print cap, so inspect
those queued receipts or retain bounded, deduplicated failure identity through
a path that survives the tee budget. Fixing setPurgeableState: first should
also prevent the early restart/output storm, but does not prove the later
shader gap repaired.

## P1: excessive contiguous AS1 allocation requirement

A5XELTEGPUAS1.cpp allocates kAS1TableBytes=0x54000=84*4096 as one physically
contiguous block, and its initialization/update paths assume a single physical
span for that entire pool. This exactly matches the observed repeated84-page
allocation failures. It is strong source/size correspondence, not a saved
allocation call stack. No poisoned-context message proves an intentionally
pinned failed GPU job here.

A single contiguous pool is not a hardware requirement for all independent
page-table pages. A future repair must update every table/PTE/cache reference
to the actual per-page physical addresses and preserve alignment/address-width,
barriers/TLB maintenance and context lifetime. Merely removing the allocation
flag would violate current span/arithmetic assumptions. This pressure is an
additional likely contributor to stalls and failed resource setup, not proof
that it alone caused the namespace13/code7 aborts.

## Presentation and compiler limits

Frame counter gpu_source is a skipped/reused/missing-source counter. Source
inspection shows it increments when no distinct valid surface can be copied,
including the already-selected surface; it is not a completed GPU draw count.
The22 gpu completions are full-panel-copy completion, not measured correct
compositor pixels. Shown/fps counters include unchanged-source ticks and must
not be presented as an actual iOS render rate. There is no pixel readback or
user-visible successful UI in this run.

The automatic compiler progresses: metal2vulkan exits0 at wall30.676s/cpu5.431s,
then midgard-generic602 remains alive through663.3s with periodic memory/status
reports. This is not UNSUPPORTED, a completed phone compilation, a published
cache, or proof of a deadlock. CPU-time/progress details for that child would
be needed to distinguish slow work from a stall.

## Next work

Implement and test the missing purgeable resource method. Preserve exact
failure identity beyond the daemon tee cap so later fragment admission can be
repaired using real requests. Remove the oversized contiguous table-pool
assumption with correct per-page mappings, and then recheck native fences,
compositor output pixels and display presentation separately. Keep all three
issues distinct; this readout does not claim a new fix/build/installation.
