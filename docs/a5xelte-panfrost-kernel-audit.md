# A5XELTE kernel GPU protocol audit against released Panfrost

Date: 2026-10-21. Read-only audit. No driver changes, build, flash, or device writes.

## Baselines and limits

Protocol authority is clean Linux **v7.2.12**, downloaded from git.kernel.org `plain/...?h=v7.2.12` into `/private/tmp/a5xelte-panfrost-release-audit/linux-7.2.12`. Parent verified this release against kernel.org/releases.json. The downloaded `test-kernel-mmu.c`/`test-kernel-gpu.c` were also read; final citations below refer to their canonical files under the release directory. No A5 Linux fork is used as protocol authority. Mesa **26.2.4** clean release is available under `/private/tmp/a5xelte-panfrost-release-audit/mesa-26.2.4`; this report covers the kernel half, not shader/descriptor correctness.

Current target is staged XNU `/private/tmp/a5xelte-0156/xnu`, including source patches through 0165. GPU observed previously is `GPU_ID=07201000`: product0720, revision1000. The report separates an absent upstream protocol operation from proof that its absence caused a particular device fault. None of the static findings below alone proves the0165 fault address or stage. That run did not record AS_FAULTSTATUS/address.

Path shorthand:

- `K/` = release `drivers/gpu/drm/panfrost/`
- `I/` = release `drivers/iommu/`
- `X/` = staged XNU `iokit/Kernel/arm/`

Official primary-source entry points: https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/tree/drivers/gpu/drm/panfrost?h=v7.2.12 and https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/tree/drivers/iommu/io-pgtable-arm.c?h=v7.2.12 .

## Highest-priority confirmed source mismatches

### 1. T720 `JS_CONFIG_START_MMU` workaround is absent in both queues

**Confirmed omission, high priority.** `K/panfrost_issues.h:188-193` places HW_ISSUE_10649 in the T720 issue set. Its definition at68-69 is “MMU TLB invalidation hazards.” `K/panfrost_job.c:233-246` sets `JS_CONFIG_START_MMU` whenever this issue is present. `K/panfrost_regs.h:268` defines BIT10.

Current AS0 at `X/A5XELTEGPU.cpp:374-381` programs `(8<<16)|(3<<8)|(3<<12)`; AS1 at `X/A5XELTEGPUAS1.cpp:529-540` adds only AS number1. Neither has BIT10. These are actual hardware configurations, not merely feature-advertisement omissions. The bounded T720-only counterpart would include0x400 in every submitted AS0/AS1 job configuration. No feature-gated flush-reduction or job-chain flags should be copied blindly: T720's released feature set is `hw_features_t600` (`K/panfrost_features.h:28-34`).

This is particularly relevant to a failure after live PTE mutation, but is **not proven to be the0165 root cause**. Standalone table LOCK/FLUSH_PT does not replace this per-job erratum workaround.

### 2. Mandatory released T720 shader-core configuration is not established

**Confirmed omission, high priority.** `K/panfrost_gpu.c:117-150` derives shader quirks. T720 HW_ISSUE_10797 (`K/panfrost_issues.h:188-193`) requires `SC_ENABLE_TEXGRD_FLAGS`; T720 does not carry GPUCORE_1619, so the model<0x750 path also sets `SC_LS_ATTR_CHECK_DISABLE`. `K/panfrost_regs.h:180,212-213` identifies GPU_SHADER_CONFIG0xf04 and bits18/25, yielding **0x02040000** for this model's relevant shader configuration.

Current `X/A5XELTEGPU.cpp:115-195` powers cores without reading or writing0xf04. No other GPU source establishes these bits. Existing firmware could coincidentally have left them set; current logs do not prove that either way. Explicit T720 model-gated setup plus readback is needed to remove that dependency. The translated fragment uses texture instructions; the released issue description calls10797 a T72X compiler hardware workaround. This does not establish that every bad vertex/tiler job is caused by this register.

### 3. AS1 teardown omits released drain/flush sequence before freeing memory

**Confirmed lifecycle/protocol mismatch; actual corruption is unproven.** `K/panfrost_mmu.c:191-204` performs a locked full-address-space `AS_COMMAND_FLUSH_MEM` before zeroing TRANSTAB/MEMATTR, setting TRANSCFG unmapped, and issuing UPDATE. Enable similarly flushes previous state before replacing the root (`167-188`).

