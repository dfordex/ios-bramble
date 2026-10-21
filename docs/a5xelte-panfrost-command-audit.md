# Released Mesa 26.2.4 command-stream comparison (read-only)

## Scope and evidence boundary

Audit date: 2026-10-21. This fragment changes no code, builds no executable and submits no GPU job.

Path roots used below:

- **U** = `/private/tmp/a5xelte-mesa-full/mesa-26.2.4` (released upstream source supplied and provenance checked by the parent).
- **P** = `/private/tmp/a5xelte-mesa-full/buildtools/src/panfrost/genxml/v4_pack.h` (generated from that upstream v4 schema).
- **R** = `/Users/orhuntx/Documents/ChatGPT/sma510fpmos/experiments/ios-a5xelte`.
- **K** = `/private/tmp/a5xelte-0156/xnu/iokit/Kernel/arm` (actual current staged kernel, not obsolete a5xelte-dxb).

Inspected current command producers: `R/tools/a5xelte-gpu/gen-t720-texture-fixture.c`, both `R/userland/a5xelte-air-translation/build_*_job.c`, `R/userland/a5xelte-gpu-translation/midgard_encode.c`, and K's GPU.cpp / GPUAS1.cpp / GPUTransfer.cpp / GPUFramePresent.cpp / DownsampleSelftest.inc. MMU/scheduler implementation is another agent's audit; this report only notes command ownership and data dependencies that affect descriptor validity.

**Phone boundary:** `/private/tmp/a5xelte-0169-phone-log.txt:91-115` proves the original private texture path still matches 256/256, and the actual translated DS4 vertex/tiler and fragment chains reach terminal success with no MMU IRQ. DS4 produces only 120/1024 expected pixels, 368 untouched pixels, and invalid/incomplete position/UV outputs. This is NOT a working DS4 shader/pipeline proof, and successful job fences are NOT a full-frame copy or arbitrary Metal rendering proof. Current source may receive parent edits after this snapshot; findings below identify the inspected locations, not an assertion about an unbuilt future candidate.

## Confirmed mismatches to correct together

### C1 — Fragment dispatch bounds are tile indices; general copy/clear/present leave them zero

Upstream: `U/src/panfrost/lib/pan_desc.c:1682-1690` derives each fragment payload bound by shifting inclusive draw extent by `MALI_TILE_SHIFT` (4). `P:3823-3859` packs these as independent 12-bit tile fields. Framebuffer bounds are separately in PIXELS (`pan_desc.c:1552-1553`).

Current:

- `R/userland/a5xelte-gpu-translation/midgard_encode.c:112-117` writes only job header and FBD pointer. Both encoders first clear the descriptor BO (`:157`, `:202`). Therefore fragment min/max tile coordinates remain zero, dispatching tile (0,0) even when the accepted operation spans a larger rectangle. The framebuffer bounds at `:78-85` do not replace job dispatch bounds.
- `K/A5XELTEGPUFramePresent.cpp:53-83` changes full-panel texture, quad, viewport and FBD geometry, then clears only header status. It does not expand fragment payload bounds inherited from the 16x16 startup template. Full-panel fences cannot establish full-panel coverage. Correct full-panel maximum is `(1079>>4,1919>>4)=(67,119)`.
- `R/userland/a5xelte-air-translation/build_read_surf_job.c:319-323` writes width-1 / height-1 directly into tile fields (1079,1919), rather than (67,119).
- DS4 was corrected already in `build_downsample4_job.c:400-405`; 32x32 is max tile (1,1). Do not copy its older pixel-bound version back into shared helpers.

Required contract: encode explicit inclusive TILE min/max from the destination pixel rectangle for every fragment producer. Validate off-origin rectangles and dimensions crossing 16-pixel boundaries. This is a source-proven encoding error independent of DS4's remaining shader/geometry issue.

### C2 — Both translated vertex builders omit COMPUTE_JOB.parameters.job_task_split=5

