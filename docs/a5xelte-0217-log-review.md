# 0217 UI stall: synchronous producer flock

## Verdict: confirmed provider wait; physical correction pending

Full SYSTEM capture is flush53,412,111logical bytes; decoded411,866bytes/5,180lines. No panic/CRASH record. User reports visible UI with no useful Home/Power/touch response.

| Evidence | Observation |
| --- | --- |
| Backboardd command buffers2–6 | status4/error0/submitted1; three sampled GPU-present intervals and matching sampled source/panel pixels |
| HID queue | consumer head advances to10,240; full0, including after drawing stops |
| New fragment |1888bytes installed successfully and its original request retired; no captured runtime acceptance yet |
| Compiler | source read/hash and all five recipe reads complete; scanner retires14authenticated terminal requests |
| Backboardd render thread534 | syscall PC1ce20433c/LR1056449f0; caller1056064a0 |
| Exact shipped provider | load base1055f0000: return offset549f0 follows `bl _flock` at549ec with argument2=`LOCK_EX`; caller1649c invokes request forwarding inside pipeline factory |
| Fresh read-only HFS catalog | one identity-bound retirement claim remains; archive slot13 holds the preceding completed request |

This is not a captured GPU fence hang or the prior nanosleep shader-publication wait. The old producer used blocking flock even for diagnostic pipeline forwarding.0217 terminal retirement introduced a second holder that retains the UID lock through publication reads, private-claim recovery and several fsyncs. The retained claim and stopped retirement are consistent with that holder; the worker itself was outside the sampler target list, so its precise blocking syscall/lock ownership is not directly captured. HFS read/write latency may contribute and is not declared solved. Touch detail logging remains0, so no contact-hardware failure is inferred from absent logs.

## 0218 correction

- Compute the existing validated owner-bound request identity without opening the spool. Load/authenticate an actual cached stage before enqueueing. Diagnostic specialization logging no longer publishes the same dynamic function request first.
- Producer flock uses LOCK_NB and returns a distinct Busy result with the validated identity. Missing-stage specialization retries enqueue after100ms while checking actual publication; it does not substitute a shader or silently accept a failure. Existing compiled-pipeline factory admission remains independent of optional request forwarding.
- Root-private preparation/recovery happens before taking the UID lock. After atomic identity-bound claim rename, release the UID lock before any durability sync/archive/publication read. Producer replacements/new leaves remain protected; authenticated terminal/quota/archive contracts remain unchanged.
- Add the compiler process to the existing bounded thread sampler and bounded retirement phase records to locate any remaining service I/O wait.

## Validation

The real1888-byte captured fragment and static603 vertex both load through the actual stock-library function path while another descriptor holds the producer lock; the factory accepts the genuine pipeline, no request leaf is written, and the process completes under a10-second watchdog. The direct request test passes exact identity, Busy return/retry, corrupt/symlink guards,64pending quota and16concurrent writers. Retirement tests pass all22genuine publications,300bounded rotations, replacement/stale-claim cases, and explicitly reacquire the producer lock in the after-claim hook. Diagnostics tests and actual Cortex-A53 iOS provider/worker Werror builds/signature-page validation pass.

Source-backed tests do not prove interactive UI recovery. New physical capture must confirm that drawing proceeds beyond the previous factory call and that Home/Power/touch cause visible transitions. Raw logs, captured request identities and shader programs stay private.
