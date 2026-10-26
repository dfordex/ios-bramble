# 0242b: stopwatch observation, PosterBoard progression and CPU wall timing

## Phone results

The user observed the Clock stopwatch advancing in half-second steps and an
otherwise very slow interface. This is consistent with the independently logged
peak actual panel-copy rate2.201/s. It is not a controlled benchmark of the Clock
app's own requested update frequency.

Read-only SYSTEMflush62 contains599380 recovered bytes/6589 decoded lines, no
ring overwrite. There are152 GPU and3 CPU panel copies, one GPU fallback,
154self/missing-source records and312shown records. The reported4.4shown/s
includes no-ops. Reconstructed presentation cost is12.899ms/copy, with weighted
pending age25.209ms. These measurements cannot explain a half-second frame
interval by final scanout work alone. No fixed half-second throttle has been
identified; upstream preparation, scheduling, dependencies and native rendering
still need separate timing.

All65 captured command-buffer results are Completed/error0. All37 sampled groups
complete/status0:21size1,14size2,one size3,one size4; last sampled group1856.
These are samples, not the full group-size distribution.32native receipts have
status0/MMU0;308AS0fencescomplete/MMU0;128native phases result0. Eight4096-point
panel/source grids mismatch0. Two admission-contention receipts recover after
9124/1215us; there is no unavailable/deadline or mapping-failure receipt. There
is no captured kernel panic or SpringBoard/backboardd crash. Driverkitd again
has one namespace1/code7 memory-limit SIGKILL.37touch/20key records continue.

## PosterBoard: original repair executes, next invariant fails

The startup shim is installed. Its first-time setup receipt reports unloaded
extensions with an existing empty configuration, resets only that empty state,
calls the original method and records its return with a configuration object.
This verifies execution beyond the earlier configuration-slot assertion.

PosterBoard then SIGTRAPs with **Invalid condition not satisfying:
selectedLockPath** and later relaunches. This is a different unresolved invariant;
successful return from the setup method is not complete PosterBoard startup.
No new assertion bypass, fabricated selected path or preference reset was added.

Limited directory inspection initially found no `/System/Library/Wallpaper`,
but the actual `/Library/Wallpaper` exists with its default plist, Stills and nine
collections. The system default selects wallpaper7400. Its iPhone8Plus-sized
414w-736h@3x wallpaper plist and animation files exist. Five associated HEIC
entries initially show zero-length data forks because they are HFS hardlinks.
Resolving the hidden inode records gives real lengths808440,677535,65125,608897
and310057bytes with allocated blocks. Therefore these entries are **not proved
missing or empty**; duplicate asset installation is not justified by the first
catalog listing. Metadata presence does not establish that every asset decodes
or every PosterBoard extension/resource is available.

The expected mobile PosterBoard directory and its preference file are absent at
the explicitly inspected paths. How stock migration, selected poster creation,
extension availability and the data container produce selectedLockPath is still
unresolved. The next fix must establish the real path/state contract, rather
than replace this assertion with success.

## Another shader publication wait

A new fragment request waits near the end. The phone translator exits0 after
40.872s, then starts the native backend. No terminal native publication is in the
captured log or the bounded project-file read; only the3836B request is found.
This is not an unsupported-lowering verdict or proof of a permanent hang.
Mac replay through the actual worker and released backend produces a genuine
1568B fragment with four resources/two pushes; SPIR-V, hashes and production
cache-loader ASan/UBSan checks pass. This remains a private host publication,
not installed or executed on the phone. Earlier2704B explicit dynamic acceptance
is not captured either; do not infer its use from successful later draws.

Final storage counters show3012937216B read/112881664B written/zero errors and
576859ms cumulative active time.15340718ms summed lock wait overlaps between
callers and is not wall time. Per-process I/O attribution and its effect on the
steady stopwatch interval are not established.

## Prepared timing instrumentation: source only

`A5MaliTiming.h` provides monotonic CPU wall-clock microseconds. The public
Metal GPU timestamp methods remain zero; CPU time is never advertised as GPU
execution time. Receipts sample the first eight operations, then every64th up
to serial16384, independently of the early diagnostic budgets.

| Receipt | Measured intervals |
| --- | --- |
| Metal timing | Resource registration, dispatch wait, dependency wait, private backend execution, retirement and total commit-to-terminal wall time |
| Backend timing | Device-lock acquisition, batch begin, operation preparation/execution, terminal batch drain and retirement |
| Callback timing | Completion-dispatch wait and handler execution |

Backend execution and drain can include CPU encoding, kernel calls, coherency and
GPU waits. They are not isolated hardware GPU timestamps. Existing real-fence,
ownership, failure, retirement and callback ordering is unchanged.

The actual phase-diagnostic integration test now queues a buffer behind a
suspended dispatch target and verifies that a real20ms delay appears in queue
timing. It verifies successful completion, both failure paths, backend/callback
receipts, unchanged zero public GPU timestamps and exclusion of resource tokens.
ASan/UBSan pass after correcting the test fixture's transport-context lifetime
to outlive its autorelease pool. That fixture issue is not a phone driver bug.
Both modified implementation files also compile for iOS16/Cortex-A53 with
warnings-as-errors.

No new full XNU/BOOT image or device write was made in this follow-up.0242b
remains the installed image; these timing receipts need a later integrated
image and fresh runtime before attributing the low FPS to a specific stage.