Upstream: `U/src/gallium/drivers/panfrost/pan_jm.c:492-508` copies the invocation and packs `COMPUTE_JOB.PARAMETERS.job_task_split=5`. `P:4084-4105` places this field at bits 26..29 of the word at job+40; schema offsets at `P:4171-4175` confirm invocation+32, parameters+40, draw+64 and padding+184.

Current: `build_downsample4_job.c:336-357` and `build_read_surf_job.c:260-276` pack the header, invocation and draw but never PARAMETERS. Zero initialization leaves task split=0. The independent tiler primitive split=6 is correctly populated; it does not fill the vertex parameter field.

Minimal released-upstream correction: pack the vertex PARAMETERS section with split=5 and assert its decoded value. A timing-delay change has no source support here. Whether this accounts for the observed missing even vertices remains to be tested.

### C3 — DS4 UV producer descriptor must match its U32 store; consumer stays F32

Upstream: `U/docs/drivers/panfrost/varyings.rst:87-108` explicitly permits VS integer / FS float descriptors, requires descriptors to match their own instructions and states that highp VS varyings are written U32. `U/src/panfrost/compiler/pan_nir_collect_varyings.c:153-173` intentionally changes highp VS stores to uint32 when trust=false. `U/src/gallium/drivers/panfrost/pan_cmdstream.c:2780-2822` chooses FS base type + VS bit size for the consumer and VS slot type for the producer. `midgard_compile.c:1883-1897` selects ST_VARY opcode from store src_type.

Current: `R/userland/a5xelte-air-translation/spirv_pair_midgard.c:302-319` uses trust=false, matching `U/src/gallium/drivers/panfrost/pan_shader.c:134-137`. Actual staged final NIR and disassembly in `/private/tmp/a5-downsample4-midgard-checked.log:489,673` are uint32 / `ST_VARY.u32` for UV slot2. Yet `build_downsample4_job.c:325` uses RG32F for the VS descriptor. The FS descriptor at :329 is RG32F and actual shader uses LD_VARY.f32, which is correct for the consumer.

Released-upstream contract: VS slot2 **MALI_RG32UI** (schema enum141), FS slot0 **MALI_RG32F**. Preserve the shader bit pattern; do not force NIR back to float or change the consumer to integer. The current int-register / float-memory mismatch invokes a conversion outside the documented int-int / float-float contract (`varyings.rst:24-32`). It is a concrete defect, but the precise resulting NaN bit pattern is still a phone observation rather than a simulated ISA proof.

### C4 — read_surf still carries several descriptor mistakes already fixed in DS4

Current `R/userland/a5xelte-air-translation/build_read_surf_job.c`:

- :238 writes buffer1 at VS_VARY_BUFS+32 while the corresponding ATTRIBUTE index is1 (:228). Schema `P:1079` says buffer entries are16 bytes; upstream allocates/indexes a packed array (`pan_cmdstream.c:2881-2933`). Hardware entry1 therefore remains zero. Pack contiguous 16-byte entries.
- POSITION descriptor :225 uses RGBA32F, PSIZ :230 uses R32F / stride4,size16 (:241-242). Released upstream special formats are SNAP_4 and R16F (`pan_cmdstream.c:2651-2659`); position buffer stride16 and point-size stride2 (`:2909-2917`). DS4 now follows these at :319-328.
- VS draw :271-276 leaves thread_storage zero. Midgard embeds local storage in the FBD (`pan_jm.c:25-47`) and always supplies that FBD pointer to the vertex draw (:480-486). Schema DRAW.thread_storage and DRAW.fbd alias the SAME qword (`P:1660-1663`); no separate TLS descriptor or fake scratch allocation is required for a zero-TLS shader. DS4 now supplies it at :354-356.
- :217 writes a 16-byte ATTRIBUTE_VERTEX_ID special directly into the 8-byte ATTRIBUTE table at index16, and the VS draw does not set attribute_buffers. Released upstream builds the special in the BUFFER table, then emits ordinary ATTRIBUTE[index16] referring to its buffer_index (`pan_cmdstream.c:2460-2469`; special divisor values in `U/src/panfrost/lib/pan_encoder.h:121-133`). The chosen divisor values themselves match non-instanced upstream; the table placement/indirection does not.
- :134-135 leaves geometry's heap start==end; see C5.
- Vertex split and fragment tile bounds are C2/C1.