Current `X/A5XELTEGPUAS1.cpp:220-246` writes TRANSTAB/MEMATTR and UPDATE, but its `disable` branch deliberately skips the subsequent LOCK/FLUSH_PT block and never issues FLUSH_MEM. `a5g3d_as1_destroy` at739-771 releases retained surfaces, buffers, job BO and table BO immediately after this is reported applied. Normal job-end cache flushing and an idle slot are useful, but they do not reproduce the released MMU teardown contract. Before enabling general reuse/free, disable needs a verified drain, fault check, and completed root-disable update; on ambiguity retain the context, as current poison logic already does.

### 4. AS1 MMU preflight mixes masked and raw fault registers

**Confirmed polling-protocol inconsistency; mitigated by the separate FAULTSTATUS check.** AS1 update preflight/result uses0x200c at `X/A5XELTEGPUAS1.cpp:215,246`, and job preflight uses it at523. This is MMU_INT_STAT, masked by MMU_INT_MASK0x2008 (`K/panfrost_regs.h:285-289`). The current polling driver never establishes MMU_INT_MASK. If that mask is0, the IRQ portion of those checks cannot observe pending RAW bits. The same preflights also check AS1_FAULTSTATUS0x245c, which catches ordinary recorded AS1 faults; this is not proof that the current code misses every pending fault. The actual run loop correctly reads RAW0x2000 at544-549. AS0/FrameMap/DS4 checks also use RAW.

The released threaded MMU path reads RAW, captures status/address before acknowledgement (`K/panfrost_mmu.c:877-906`), then deliberately manages masks (`945-951`). A polling-only port should consistently inspect the relevant RAW AS bits without depending on an unbound interrupt mask. A zero-valued masked register is not evidence of a fault-free MMU.

## Protocol coverage by stage

