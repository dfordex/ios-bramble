# 0239: presentation cache, shader prewarm and native batches

## Scope

Implements the first three priorities from the [0238 runtime review](a5xelte-0238-runtime-optimization-review.md). Runtime speed and physical rendering remain unverified for this image.

### Preserve useful presentation history

Patch0217 removes unconditional shadow invalidation before the CPU fallback loop. Self/framebuffer, empty and rejected-allocation presentations do not mutate pixels and now preserve the comparison history. A real CPU fallback invalidates immediately before its first copy. Fade/fault invalidation remains.

IOSurface write-unlock and successful typed/native GPU writes advance a surface write epoch. Frame presentation compares the panel epoch with the saved epoch before reusing its shadow, and remembers the new epoch only after real GPU completion. This catches tracked panel writes from other paths without discarding history for no-ops. Unannounced writes outside the surface ownership/unlock contract are not tracked.

The existing full-row comparison, identical-frame skip and aligned partial transfer remain enabled. They still cost CPU comparisons and an8.29MB shadow; this is not proof of a net FPS gain. Self-present pacing and the display statistics' no-op accounting are separate remaining work.

### Precompile exact known demands

`tools/a5xelte-prewarm-shaders.py` uses authenticated captured request identities, stock AIR translation and the released Mesa backend to produce genuine persistent stage triplets outside the checkout. It validates publication metadata, code/reflection and the actual production cache loader under ASan/UBSan.

Four exact fragment variants are embedded before launchd:1104,1760,880 and2128B. The first three native programs match previous phone-produced bytes exactly; the fourth previously lacked a terminal publication. Its physical execution is pending. This warms known requests, not every future function/constant/state combination. The existing phone worker still handles unseen requests.

The shared backend now lowers variable initializers before preprocessing on both host and device; the device adapter previously inserted this pass itself. Tool discovery accepts absolute released-Mesa source paths. The phone worker/backend bytes are unchanged from0238. Patch0219 raises the bounded embedded compiled-stage limit32→64 so36 complete publications fit; validation and metadata rules remain.

### Submit bounded groups and coalesce coherency

Patch0218 and the provider add selector20/capability64 with at most four256KiB job snapshots per group. Groups require the same mapping epoch and all resource tokens. Query results may be reused only inside that session; mapping changes and other transport operations flush pending jobs first.

The kernel snapshots and validates every item, descriptor/job chain, token, epoch and access before any GPU start. It holds resource ownership across the group, cleans the union of images/buffers once, runs existing native jobs in order and flushes written CPU aliases at the end. Each completed item has a real ordered hardware fence. Fault/timeout or uncertain coherency poisons/quarantines resources; no synthetic completion is returned.

The command buffer completes only after the final group is flushed. Preparation abort discards unstarted pending jobs; sticky errors prevent resubmission. Legacy kernels retain the single-submit path. This is bounded submission/coherency batching: hardware stages are still serial and descriptor snapshots remain256KiB per draw. It is not a fully asynchronous queue or a persistent render pass.

## Verification

- Actual framebuffer fallback ASan/UBSan: self/empty preserve cache; real CPU mutation invalidates; invalid allocation never copies.
- Existing real band planner/released-v4 descriptor and80-transition pixel model pass.
- Actual kernel batch implementation with mocked MMIO: all-item preflight before start, four ordered real fences, one image clean/flush, write epochs, partial-busy cleanup, fault poisoning and balanced wired snapshots pass ASan/UBSan.
- Actual provider transport and command-buffer batch tests pass ASan/UBSan:4+3 and4+4+1 grouping, query reuse, mutation/mapping barriers, abort, real completion, malformed/fault quarantine and legacy fallback.
- All18 native wrapper regressions pass. Signed iOS/A53 provider builds with4KiB signature pages. Kernel patches round-trip.
- Full XNU make exits0. Actual386-file installer preflight passes ASan/UBSan without filesystem writes. Final linked segments, embedded CRCs, four prewarm publications and270 original app files/metadata match the BOOT package.

## Package and installation

- BOOT25,837,584B; kernel25,170,640B; provider1,000,448B.
- Payload386files:17,666,890raw/3,807,476packed bytes,36 compiled publications.
- BOOT SHA256:`1c745ce12425b0c26197500e0f84dce43e219f488254a2664ba409b1b8ddc959`.
- Loader/DTBH exact0230; ADT identity iPhone10,5/D211AP retained. Boot arguments match0238. Four CPUs,736MiB,32-sector storage and functional quiet input retained.
- Guarded TWRP/model/p10/capacity checks pass. Offset-zero BOOT write acknowledges all25,837,584bytes; sync0 and reboot requested. No BOOT backup/readback or whole USERDATA transfer.

Private image, shader publications, build/test logs and installation receipt are retained under the workspace research build0239 directory, outside git.

## Next runtime evidence

After interaction and return to TWRP, recover the complete SYSTEM log. Check native batch group counts/completions/coherency, partial/unchanged presentations and copied bytes, shader cache hits/publications, process crashes and physical UI response. Existing PosterBoard null external-surface/zero-geometry and unnormalized-sampler gaps were not part of these three changes. No runtime FPS improvement is claimed yet.