These are present even though read_surf's bounded factory may currently reject use or the compiled private include may be absent. Fix the whole path before advertising it as a valid native translated render implementation. Do not infer corrected read_surf from a DS4-only fix.

### C5 — Typed AS1 copy and read_surf supply an empty heap for enabled tiling

Upstream: `U/src/panfrost/lib/pan_desc.c:953-968` sets an empty heap only for disabled tiling. Enabled tiling uses a separate heap start plus heap size. `pan_jm.c:140-146` explicitly retains the tiler heap BO when a tiler job exists. `U/src/panfrost/lib/pan_tiler.c:57-69` describes the growable allocation used by Linux.

Current: `midgard_encode.c:96-104` uses enabled flat tiling (mask0x1c7) for copy but sets heap start==end==polygon list. `build_read_surf_job.c:132-138` does the same. There is no independent heap allocation in its 8KiB descriptor layout. This is an upstream command contract mismatch even if a tiny quad happens to fit other storage on one tested run.

DS4's separate mapped heap+0x9000..+0xa000 at `build_downsample4_job.c:163-164` matches the nonempty-heap requirement. Existing AS0 texture startup/reset and full-frame-present paths likewise have real private heap+0x3000..+0x4000 (`K/A5XELTEGPU.cpp:533-534`; GPUFramePresent.cpp:76-77). Clear-only tiling is disabled and its empty heap is intentional, not C5.

## Stage-by-stage matches and bounded differences