| Stage | Released Linux behavior | Current coverage and exact boundary |
|---|---|---|
| SoC power, supplies, clocks | Device init uses regulator/clock/reset/PM-domain providers (`K/panfrost_device.c:22-139,216-277`); runtime resume reacquires providers before reset (`432-455`). | `X/A5XELTEGPU.cpp:777-821` verifies Exynos PMU and both gate banks before G3D access; `115-195` programs the existing Exynos clock path and GPU core power. PMIC helper `bsd/dev/a5xelte_touch.c:175-230` verifies PMIC ID and BUCK4 selector/readback, preserves enable bits. **Intentional device-specific implementation**, not interchangeable with Amlogic/Rockchip/Mediatek sequences. Domain is inherited powered; power-off/cold-boot/resume support is incomplete. |
| GPU core power order | L2→shader→tiler with bounded polls (`K/panfrost_gpu.c:452-481`). | Matches order/time budgets at `X/A5XELTEGPU.cpp:167-193`. Current implementation deliberately accepts one L2 and low32-bit masks; observed T720 topology fits. It does not implement dynamic core scaling, which T720 issue11056 explicitly warns against (`K/panfrost_issues.h:101-102,188-193`). |
| Initialization reset | Soft reset, bounded hard-reset fallback, IRQ-status cleanup, then feature discovery and power (`K/panfrost_gpu.c:61-104,511-549`). | **Missing** GPU reset/known-state initialization. Current path accepts inherited non-running JM/AS state at `X/A5XELTEGPU.cpp:560-580` and programs a private AS. Reasonable lab checkpoint, insufficient as a general native driver. A reset must preserve safe Exynos supply/bus/domain sequencing and must not enable hardware IRQs before binding handlers. |
| ID/features/errata | Reads GPU ID revision, MMU/thread/texture/JS features, 64-bit core masks and model issue tables (`K/panfrost_gpu.c:217-373`). | Product0720 check is correct (`X/A5XELTEGPU.cpp:825-836`); presence checks exist (`560-580` and AS1`511-516`). **Incomplete** revision/features/errata initialization: gaps1/2 above. Memory limits and core masks are fixed to this observed board, not advertised as generic hardware limits. |
| Mali page-table format | Four levels even for low IAS; TTBR READ_INNER|TABLE; MEMATTR0x888d88; NC/read-write outer-shareable leaf (`I/io-pgtable-arm.c:515-577,1215-1264`). | **Matches** four4KiB levels, TTBRphysical|7, MEMATTR0x888d88, PTE0x2c1 (`X/A5XELTEGPU.cpp:606-629,713-719`; AS1`151-194,224-231`). Explicit software bounds below4GiB are narrower than possible hardware PA/VA support, not an erroneous Mali encoding. |
| Page-table publication | Noncoherent PTEs are DMA-synchronized (`I/io-pgtable-arm.c:350-389`); command writer waits for AS_READY (`K/panfrost_mmu.c:72-100`). | Whole table/BO CPU Store plus barrier is present. Bounded AS waits present. XNU board header does **not** set `__ARM_COHERENT_IO__`; real noncoherent cache routines are selected, not the Apple-only no-op branch (`pexpert/pexpert/arm64/A5XELTE.h`; `iokit/Kernel/IOMemoryDescriptor.cpp:3907-3928`; `osfmk/arm/caches.c:145-239`). This audit does not prove every XNU/CPU bulk-cache dispatch detail at runtime. |
| Live TLB invalidation | Lock naturally aligned power-of-two range then FLUSH_PT; wait completed (`K/panfrost_mmu.c:103-150,383-394`). | **Matches after patch0164** in DS4: TestVA|15 covers64KiB, bounded checks before/after commands. FrameMap0..128MiB lock covers its fixed windows (`X/A5XELTEGPUFrameMap.cpp:69-91`); AS1 lock128MiB at10000000 covers surfaces/jobs/buffers (`AS1.cpp:234-243`). Gap1 still applies independently at job start. |
| Job submission | HEAD_NEXT, affinity, AS number, priority8, start/end clean+invalidate, erratum START_MMU, START (`K/panfrost_job.c:203-268`). | Correct field locations, priority, affinity and cache flags in AS0/AS1. Global CAS reservation serializes physical JM use. START_MMU is missing. No arbitrary user-provided GPU addresses or descriptors accepted. |
| Completion | IRQ-backed scheduler, fences, sampled JS_STATE ACK rules (`K/panfrost_job.c:433-630`). | Serialized raw-register polling, finite200ms polling then10ms idle wait; no real GIC IRQ handlers. Correctly requires DONE, no ERR/MMU/GPU error, idle/current state, terminal header and requested output proof (`X/A5XELTEGPU.cpp:383-479`; AS1`540-595`). This is bounded queue proof, not a general asynchronous GPU scheduler. Polling consumes CPU and has a fixed workload ceiling. |
| Fault/recovery | MMU status/address/access/source decoded before clear; disable offending AS (`K/panfrost_mmu.c:877-935`); JM soft-stop/reset/fence error/requeue (`K/panfrost_job.c:657-804`). | **Deliberately limited**: queue permanently poisons and pins on ambiguous jobs instead of recovery. Safe against uncertain reuse but one failure disables acceleration until reboot. New AS0 snapshot captures AS status/address/current JS_HEAD before clear; AS1 lacks corresponding full fault-address and JS-head logs. GPU global fault status/address (0x3c/0x40/0x44; released gpu.c26-57) are not captured by either queue. |
| Memory retention | Kernel GEM/VM references and DMA mapping remain through render fence/unmap; MMU disable drains before release. | Positive: IOBuffer backing and SweetSurface references retained; every imported page validated; AS1 poisoned context retained at`739-759`; FrameMap uncertain source retained at`249-252`; AS0 service owns test backing at`908-909`. AS1 normal teardown drain gap3 remains. No existing root/partition writes are part of GPU paths. |

## Cache and interstage details needing care

1. Current DS4 now invalidates **all48KiB private data** after vertex+tiler before the following whole64KiB CPU clean (`X/A5XELTEDownsampleSelftest.inc:168-176`). This includes GPU-written varyings, polygon data, and its separate4KiB heap. It is correct coverage for this fixture.
2. AS1 re-cleans its whole8KiB job BO at every stage (`X/A5XELTEGPUAS1.cpp:525-527`), but interstage explicit invalidation covers only0x1000..0x2000 at703-704, plus individual headers in run_job. The translated read_surf fixture also writes vertex/varying scratch in page0. **Confirmed range omission; corruption is a hypothesis**, because whether a stale clean CPU line is subsequently dirtied/evicted depends on actual cache traffic. Broaden invalidation to all GPU-written descriptor/scratch ranges before whole-BO cleaning, or prove non-overlapping dirty-line ownership for every supported profile. Do not substitute CPU-generated varyings or pixels.
3. AS1 source/destination CPU Store before GPU work and destination Flush after terminal completion are present (`AS1.cpp:672-681,717-719`). PTE/table synchronization is present. Surface retains protect allocation lifetime, but they are not a general userspace write/read hazard protocol; generic Metal queue hazards/resource transitions are beyond this kernel-only bounded contract.
4. Released JS start/end cache clean+invalidate flags are present and must remain; CPU cache operations, GPU cache operations, and MMU TLB operations serve different domains. One does not replace another.

