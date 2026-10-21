# Native texture resource operations — 0180

## Verdict: CONCERNS — integrated, hardware verification pending

The0179 log exposed resource creation failures before a captured stock command
commit. These are resource/encoder contracts, not missing shader source that
can simply be sent to the existing on-phone compiler. This change implements
real backing and native GPU operations for the observed resource families.
General iOS compositor rendering is not established by the local tests below.

## Implemented boundaries

| Component | Implementation and evidence |
| --- | --- |
|Logical textures|`A5MaliMetalTexture.m` owns real packed backing, with bounded offset, row and dimensions for every mip. Public1D max4096,2D max2048; physical backing may have height4096.|
|Formats|Distinct R8/RG8/BGRA8/RGBA16Float/R32Float plus captured R16Uint,R16Float,BGR5A1Unorm,RG32Float. FourCC and bytes-per-element are checked exactly.|
|CPU transfer|Shared replace/get copies actual bytes under IOSurfaceLock/Unlock. Private and Memoryless CPU access is rejected. Internally created Shared textures do not expose a misleading physical-atlas IOSurface as their logical texture.|
|Memoryless|The logical object owns no persistent backing. Renderpass Clear/DontCare and StoreDontCare use a fresh pass lease; Load/Store, CPU transfer, sampling and blit escape are rejected. The command buffer invalidates leases before publishing completion.|
|Native mip/copy|`runtime_resource_ops.c` emits real VS/TILER/FRAGMENT jobs. Same-format copies preserve bits for nine formats, including typed1D. Partial copies use an actual destination-preload job. BGRA8 mip generation runs a genuine shader.|
|Queue|Each operation maps retained whole backing, validates the logical level against that span and adds its offset once. Same-allocation mip levels use one physical mapping with disjoint byte windows and ordinary terminal fences.|
|Kernel|0181 admits only the four new exact format/BPE pairs and bounded4096/32768 physical geometry;32MiB windows remain. Legacy typed BGRA helpers remain restricted.0182 adds only native profiles500/501; chain, epoch, permissions and fence checks remain.|

The ten new resource shader programs are our source-generated NIR compiled by
released Mesa26.2.4. They do not require Apple shader extraction. Generated
program bytes remain private; the signed provider records their verified include
digest. Existing authenticated QuartzCore profiles and seven passing0179 GPU
oracles remain unchanged.

## Meaningful verification

- Real Mac IOSurface RAM tests cover all nine formats,1D3072/4096 raw data,
 776x24 ten-level backing, padding/gap canaries,1x1 and32MiB bounds, and memoryless
 lifetime/CPU denial. Kernel transport is injected, not phone hardware.
- Linked public Metal API transport tests cover actual compiled profile
 bindings, large uploads, clear/path and diagnostics. A new test exercises
 partial copy, nine same-allocation mip jobs, physical-atlas/logical-level clear,
 mapping epochs and returned terminal fences. Wrong backing, short spans,
 arithmetic overflow and bad fences are rejected.
- Nine-format clear words match unmodified released Mesa `pan_pack_color` for27
 constants. Eighteen resource descriptor/negative contracts and Cortex-A53
 iOS16 `-Werror` compilation pass.
- Actual Apple M4 Metal `generateMipmapsForTexture` supplied an independent
 reference for six shapes and29 reductions. Fixed2x2 averaging is wrong for odd
 sizes, including97x3->48x1 inside the776x24 chain. Center-scaled bilinear
 filtering matches every measured component within1; the native Mali shader and
 strong independent oracle use that algorithm. This is a semantic reference,
 not proof of Mali execution.

## Device test and limits

0180 embeds the existing seven GPU tests plus14 new resource cases: nine exact
copies, including captured1D widths, and five mip reductions including odd and
single-axis shapes. Source, expected and mask hashes are pinned. Tolerant tests
may mask row padding only by full-element/zero masks; partial-bit masks with
tolerance are rejected. The kernel comparator's semantics are unchanged.

The device must establish correct new pixels, terminal fences and actual stock
commit/submission records. Mip generation is BGRA8-only; other mip formats are
explicitly rejected. Ordered original-path multi-attachment rendering, general
indexed/instanced geometry, arbitrary Metal shaders and complete compositor
coverage remain outside the current implementation. These limits must not be
hidden by successful allocation or fabricated completion.
