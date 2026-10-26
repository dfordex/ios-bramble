# 0243: scheduling overlap, eight-draw groups and terminal upload reuse

## Changes

### 1. Separate scheduled acceptance from terminal completion

Previously, a command buffer on the configured asynchronous submission target
remained Committed throughout its synchronous kernel work. Its scheduled
handlers and `commitAndWaitUntilSubmitted` consequently waited until GPU
completion.0242b captures scheduled waits ending in Completed, and backboardd
does configure asynchronous submission/completion targets.

After dependency registration and dependency readiness, the real submission
worker now publishes Scheduled and dispatches scheduled handlers before entering
the private backend. `commitAndWaitUntilSubmitted` can return at that point,
allowing the caller to prepare independent CPU work while GPU execution
continues on its submission worker. This state means software-queue scheduling,
not a hardware completion fence. The unconfigured synchronous submission path
retains its prior behavior; the observed configured backboardd path benefits.

Resources remain retained and dependency tickets remain outstanding until the
kernel work returns with validated terminal fences. An encoding/dependency
failure still returns Error. A later execution failure still reaches completion
as an error, after having been scheduled. No public GPU timestamp is fabricated.

Scheduled callbacks use the configured completion target or an owned serial
fallback. They do not run inline on the submission worker. With no configured
target, terminal callbacks drain through the same fallback after real terminal
state; a queue-specific reentrant path avoids self-deadlock. A scheduled handler
may wait for completion without preventing the GPU worker from completing.

### 2. Eight immutable native snapshots per compatible group

The matched native ABI and kernel cap increase4to8. The request header remains
24B; the fixed result expands192to352B. Patch0223 and the provider must be
installed together. An old smaller result buffer is rejected by kernel size
validation before START; this is not a claim of wire compatibility with old
providers. The four mapped surface/buffer slots are unchanged.

All items still require matching resource bindings/mapping epoch and undergo
complete preflight before any item starts. Jobs execute in order and each item
returns real ordered tiler/fragment fences. CPU aliases are cleaned once and
completed outputs reconciled once per compatible group. Mapping changes,
mutations, capacity boundaries and explicit barriers still drain pending work.
Fault/timeout poisoning and resource retention remain intact. Larger groups
help compatible draws; they do not guarantee that every live frame has eight
compatible items or fewer hardware jobs.

### 3. Reuse terminal upload allocations between command buffers

Real service-backed Metal devices now retain up to four idle upload arenas,
each at most1MiB. The cap is4MiB of kernel BOs plus4MiB of CPU staging shadows;
larger transient arenas are released normally. Each reused arena resets its
staging offsets after terminal proof. New bytes are copied to disjoint slices
and uploaded before the next START. Query caching is reset for each session;
old mapping epochs are not carried forward.

This avoids repeated allocation/release and resulting mapping churn for common
small uploads, reducing work under the existing device transport lock. The
lock itself remains around transport/session mutation and execution; removing
that protection would race shared client state. An active or unsubmitted slice
cannot be evicted. Ordinary private-buffer allocation under four-slot pressure
evicts only idle terminal arenas, restores the output reply capacity, and retries.
Device teardown releases idle cache ownership. Faults, malformed replies and
failed releases quarantine handles and prevent unsafe reuse.

## Tests and build evidence

- Actual kernel preflight/dispatch under ASan/UBSan validates eight ordered
  terminal items, single image clean/flush, later-item preflight rejection,
  mapping-epoch rejection, wired descriptor snapshots and fault poisoning.
- Actual C batch transport tests8+3 grouping, query caching, mutation/mapping
  barriers, abort, real fences and malformed/fault ownership.
- Actual arena tests8+8 groups, immutable bytes, allocation reuse across two
  command buffers only after terminal proof, idle eviction, pending-slice
  protection, write failures, abort, fault and release quarantine under
  ASan/UBSan.
- Actual Metal/IOSurface alias integration holds the first transport fence:
  Scheduled and submission acceptance become observable while completion and
  CPU alias reads remain blocked. The scheduled handler itself waits for
  completion without deadlocking the GPU worker. Cross-queue storage order and
  failed-fence quarantine pass under ASan/UBSan.
- Actual public private-buffer factory fills all four slots with an idle arena
  and three buffers. The fourth buffer evicts the idle arena and succeeds, with
  reply capacity restored and all ownership cleaned up; ASan/UBSan passes.
- Actual native603 API/emitter test executes eight shifted buffer-backed
  snapshots as one transport group/one bulk upload, preserving resources,
  offsets, fences and cleanup. Actual phase diagnostics and the public legacy
  Metal API/queue/callback suite pass under ASan/UBSan. The legacy suite is built
  without the native registry as intended; using the native-registry template
  first gave an unrelated authenticated-function diagnostic mismatch.
- IOSurface tests required host IOKit access outside the sandbox. The initial
  sandbox run failed resource allocation, not a driver fence assertion.
- Strict new-patch reverse/apply roundtrip is byte-exact. The provider/probe
  are built for iOS16/Cortex-A53, whole-bundle codesign and4096-byte signature
  pages pass. Full XNU make returns0.

The prior sampled CPU wall timings are included. They measure dispatch,
dependencies, backend/lock/operations/drain, retirement and callbacks; they are
not isolated hardware GPU timestamps. The last waiting fragment is also
included as a genuine1568B host publication after strict production-cache
validation. Its physical execution remains unverified.

## Packaging and installation

The actual403-file installer stream/policy preflight passes. Linked segments,
all payload CRCs,39 compiled publications,270 original selected-app files and
metadata, all seven PosterBoard files/resource seal, original loader/DTBH and
startup arguments are verified. PosterBoard's existing selectedLockPath issue
is not modified by this performance image.

Kernel25451128B; BOOT26118160B, SHA256
`c594e57bd24c70dd845826848d9030237243d28bb566ebd7755afd6b5bf8d737`.
Four CPUs/736MiB/iPhone10,5/D211AP/32-sector I/O and native GPU/full-frame
comparison-disabled presentation are retained. Recovery/model/TWRP/canonical
BOOTp10/capacity guards pass; offset-zero write acknowledges all26118160bytes,
sync returns0 and reboot is requested. No BOOT backup/readback/hash or whole
USERDATA transfer is performed.

This proves implementation, local contracts, build and installation. A physical
FPS gain is not established. The user was asked to repeat the stopwatch, Home
and scrolling test, then return to TWRP for actual copy rate, schedule/execution
times, group sizes and upload reuse receipts.
