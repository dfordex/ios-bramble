# 0241: immutable upload arenas and pre-START queue admission

## Scope and established causes

The [0240 readout](a5xelte-0240-runtime-review.md) shows approximately5 actual panel copies/s despite the final presentation path costing about13ms. Two source-level causes are addressed here:

1. Every native draw allocated/uploaded/released temporary BOs. Those transport mutations flushed the new bounded group before the next draw, and invalidated query reuse.
2. AS1 mapping and native submission attempted the shared runtime queue once. An existing AS0 presentation reservation could reject a never-started native group asBusy; mapping collapsed an updateBusy into a false result and Query17NoResources. Actual0240group1385 was rejected before any item started. The exact cause of every earlier NoResources is not established.

This implements functional changes and diagnostics. No physical FPS gain or universal resource-exhaustion fix is claimed before the new phone run. PosterBoard's separate switcher-state assertion is unchanged.

## Immutable upload arenas

`A5MaliStageNativeUploads` collects each draw's actual immutable CPU snapshots into disjoint64-byte-aligned ranges of retained real kernel BOs. There are at most four lazily allocated arenas, starting at256KiB and growing to at most8MiB each. The existing four-buffer/32MiB maximum is retained. CPU staging allocations have the same bounded maximum; they are not GPU-visible aliases.

The Metal producer folds the returned arena offset into each actual image/storage-buffer binding. Public offsets, texture row/image strides, native resource limits and shader validation remain. A legacy/nonbatch connection retains the old upload route. Real buffer handles and query spans are used, not placeholder GPU addresses.

Pending dirty ranges are bulk-written with the original transport immediately before actual native group submission. Uploads are CPU-only until then; a write failure starts no pending GPU jobs. Query reuse is valid because suballocation does not replace a mapping. New range data cannot overwrite ranges referenced by pending work. A full arena first flushes real pending GPU jobs and only then resets offsets; growth/eviction also occurs after real completion. Ordinary buffer allocation pressure can evict an idle arena, but not a range handed to the current unsubmitted draw.

The previous per-draw release loop only handles legacy allocations. Session-owned arenas survive until the command buffer's final group is terminal. Preparation abort discards unstarted work. Fault/timeout/malformed completion keeps real kernel allocations owned and records their tokens in a bounded connection quarantine; another batch cannot recycle that connection's arenas. Failed unmap/release also retains ownership. CPU-only staging memory can be freed independently of pinned GPU backing.

Existing packet validation, same-mapping/epoch requirements, four-snapshot limit, mutation barriers and genuine ordered hardware fences remain. This does not implement one persistent tiler pass or a fully asynchronous hardware queue. A surface/mapping change can still require a group boundary.

## Coherency

The kernel's private buffers have no CPU user mapping and supported native jobs read them. All CPU mutation entry points already synchronously perform IOStore: zero-filled createBuffer, transferBuffer(write), and nativeBulkWrite. Repeating a whole-allocation IOStore for these BOs before every native group was redundant, particularly for arenas whose capacity exceeds the used range. Patch0220 removes that repeat; actual bulk stores still cover every newly uploaded byte before GPU START. Surface image coherency and terminal output flushes remain.

## Queue admission

Patch0220 adds a shared runtime acquisition waiter used by AS1 page-table update, typed submission and native submission. It retries acquisition only while another reservation exists, sleeping1ms between checks with a2s deadline. It returns promptly for poisoned or unavailable queues. It never resubmits a started GPU job and does not suppress a timeout/fault or manufacture a fence. Current AS0 reservation owners do not acquire the AS1/client locks held by these callers.

Mapping errors still return a real failure when validation/allocation/admission cannot complete. Bounded diagnostics now identify invalid logical handles, missing context, victim-unmap failure, protected capacity, surface-map failure and buffer-map failure. Admission logs report recovery/unavailable/poison/deadline plus elapsed time. This distinguishes contention from genuine capacity/layout problems in the next device readout.

## Verification

- Actual arena/session code under ASan/UBSan: eight distinct immutable snapshots become4+4 real terminal groups with one allocation/two writes/one query; uploaded bytes and disjoint offsets are consumed by mocked GPU jobs. Capacity rollover and growth prove prior fences before overwrite/release. Abort, upload failure before START, allocation pressure eviction, current-draw protection, release failure and uncertain ownership pass.
- Actual Metal buffer-texture API/factory/emitter path passes six copy/blend/RGBA/BGRA cases: eight draws in4+4 groups, real offset-adjusted native texture descriptors and snapshot bytes, one allocation and fence-based cleanup. Repeated under ASan/UBSan. Host transport is mocked; this is not physical pixel proof.
- All18 previous native regression executables pass; the new arena integration makes19. Existing actual transport/command-buffer batch tests, real kernel batch preflight/terminal/fault tests, and lazy mapping negative/positive cases pass. Actual admission helper with deterministic scheduling passes immediate success, delayed acquisition, poison/unavailable rejection and2s deadline without retrying a job.
- Strict six-file patch0220 roundtrip reproduces staged kernel bytes. Full XNUmake0; signed iOS/A53 provider and4KiB signature pages pass. Actual386-file installer preflight passes ASan/UBSan without filesystem writes. Final linked segments/embedded CRCs/36stage triplets/270original app files and metadata verified.

## Build and installation

BOOT25856016B, kernel25187768B, provider1000736B. Payload386files/17667178raw/3809315packed bytes. Worker/backend/startup helper are unchanged; only the provider changes among old payload files. Loader/DTBH remain exact0230, iPhone10,5/D211AP and4CPUs/736MiB/32-sector storage retained. Boot arguments match0240, including continuous comparison off. Selected DT staging remains below0x42000000.

BOOT SHA256:`c91f0a3f0bfa89136edce1870ae7e4d27636d7c2447fb1a992a0937296ea4baf`.

Guarded recovery/model/TWRP/p10/capacity checks pass; offset-zero BOOT write acknowledges all25856016bytes, sync0 and reboot requested. No BOOT backup/readback or whole USERDATA transfer. Private package/build/tests/install evidence retained under workspace research build0241, outside git.

## Pending device evidence

Measure actual group sizes, arena creates/writes/resets and admission waits alongside real panel-copy rate, current resource errors and physical UI response. Capture any remaining mapping failure's exact phase. Successful host groups and a written BOOT do not establish improved animations or resolved PosterBoard state.

## 0241b allocation-pressure follow-up

When a regular allocation first returns NoResources, a transport may zero its output-size argument. The arena eviction/retry path now restores the original output capacity before retrying. The pressure test explicitly models that reset and requires the restored32-byte reply space. Actual batch/arena/command-buffer ASan/UBSan tests pass again; signed provider build, full XNUmake and actual386-file preflight/final segment checks pass.

0241b keeps the same kernel code, boot arguments and size25856016B; provider1000720B. SHA256:`bb853cceca0472b483c60a4b4e8ce2fb49514c37a0d7834d3f1c6c993275a885`. It is a prepared private artifact, not yet written: the phone is absent from ADB after starting0241. The user was asked to return to TWRP; recover the first trial's log before writing the follow-up. Do not conflate0241's installation receipt with0241b.