| Stage / field | Upstream reference | Current assessment |
|---|---|---|
| WRITE_VALUE header / payload | P WRITE_VALUE_JOB header+32 and payload address+0,type+8; enum ZERO=3 at :3905-3907 | `K/A5XELTEGPU.cpp:99-112,681-686` is a packed 48-byte host struct containing the 44-byte required command plus harmless zero padding; type/64-bit flag, destination and ZERO3 match. This is not an arbitrary compute shader implementation. |
| Job descriptor stage offsets | P COMPUTE_JOB :4171-4175 and TILER_JOB section offsets; pan_jm.c:852-870 | Both translated builders use +32 invocation, +40 primitive/parameters, +64 DRAW and +184 primitive-size/padding. They reserve192 bytes; zero padding matches. Missing vertex params is C2. |
| Vertex / tiler invocation | pan_jm.c:964-978 | Current invocations3, Y/Z-size shifts0, workgroup X/Y shifts0, Z shift32, group split2 exactly match upstream single-instance4-vertex draw. No evidence supports changing invocation count/delays. |
| Topology | pan_jm.c:701-704,723,737-758 | Triangle strip,4 indices, primitive split6, nonindexed type0 and no restart fit the fixed quad. Fixed primitive size1 is appropriate for a non-point primitive. Arbitrary indexed topology, instancing, point-size arrays and restart are not implemented. |
| Chain / dependency | Upstream job-chain descriptors and pan_jm.c stage construction | Translated builders chain VS->tiler and make tiler depend on index1; fragment is a later separate JS0 submission after verified completion. Fixed runtime copy bypasses VS using CPU-prepared position/UV arrays; therefore it is not proof that a Metal VS executed. |
| DRAW local storage | pan_jm.c:25-47,480-486,664-673; P:1660-1663 | Tiler fbd is the same address field as thread_storage. DS4 now has both stage pointers. read_surf vertex remains zero (C4). No separate stack needed for compiler-reported TLS/WLS0. |
| Position / PSIZ formats | pan_cmdstream.c:2651-2659,2909-2917 | DS4 uses SNAP_4/R16F and contiguous buffers as of0169; read_surf does not (C4). Original runtime copy positions are CPU-filled float4 directly for tiler use, so it has no VS producer descriptor to change to SNAP_4. |
| Generic varying format | varyings.rst:97-108; pan_cmdstream.c:2780-2822 | DS4 producer RG32F is wrong for its U32 store (C3); FS float descriptor is correct. Original copy shader is a float FS-only varying, backed by CPU float coords; it is a different contract. |
| Vertex input alignment / stride | P ATTRIBUTE_BUFFER pointer is64B aligned, length16; pan_cmdstream.c:2387-2409 | DS4 VERTEX_DATA+0xc00 is64B aligned, stride48,size192; Float4@0 and Float2@16 match the shader's two actual LD_ATTRs. Four descriptors also include unused Float2@24,Half4@32; these extras do not by themselves establish a defect. read_surf raw ID indirection is C4. |
| SFBD pixel dimensions / RT stride | pan_desc.c:1552-1553,1601-1614; P PARAMETERS begins+32 | width-1,height-1 pixel bounds are right in FBD, unlike fragment tile payload. FBD word22 row_stride is a raw BYTE stride;128 for DS4,4320/4352 in the appropriately checked runtime image paths are not missing divide-by16. |
| Texture byte stride | pan_texture.c:892-903; P SURFACE_WITH_STRIDE | Source texture row_stride256 and surface_stride16384 for DS4 are byte units and valid. Runtime16x16 uses64/1024; full-frame-map explicitly requires4352-row source while AS1 read_surf checks4320. They are distinct paths, not interchangeable buffer geometries. |
| Texture format / swizzle | P TEXTURE format/swizzle fields; pan_desc.c:1590-1593 inverts rendering swizzle | BGRA source format low swizzle0x60a and BGRA FBD writeback are deliberate; original private RGBA test uses0x688. No source-proven BGRA/RGBA reversal was found for DS4. Need asymmetric colored-pattern proof, not constant red/black proof. |
| Sampler | P:1921-1933 | Nearest,min/maxLOD0,clamp-to-edge,noncube are defined. DS4 normalized=true matches its normalized UVs/taps. Runtime copy and read_surf use nonnormalized pixel coordinates. Changing all paths to one normalization mode would violate their shader contracts. General filtering/mips/aniso/comparison are not implemented. |
| Viewport scissor / depth | pan_cmdstream.c:815-841; P VIEWPORT defaults minz0,maxz1 | Current scissor maxwidth-1/maxheight-1 is correct inclusive packing. Fixed shader viewport1080x1920 plus MVP maps DS4 to32x32; not a general dynamic viewport API. Geometry readback is still wrong, but changing scissor coordinate units is unsupported. |
| Replace blend / mask | pan_cmdstream.c:520-529,542-567 | A=SRC,B=SRC,C=ZERO with fullcolor mask is the same fixed-function replace form used upstream. FS work register counts match the checked compile outputs. This does not implement arbitrary CoreAnimation alpha/blend/coverage state. |
| RSD shader counts / scratch | pan_jm.c uses compiler metadata; pan_desc.c:903-936 | Descriptor counts are hardcoded for authenticated fixture shaders, not generic programs. DS4 TLS/WLS0,VSregs8,FSregs7 were verified from the actual compiler earlier. Uniform tables include all explicit rebound UBO1/2 and3/4 plus metadata UBO0. RSD uniform-count0/NULLpush pointer is intentional because local compiler lowers pushes to UBO0. Do not assign scratch sizes from a different shader. |
| Framebuffer length / padding | P FRAMEBUFFER length320 at :3667; weights+256,padding+288 | Both build_* validators currently label framebuffer only0x100 bytes, while the actual descriptor is0x140 bytes. Current next regionVS_RSD+0x500 leaves enough physical zeroed room (FB+0x300..+0x440), so no present overlap is proven. Validator must nevertheless reserve/check pan_size(FRAMEBUFFER), not a shorter manual region. |
| Tiler polygon layout | pan_tiler.c:231-256,265-296; pan_desc.c:961-972 | Current fixedmask0x1c7 is a fixed1024x1024-bin policy and the corresponding polygon header/full-size formula is explicitly computed. Upstream chooses dimensions dynamically from width/height. This policy is a bounded divergence, not proof of general tiler sizing. Fixed4KiB/8KiB command storage cannot be assumed sufficient after adopting arbitrary upstream bins or geometry. |
| Clear-only SFBD | pan_desc.c:953-959,1556-1562 | Empty polygon list marker0xa0000000 and no-geometry disabled/user mode permit shaderlessclear. Smallprivateclear succeeds onphone; genericcopy/clear dispatch bounds still must be corrected (C1). Partialrects/preload semantics need preserved-outside-rect pixel verification. |
| Preload / preservation | pan_jm.c:240-250 invokes pan_preload_fb; P exposes color_preload fields | Current shared encoder directly sets SFBD color-preload bits/addresses instead of constructing upstream preloadjobs. This is an implementation divergence; no standalone source proof here that every partialrect preserves otherpixels. Keep as unverified semantic coverage, not a guaranteed bug or complete upstream equivalence. |
| Live present | GPUFramePresent.cpp:88-189, GPUFrameMap.cpp:94-106 | Requires exact BGRA1080x1920 source geometry, serializes tiler+fragment, retains mapping and treats uncertain panelDMA specially. It copies a previously CPU-rendered IOSurface; it does not execute all iOS graphics onGPU. Its missing fragment bounds are C1. |

