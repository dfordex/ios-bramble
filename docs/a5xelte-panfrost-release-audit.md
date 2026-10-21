# A5XELTE GPU audit against released Panfrost

Date: 2026-10-21. Audited A5 source: `81013a5`, with XNU patches
`0001`–`0165` applied in the existing staging tree. Latest phone trial: **0169**.
This is a source comparison and a review of recovered phone evidence. No new
kernel, provider or disk image was installed during the audit.

## Reference and scope

The user's development A5 Linux driver is **not** the GPU protocol reference
for this audit. Two distinct released upstream components are needed:

| Layer | Pinned reference | Provenance |
| --- | --- | --- |
| GPU kernel driver | Linux **v7.2.12**, `drivers/gpu/drm/panfrost/`, plus `drivers/iommu/io-pgtable-arm.c` and the DRM UAPI header | [kernel.org release metadata](https://www.kernel.org/releases.json), [stable tag](https://git.kernel.org/stable/h/v7.2.12). Individual files retrieved from the official stable repository with `?h=v7.2.12`. |
| Compiler and userspace command stream | Mesa **26.2.4**, released 2026-10-01 | [official release notes](https://docs.mesa3d.org/relnotes/26.2.4.html), [source archive](https://archive.mesa3d.org/mesa-26.2.4.tar.xz). Archive SHA-256 verified: `bce5f7fbebb934373b86c999a064d52fb5065878dc57f287f95346648ec832e9`. |

A clean archive extraction was compared with the Mesa tree used to build our
tools: **591 release files** under `src/panfrost`,
`src/gallium/drivers/panfrost`, the Panfrost documentation and top-level
version/build files were compared. The only difference among those release
files was the added `a5_t720_copy_shader` executable in
`src/panfrost/meson.build`; the compared upstream compiler and command-stream
source files were unchanged. Additional local tool files are our adapter,
not upstream release code.

Upstream file/line references below mean these pinned releases, not a moving
`main` branch. `arm/` references mean `iokit/Kernel/arm/` in XNU after applying
the repository's patch series; their durable source is `xnu/patches/`.
Repository `userland/` references are direct tracked source files. Generated
Apple shader artifacts and the recovered raw console ring remain private.

Panfrost separates a Linux kernel driver, a userspace compiler and a graphics
API implementation. Our XNU kernel and Metal provider replace much of that
stack with custom code. Calling Mesa's compiler does not mean that its
resource tracking, state emission, scheduler or graphics API was ported.
The [upstream support matrix](https://docs.mesa3d.org/drivers/panfrost.html)
identifies T720 as **Midgard v4**, with no PanVK Vulkan support. Panfrost does
not supply an iOS Metal provider. The adapter must implement that contract
independently. Exynos PMIC/CMU/DECON registers remain board-specific; upstream
GPU protocol checks do not justify copying another SoC's power overrides.

## Latest phone evidence: 0169

The recovered SYSTEM ring contained flush 2 and 22,644 raw bytes, with no
overwrite. Both translated vertex/tiler and fragment jobs completed:

| Measurement | Result | What it establishes |
| --- | --- | --- |
| Vertex/tiler fence 3 | Queue status 0, both headers 1, IRQ 2, MMU IRQ 0 | The submitted chain completed; output semantics are not implied. |
| Fragment fence 4 | Queue status 0, header 1, IRQ 1, MMU IRQ 0 | Fragment job completion, not a correct image. |
| Image oracle | **120/1,024** matches; **368** poison pixels remain | The translated DS4 image test failed. |
| Source and guards | 4,096/4,096 source words, 2,048/2,048 guard words intact | No change detected in these checked ranges. |
| Output histogram | 528 opaque black; 368 poison; 120 transparent black; 8 `0xa5a5a5a5` | No expected colored output; some marker-valued pixels require investigation. |
| Vertex outputs | Vertices 0/2 positions remain zero; vertices 1/3 have positions but UV words `0x7fec0000` (NaN) | Localizes an error before correct texture sampling; does not identify one unique cause. |

Touched masks are triangular in rows 0–15 and mostly `0xffff0000` in rows
16–29; this is not complete 32×32 coverage. The logged source taps and UBO
constants have the expected fixture values. Readback happened after completion
and cache invalidation, before the return to TWRP. Ending iOS boot early does
not explain these already measured pixel errors. The short recovered window
does not establish later iOS stability or absence of later backboardd crashes.

## iOS integration and presentation comparison

These differences remain even after correcting individual GPU packets.

### Device discovery is implemented; general rendering is not

`userland/a5mali-metal/StockMetalPlugin/A5MaliMetalDevice.m:67–90` validates
the accelerator service and opens the private GPU client. Lines 93–130
initialize restricted limits and feature queries. The previously recovered
stock-device acceptance and queue creation establish this discovery milestone.
They do not prove compositor pipeline coverage or pixel correctness.

`A5MaliMetalLibrary.m:119–159` exposes only `read_surf_vert` and
`read_surf_frag` from one authenticated library and rejects function
specialization. `A5MaliMetalAPI.m:13–44,157–182` accepts only the corresponding
single-color, no-blend/no-depth, single-sample pipeline. The actual DS4 shader
pair is still an isolated kernel self-test and is not vended to iOS.

This explains the **separate** backboardd missing-fragment-function failures:
correcting DS4 pixels alone will not make all QuartzCore shaders available.
The earlier warmup table review found 1,079 rows and 21 direct fast profiles;
runtime order was not proven. A general frontend must translate each required
function/specialization and its state, or explicitly decline it. Returning a
generic shader under another name would not implement the requested shader.

### Resource and draw coverage is deliberately narrow

`A5MaliMetalAPI.m:126–208` supports shared, single-level BGRA8 2D textures
and requires IOSurface row bytes to equal `width * 4`.
`A5MaliMetalAPI.m:575–591` further restricts its read-surface draw to
1080×1920 with 4320-byte rows. The phone's previously observed compositor
surface has **4352-byte rows**. The separate kernel presentation mapper handles
that exact 4352→4320 case, but that does not extend the provider's texture or
render-encoder acceptance. This is a confirmed coverage gap; the latest DS4
fixture does not test this iOS import path.

The render encoder accepts one triangle draw, one source texture, one exact
viewport and one target (`A5MaliMetalAPI.m:535–591`). It has no general vertex
buffer, index, UBO, sampler, blend, depth/stencil or multi-pass state emission.
By comparison, upstream `pan_jm.c:993–1025` emits vertex and tiler jobs using
the complete draw state; `pan_cmdstream.c` constructs resource and shader
descriptors from that state. Existing rejection paths are preferable to
claiming unsupported features, but still block normal compositor rendering.

### Completion and shared ownership need broader semantics

`A5MaliMetalAPI.m:434–476` submits the private command buffer synchronously
and reports scheduled/completed callbacks after `commitAndWait` returns.
`A5MaliCommandBuffer.m:310–375` serializes bounded operations and retains
their source/destination resources. This is a real bounded submission path,
but not the release stack's general dependency model.

Upstream Mesa `pan_job.c:244–280` tracks readers and writers and submits
conflicting batches. `pan_jm.c:115–156` supplies every referenced BO to the
kernel, and lines 185–229 protect tiler/fragment submissions sharing a heap.
Those Linux APIs are not required verbatim on XNU, but equivalent lifetime,
read/write dependency and completion guarantees are required. CPU cache
maintenance alone is not a producer-completion fence.

### Final transfer and panel scanout are separate from composition

`arm/SweetFramebuffer.cpp:503–558` attempts Mali presentation only for one
exact full-screen layer. Partial rectangles, multiple layers and unsupported
geometry use the CPU path. `arm/A5XELTEGPUFrameMap.cpp:94–106,121–169` pins
validated pages, handles the observed 4352-byte source stride and performs
cache maintenance; it does not import a producer-completion fence.

`arm/A5XELTEGPUFramePresent.cpp:168–173` increments `shown` after GPU job
completion. It does not read back the entire panel image or wait for a panel
page-flip event. DECON continues scanning the loader's live buffer; there is
no double-buffered page flip here. This is custom display integration, not a
Panfrost display driver. The upstream documentation also distinguishes Mali
rendering from the separate display controller.

**Evidence correction:** earlier 0146 notes titled “first full-panel Mali
presentation” prove completed jobs on full-size mapped resources and a
user-visible normal screen. The fragment tile-range omission found in this
audit means they do **not** establish that all 1080×1920 pixels were copied by
Mali. Retain the original observation as history, with this narrower conclusion.
Likewise, byte/frame counters derived from completion must not be treated as
measured full-image coverage. The 0133 user-visible green patch remains valid
evidence that GPU-written pixels reached the panel.

## Coverage and actionable findings

The comparison covers each layer already attempted, including the older
`read_surf`, typed AS1 operations and full-screen transfer paths. It is not
limited to the latest DS4 packet.

| Stage | Assessment against the release | Required work / evidence boundary |
| --- | --- | --- |
| Exynos power and clock setup | Board-specific sequence; L2→shader→tiler order matches | Preserve actual Exynos wiring; inherited domain state and no full resume lifecycle remain limitations. |
| T720 initialization and errata | **Missing release operations** | AS0/AS1 job config lacks `START_MMU` bit 10; shader configuration `0xf04` does not establish T720 bits 18/25 (`0x02040000`). Firmware may have left bits set, but no readback proves it. |
| MMU tables and live updates | Four-level Mali-LPAE, leaf `0x2c1`, MEMATTR `0x888d88`, TTBR flags and current DS4 lock/flush match | Keep the corrected DS4 publication sequence. AS1 disable/free lacks the release's `FLUSH_MEM` drain. |
| Cache and fault handling | CPU/GPU cache operations exist; ambiguity retains memory | AS1's interstage invalidation omits page-0 GPU-written varying ranges. Its masked/raw IRQ checks are inconsistent, partly mitigated by a separate FAULTSTATUS check. Actual corruption is unproven. |
| Scheduling and recovery | Bounded serialized polling queue | No equivalent of the release's IRQ scheduler, reset/recovery, cross-context resource dependencies or full PM lifecycle. This is a feature gap, not evidence that every bounded job fails. |
| Vertex dispatch | **Confirmed parameter omission** | Both translated builders omit `COMPUTE_JOB.PARAMETERS.job_task_split=5`. Current four-vertex invocation fields themselves match upstream. |
| Varyings | **Confirmed DS4 producer-format mismatch** | Compiled VS uses `ST_VARY.u32`; VS descriptor must be `RG32UI`, while smooth FS stays `RG32F`. Forcing NIR to float would contradict upstream's deliberate policy. |
| Tiler and scratch | DS4 now has a nonempty heap and current special-output layouts | Older `read_surf` still has wrong table spacing, special formats, missing VS FBD and misplaced vertex-ID indirection. Typed AS1 copy/read_surf use empty heaps with enabled tiling. |
| Fragment dispatch | **Confirmed shared extent errors** | Generic copy/clear and full-panel present retain zero tile maxima; old read_surf writes pixels into tile fields. DS4's max tile `(1,1)` is already corrected. |
| Texture, sampler and color | Fixed single-level profiles; byte-stride units match | Extra view swizzle and no-mip LOD differences need isolated tests. They are not proven causes of NaNs or missing geometry. General formats/mips/samples are absent. |
| Compiler pipeline | Release Midgard backend, custom frontend/lowering | Custom half-arithmetic lowering occurs after the release's postprocess boundary; SPIR-V validation is disabled. Both need correction/validation without relabeling them as a proven runtime cause. |
| Metal functions, resources and state | Discovery and bounded queue accepted | Only read_surf functions/pipeline are exposed. DS4, generic resource bindings and compositor state are incomplete; 4352-byte surface stride is rejected by the current provider path. |
| Panel presentation | GPU pixels reached panel in the green-patch test | Current completion counters do not verify full-panel coverage, producer completion or page flipping. CPU fallback remains active for other cases. |

### Implementation order

1. Establish the release's T720-specific shader configuration and `START_MMU`
   on both queues with model/config readback. Correct MMU drain and cache
   ownership before normal AS1 memory reuse. Preserve pinned resources on
   ambiguous failure.
2. Correct **all shared command producers**: tile-coordinate bounds,
   vertex PARAMETERS, per-stage varying types, read_surf tables/FBD/vertex-ID
   and nonempty geometry heaps. Use the generated release schema sizes in
   validators, including the full 320-byte framebuffer descriptor.
3. Place custom arithmetic at the supported compiler stage, validate SPIR-V
   and final NIR, and regenerate authenticated shader metadata and artifacts.
   Keep the intentional U32-producer/F32-consumer varying contract.
4. Establish finite complete vertex outputs and **1,024/1,024** DS4 oracle
   pixels with intact source/guards. Check asymmetric channel colors, rectangles
   crossing tile boundaries, off-origin regions and preserved outside pixels
   for copy/clear. Full-panel validation must include distant tiles/corners;
   another successful 16×16 sample cannot cover the dispatch omission.
5. Extend real Metal function/pipeline/resource factories to the required
   QuartzCore profiles and row strides, with actual bindings and dependency
   semantics. Device matching or a fabricated generic shader cannot replace
   these implementations. Bind interrupts, cancellation/reset and PM lifecycle
   before claiming a general scheduler.

Steps 1–3 contain source-proven corrections. Their implementation and device
effect are **pending**; this audit did not silently change or install them.
The swizzle, LOD and cache-corruption explanations remain hypotheses until
the corresponding controlled output checks.

## Detailed evidence

- [Kernel protocol, power, MMU, cache, queue and memory lifecycle](a5xelte-panfrost-kernel-audit.md)
- [All current command producers, vertex/tiler/fragment and display packets](a5xelte-panfrost-command-audit.md)
- [Compiler, AIR/SPIR-V translation, shaders, formats and resource coverage](a5xelte-panfrost-compiler-audit.md)
- [Pinned release source hashes and retrieval URLs](a5xelte-panfrost-source-manifest.json)

The source mismatches are actionable without assuming the development A5
Linux driver is correct. The current phone result remains failed DS4 pixels;
complete iOS rendering on Mali has not been demonstrated.


## Correction candidate 0170

The source-proven bounded-path corrections were implemented after this audit in
patches0166–0170, the tracked command builders/encoder and the compiler wrapper.
This includes T720 setup, MMU drain/cache handling, all current fragment bounds,
vertex dispatch/varying layout, nonempty heaps and padded read_surf row strides.
The original audit above records the pre-fix snapshot; do not reinterpret its
static findings as proof of the new candidate's phone result. See the latest
[A5 progress entry](../A5XELTE_PROGRESS.md) for build, installation and pixel evidence.
General Metal pipeline/resource coverage, asynchronous IRQ/reset/PM architecture
and the swizzle/LOD hypotheses are not claimed completed by these source fixes.
