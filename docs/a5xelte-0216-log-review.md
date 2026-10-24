# 0216 input report: CA waits for a new shader stage

## Full capture

The SYSTEM capture has flush66 and431,469logical bytes recovered, with no wrap. The decoded record is431,224bytes/5,186lines. The user's screen reaches the UI but buttons and touch do not produce a usable transition. No panic, process CRASH, GPU MMU fault or import/map rejection appears in this capture.

Backboardd command buffers2–10 complete with status4/error0/submitted1. Seven sampled framebuffer intervals include GPU presentation; source/panel pixel samples match. Optional47-case testing is disabled and the mandatory bootstrap passes, so the previous DS4 fixture quarantine is absent.

Home and Power key events have an iOS HID consumer. The queue head advances to2048, including after the shader wait starts; no full queue appears. Thus button delivery continues while rendering stalls. Touch detail logging is explicitly off in this build; the lack of contact log lines does not establish a touch hardware failure.

## Specific rendering wait

At command buffer11, a2720-byte previously cached fragment is accepted and linked. The next exact `fixed_frag_lph_cph` specialization has a different noise/blend constant combination and is queued, then repeatedly logs waiting16times. It has no publication or terminal status in the recovered HFS state.

The actual provider runtime address immediately after nanosleep maps to `newFunctionWithName:constantValues:error:`. The caller is the descriptor pipeline factory on the CA render thread. This is a synchronous wait for a genuine stage, rather than a GPU-fence wait. No placeholder shader or ignored pipeline failure is acceptable.

The exact request is canonical and structurally eligible, with58typed constants. The real Mac production worker compiles it to1888bytes. Production cache validation, factory link with static603 vertex and native emitter replay all pass, with exact uploaded native bytes. Physical use of this new stage remains pending. This publication is added as the22nd persistent stage.

## Compiler service uncertainty

The phone logs service startup once, but no dispatch/SPAWN/RUNNING/EXIT or terminal failure. Actual HFS request-root/UID-directory/file modes and owners match the worker's guards. There are62requests, below the worker's64scan cap, so that cap is not the current stall's cause. Existing retained stage work contains no evidence linking it to the new request.

The capture cannot determine whether startup/scan filesystem operations block or requests are silently skipped. Bounded phase records now distinguish root preparation, source read/hash, recipes, scan validation categories and pre-exec workspace/packing/profile operations. They do not change priority, compilation admission, waits or time limits.

## Separate finite-spool defect

The provider's64entry pending limit counts every non-dot spool file, including completed functions and terminal pipeline requests. The worker does not retire them. The current62entries leave room for only two more, after which genuinely new requests fail. This is an independently confirmed lifecycle defect, not an explanation of why the current62nd request was not dispatched. The worker now retires only authenticated terminal requests under the producer UID lock. Identity-bound claims and a durable root-private snapshot precede removal; replaced/new producer files and genuine pending requests are preserved. The archive is limited to64slots/8MiB. The opportunistic lock is nonblocking and retries later. Host tests cover64pending versus64terminal requests,300bounded rotations, all22genuine publications, interrupted writes, stale claims, replacement, corrupt publications and unsafe files. This lifecycle correction is not claimed to solve the unexplained initial phone-service dispatch absence.

## Checkpoints

Exact-stage host compilation/link/emission passes. Native UI drawing past this specialization, touch behavior and the phone compiler's exact blocking phase require the next device capture. No full USERDATA transfer is needed.

## 0217 built

XNU incremental build exits0. BOOT31,940,624bytes fits33,554,432bytes; kernel31,273,088bytes. Loader/ADT and safe DTBH bytes are exact0216. Selected whole FDT source41fde800..41ff8800 stays before42000000. Native GPU settings,4CPUs,32-sector transfers and explicit optional-test gates0 remain. The signed provider is unchanged. Final signed worker230,608bytes has4096-byte signature pages verified; all22publications pass actual payload cache validation. Source/output provenance and raw logs remain private. Physical progress past the new stage and input responsiveness remain pending.