## Readback priorities / acceptance gates

1. Correct C1-C5 across shared producers before interpreting faster fences as correct rendering. Preserve stable varying U32/F32 policy rather than changing shaders to fit a mistaken descriptor.
2. DS4: retain raw4positions,4UVs,PSIZ halfwords and row touched/matched masks. Verify all expected vertices/UVs finite and present, then all1024 output pixels against the nonconstant CPU oracle; terminal header1 alone is insufficient.
3. TypedAS1 copy/clear: verify full rectangles crossing tile0, off-origin rectangles, guardpixels outside partialdestination, and distinct perchannel/asymmetric input. A16x16 sample does not cover C1 or fullframe.
4. Fullpanelpresent: inspect changed pixels in each of the68x120 raster tiles / corners, not just frame fence or user-visible fallback. The current live256sample precondition validates a fixed texture path, not entire panelcoverage.
5. Read_surf: validate specialvertexID ATTRIBUTE+BUFFER indirection, actual newheaprange and relocation offsets together with its translatedshader outputs. Do not advertisefunctionality merely because privatefixtureincludeexists.
6. Generalunsupported state remains explicit: genericcompute, arbitraryvertex/index/instance layouts, resourceformats, multiplemips/samples, depth/stencil, destination-readblend and shaderTLS require corresponding upstreammetadata/descriptors and outputtests. This audit is of currently constructedcommands, not evidence that thosefeatures alreadyexist.

## Corrections to earlier hypotheses

- The U32 VS store is released Mesa's intentional highp varying policy, NOT itself a compiler bug. The VS descriptor was wrong. Do not force float NIR.
- READ fault VA0 in0166 did not establish shaderISA failure. The known missing VS FBD pointer was a descriptor mismatch; after relatedfixes jobs reachterminal in0168/0169.
- Currentstride fields are byteunits. No support was found for dividingRT/source strides by16.
- No extraGPUstackallocation is justified for compiledTLS/WLS0; the FBD/local-storage pointer still must be supplied.