## Confirmed constraints versus unproven explanations

- **Confirmed protocol omissions:** START_MMU erratum flag; T720 shader quirk establishment; AS1 teardown FLUSH_MEM; masked-fault reliance; no reset/recovery/IRQ/native PM lifecycle; reduced feature discovery.
- **Already corrected current-source omissions:** DS4 live PTE flush and full interstage coverage; empty tiler heap corrected in its builder/private payload. These are not still missing in patch0164.
- **Not proven:** exact0165 fault VA/access/source; whether vertex or its linked tiler faulted; whether stale mappings, shader configuration, heap size, descriptor ABI, or instruction semantics caused it. JS_HEAD and AS_FAULTSTATUS/address in the next failed run can distinguish these.
- GPU_RAW0x700 observed after power is reset/power event bits8-10, **not** the error mask0x81 (`K/panfrost_regs.h:27-46`). Do not report it as a GPU error.
- On0165 fragment fence0 was never submitted; its zero pixel/source/guard counters were unevaluated, not observed corruption. Current source explicitly logs submitted/evaluated.
- Stock Metal device acceptance in a userspace probe proves device discovery, not these kernel job protocols or complete iOS rendering. Backboardd fragment-function SIGABRT is a separate higher-layer failure.

## Recommended implementation order after this audit

1. Apply the **T720-specific released** per-job START_MMU and shader-core quirk configuration consistently to AS0 and AS1, with ID/revision/config readback. Keep Exynos7580-specific power/clock/PMIC registers and safe checkpoint values.
2. Unify bounded MMU command/RAW-fault helpers and implement drain→disable→completed-update before AS1 normal teardown. Preserve all resources on every uncertain exit.
3. Give AS0/AS1 one complete read-only fault snapshot contract (AS-specific status/address/source + current JM head/status + global GPU fault registers), captured before acknowledgement/reset. Preserve terminal-vs-unsubmitted distinctions.
4. Make descriptor/scratch cache ownership explicit for each real shader chain; retain whole48KiB DS4 invalidation and audit read_surf page0 interstage writes.
5. Add properly bound GPU/MMU/JM interrupts, asynchronous completion/timeouts, model-aware reset and fence cancellation/requeue only after the bounded native path works. Integrate Exynos domain/clock/regulator resume with that reset flow. Merely copying Linux DRM scheduler APIs into XNU is not an implementation.
6. Keep resource/pipeline/compiler coverage separate from kernel protocol success. Hardware pixel verification of the actual translated pair remains required before claiming it renders iOS work.

## SoC/model boundaries: do not copy these unrelated paths

- Amlogic GPU_PWR_KEY/OVERRIDE1 workaround (`K/panfrost_gpu.c:105-115`) is explicitly T820/G31/G52 Amlogic integration; it is not an Exynos7580 power recipe.
- T76x tiler clock-gate override (`K/panfrost_gpu.c:153-159`) does not apply to the T720 issue set.
- TLS hashing, job-chain disambiguation and flush-reduction must follow released **T720** features, not a newer G-series model. `hw_features_t720` aliases t600, which carries THREAD_GROUP_SPLIT and V4 (`features.h:28-34`).
- Do not replace Mali-LPAE with AArch64 page tables just because newer SoCs force that quirk; released MMU selection retains Mali-LPAE by default (`K/panfrost_mmu.c:777-795`).
- GPU feature masks/VA widths can be read from the observed hardware, but Exynos PMU/CMU/BUCK wiring and clock parent semantics must continue to come from the actual Exynos7580 board reference. Current safe fixed-clock behavior is not proof of its exact frequency or optimal throughput; those require measured clock/OPP evidence.

## Audit result

The existing driver is a bounded private queue with several correct Panfrost primitives and strong ambiguity pinning. It is **not yet equivalent to released Panfrost initialization/job/memory lifecycle**, and the two omitted T720 erratum operations are directly actionable. The report intentionally does not identify a definitive runtime root cause without the missing fault registers and a real translated-job rerun.
