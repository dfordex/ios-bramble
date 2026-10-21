# Official Panfrost comparison: compiler, shaders and resources

## Scope and baseline

Read-only review of the current A5 iOS GPU implementation. No source, build,
device, partition or Git changes were made for this audit. This file is the only
output. Snapshot: HEAD `81013a5`, with the shared working tree read on 2026-10-21.

Path prefixes used below:

- **Mesa**: `/private/tmp/a5xelte-mesa-full/mesa-26.2.4/`
- **Port**: `/Users/orhuntx/Documents/ChatGPT/sma510fpmos/experiments/ios-a5xelte/`

Mesa's VERSION is `26.2.4`. The cited compiler, varying, format, texture,
Gallium command-stream and PanVK shader files were compared byte for byte
against the cached release archive
`/private/tmp/a5xelte-mesa-26.2.4.tar.xz`; those files match. The comparison does
not use the Samsung Linux GPU tree. Parent separately verified the official
archive provenance and its broader source inventory. Gallium's v4 path is the
descriptor baseline; a PanVK lowering example does not establish full T720
Vulkan support.

## Conclusion

The port uses the release Midgard compiler backend, but it does not yet use a
general release Panfrost rendering driver. Its custom frontend, descriptor
lowering, resource bindings and hand-built job state implement a small set of
fixed profiles. The latest genuine downsample job completes without a reported
GPU fault, but its output fails the pixel oracle. Two concrete compiler/ABI
mismatches are present: the DS4 vertex varying producer format, and a custom ALU
lowering after Panfrost's postprocess boundary. Their exact contributions to
the observed pixels still require isolated device tests.

## Confirmed mismatches

### 1. DS4 varying producer descriptor does not match the compiled store type

**Current source:** Port
`userland/a5xelte-air-translation/build_downsample4_job.c:325` describes the VS
texture-coordinate output as `MALI_RG32F`; line 329 describes its FS input as
`MALI_RG32F` too.

**Actual compiler output:**
`/private/tmp/a5-downsample4-midgard-checked.log:489` has `store_output`
`src_type=uint32` for `VARYING_SLOT_VAR0`. The actual VS instruction at line 673
is `ST_VARY.u32 ... + 0x2`. This is not merely an inference from the source AIR.

**Release contract:**

- Mesa `src/panfrost/compiler/pan_nir_collect_varyings.c:123-130` records the
  output intrinsic source type; lines 156-173 deliberately choose unsigned
  32-bit stores for untrusted high precision vertex varyings.
- Mesa `src/panfrost/compiler/midgard/midgard_compile.c:1883-1896` selects the
  u32/i32/f32 store opcode from that source type.
- Mesa `src/gallium/drivers/panfrost/pan_cmdstream.c:2794-2807` chooses the FS
  format from the consumer type and producer precision. Lines 2810-2822 choose
  the VS format from the producer type. They need not be the same.
- Mesa `src/panfrost/compiler/pan_nir_collect_varyings.c:29-38` maps type to
  format; `src/panfrost/lib/pan_format.c:438,452` maps unsigned RG32 to
  `RG32UI`, and floating RG32 to `RG32F`.
- Mesa `docs/drivers/panfrost/varyings.rst:33-36,87-108` explains the relevant
  restriction: integer-to-integer and float-to-float conversions are supported;
  a high precision U32 vertex store may feed a floating point FS descriptor.
  The descriptor must match the instruction at each end.

For the current unchanged binary, the producer descriptor therefore needs
`RG32UI`, while the consumer remains `RG32F`. The mismatch is confirmed. Whether
it explains all of the 0169 NaNs or coverage failure is not yet established.

### 2. Custom arithmetic is inserted after the upstream compiler boundary

Mesa `src/panfrost/compiler/pan_compiler.h:63-73` specifies the sequence:
early driver lowering, preprocess, descriptor lowering, postprocess, sysval
inlining, compilation. It explicitly permits only sysval lowering between
postprocess and compilation.

Port `userland/a5xelte-air-translation/spirv_pair_midgard.c:321-345` calls
`pan_postprocess_nir`, then runs several passes, including
`lower_half_quantize` at lines 327-328. That pass, implemented at lines 199-208,
introduces f32-to-f16-to-f32 ALU. It is not sysval inlining. This violates the
release compiler's ordering contract. The code also runs DCE after that pass.

Move actual arithmetic/driver lowering before postprocess and validate the
result there. This finding is a structural correctness issue, not proof that
this one pass caused the current device image.

### 3. The older read_surf source builder retains special-varying ABI differences

Port `userland/a5xelte-air-translation/build_read_surf_job.c:222-242` describes
position as `RGBA32F`, point size as `R32F`, and places the second attribute
buffer at `+32`, with point-size stride 4. Release Mesa
`src/gallium/drivers/panfrost/pan_cmdstream.c:2655-2674` uses `SNAP_4` for the
position and `R16F` for point size with its appropriate swizzle. The DS4 builder
now uses those special formats and `pan_size(ATTRIBUTE_BUFFER)` at Port
`build_downsample4_job.c:319-330`; the older builder has not received the same
source treatment.

This is a source reproducibility and ABI divergence. It does not invalidate a
specific previously observed binary result without comparing that generated
binary to this source and its exact active shader outputs.

### 4. Validation is intentionally incomplete

Port `userland/a5xelte-air-translation/translate_stock_quartzcore.py:149-154`
passes `--no-spirv-val`. Its metadata checks at lines 76-134 and module-header
check at lines 164-166 constrain accepted ABI, but are not SPIR-V validation.
Port `spirv_pair_midgard.c:268` validates NIR immediately after conversion; no
explicit final validation is present after all custom lowerings. This is a
validation gap, not evidence that every current module is malformed.

## Stage-by-stage comparison

| Stage | Release Panfrost behavior | Current port behavior and limit |
| --- | --- | --- |
| Apple AIR frontend | Mesa is not an Apple AIR/Metal frontend. | A separate `metal2vulkan` tool converts extracted stock AIR. Port `translate_stock_quartzcore.py:31-73` has three explicit source profiles. |
| SPIR-V to Midgard | Driver-defined NIR lowering must follow `pan_compiler.h:63-73`. | Port `spirv_pair_midgard.c:221-231,365-374` accepts two exact hash-guarded SPIR-V pairs: read_surf and downsample_4. This guard is useful, but establishes no arbitrary shader support. |
| Texture/resource lowering | Runtime descriptors and shader metadata determine real resources. | Port `spirv_pair_midgard.c:74-105` collapses the one supported texture/sampler to slot 0 and loads dimensions/LOD data from UBO 0. Lines 112-142 map four fixed DS4 UBO bindings. Descriptor arrays, general SSBOs, argument buffers and arbitrary texture slots are absent. |
| Viewport and vertex base | Mesa `pan_cmdstream.c:1061-1081` uploads actual viewport scale/translation. | Port `spirv_pair_midgard.c:47-71,342-344` bakes a 1080x1920 viewport and base vertex 0. The 32x32 fixture compensates through its MVP; this is a bounded fixture, not per-draw state. |
| Texture and sampler sysvals | Mesa `pan_cmdstream.c:1085-1124,1204-1221` derives dimensions, view level, min/max LOD and bias from real bound views/samplers. | Port `spirv_pair_midgard.c:243-260` specializes normalized nearest sampling with fixed sysval ranges. Other states require different lowering and compilation keys. |
| UBO descriptors | Mesa `pan_cmdstream.c:1432-1457` encodes size in 16-byte entries, with a 4096-entry bound. | Port `build_downsample4_job.c:213-220` uses the same size unit. Current small fixture UBO lengths fit the bound. No error identified in this size unit. |
| Texture storage | Mesa `pan_texture.c:1272-1320` derives dimensions, format, layout, levels and swizzle from an image view. | Port `build_downsample4_job.c:245-263` directly emits one linear, single-level 64x64 BGRA source with row stride 256 and nearest normalized sampler. General tiling/modifier, mipchain, arrays, cube, depth and compressed formats are absent. |
| Compiled renderer metadata | Release descriptors are driven by compiler information and active render state. | Port `build_downsample4_job.c:171-205` uses fixed shader tags, resource/work-register counts and fixed render state. The exact shader-hash guards bound this today; the builder is not a generic pipeline compiler. |
| Userland functions and pipelines | Runtime selects and links actual shader functions and state. | Port `userland/a5mali-metal/A5MaliMetalLibrary.m:118-160` exposes only authenticated read_surf functions and rejects unsupported descriptors. `A5MaliMetalAPI.m:13-44,157-182` accepts one bounded BGRA pipeline with no blending/depth/stencil or active vertex layout. DS4 selftest binaries are not automatically stock DS4 userland pipelines. |
| Userland rendering commands | A general graphics driver binds arbitrary resources and draws stateful primitives. | Port `A5MaliMetalAPI.m:545-592` accepts texture index 0, a whole-target viewport, the exact three-vertex read_surf draw and equal 1080x1920 stride-4320 resources. It delegates a fixed private operation. This does not translate all iOS draw commands. |
| Buffer resources | General API buffers need compatible memory, binding and lifetime semantics. | Port `A5MaliMetalDeviceResources.m:76-95,110-210` implements bounded private allocations, validated handles and explicit 256-byte transfer operations; `contents` is NULL. Lines 249-261 reject bytes/no-copy construction. No shared CPU mapping or general shader-buffer binding is implemented. |
| Blit/mips/fences | Successful commands must perform their stated work and synchronize it. | Port `A5MaliMetalAPI.m:625-644` permits one-level mip generation as valid no-work only; nil or unsupported inputs fail. Lines 743-812 report explicit command errors for unsupported buffer copies/fill/sync/fences/counters. Selector coverage here means safe failure, not completed GPU features. |
| Native compiler SPI | Must use an actual compatible compiler/backend. | Port `A5MaliMetalUnsupportedSPI.m:29-113` deliberately rejects native pipeline libraries, source compilation and compute, forwarding only bounded render options. This avoids invalid native objects; it does not supply general compilation. |

## Candidates requiring an isolated test

These are not asserted causes of the current pixel failure.

### Texture view swizzle is noncanonical for an identity view

Port `build_downsample4_job.c:248,251` sets BGRA component order both inside the
format and in the separate texture swizzle. The older read_surf builder does
the same at lines 188,191.

Release Mesa `src/panfrost/lib/pan_format.c:501` maps
`B8G8R8A8_UNORM` to `RGBA8_UNORM` with BGRA format component order.
`src/panfrost/lib/pan_texture.c:1282,1301,1308` assigns the format table value
and the API image-view swizzle as separate values.
`src/gallium/drivers/panfrost/pan_cmdstream.c:1826-1838` supplies the API view's
r/g/b/a swizzles. The fields are separately defined in Mesa
`src/panfrost/genxml/v4.xml:602,607`.

The enum is explicit in Mesa `src/panfrost/genxml/common.xml:7-11`:
R=0, G=1, B=2, A=3. Thus the four 3-bit fields encode identity RGBA as `0x688`
and BGRA as `0x60a`. For an ordinary identity view of a BGRA image, the release
path has the BGRA format plus an RGBA view swizzle. The fixture's second BGRA
swizzle is therefore a candidate divergence. A red-only/blue-only pattern must
settle the complete format/view/render-target combination; this audit does not
claim the output is proven reversed, nor that swizzle causes NaN or missing
coverage.

### Single-level no-mip LOD encoding differs

Release Mesa `pan_cmdstream.c:252-255` sets no-mipmap maximum LOD to minimum
LOD plus 1/256 on v4; lines 1204-1221 use the matching sampler sysval state.
Port `build_downsample4_job.c:259-268` leaves the corresponding min/max/bias
values zero. For one level and explicit LOD 0 the difference may be benign, but
that has not been independently proved. Do not carry this assumption into
general mip support.

### Half arithmetic and attribute holes need broader coverage

Port `spirv_pair_midgard.c:199-208` substitutes f32-to-f16-to-f32 for
`fquantize2f16`. The fixture uses finite 0/1 input and dyadic weights whose half
results are covered by the CPU reference. Arbitrary NaN/subnormal semantics are
not established; the README itself records that limit at lines 53-56.

Port `spirv_pair_midgard.c:293-299` packs vertex driver locations. Release Mesa
`src/panfrost/vulkan/panvk_vX_shader.c:1427-1439` preserves attribute-number
holes explicitly. DS4's active input locations 0 and 1 have no hole, so this is
not a demonstrated current DS4 bug. A general shader with active attribute 3
and missing attribute 2 must receive a correct mapping.

## What 0169 actually proves

Evidence: `/private/tmp/a5xelte-0169-phone-log.txt`.

- Lines 94-96: the AS0 mapping/flush completed and the genuine pair's vertex
  fence completed.
- Lines 97-101: some expected vertex positions exist, but UV outputs include
  `0x7fec0000` NaNs; point-size output is also not a complete expected record.
- Lines 107-111: uploaded MVP and texture matrix values are finite and match
  the intended fixture. No uploaded-matrix NaN was identified.
- Lines 113-114: vertex/tiler and fragment job headers/fences report completion.
- Lines 169-175: the oracle reports only `120/1024` correct pixels,
  `368` untouched pixels, source `4096/4096`, guards `2048/2048`, `pass=0`.
  Nontrivial expected sample colors are wrong.

This establishes submission, execution/completion and bounded memory behavior
for that run. It does not establish correct interpolation, complete raster
coverage, correct sampling, correct color output, or iOS compositor rendering.
The independent command-stream audit also found a vertex-job parameter issue;
that finding should be combined with this report rather than attributed to
the compiler without evidence.

## Corrective order

1. Match the actual VS output instruction type with the producer varying
   descriptor, keeping the FS consumer type independently correct.
2. Resolve the independently audited vertex-job dispatch parameters and retain
   both header-status and complete pixel/coverage checks.
3. Put custom arithmetic before Panfrost postprocess, validate SPIR-V and the
   final custom NIR, regenerate and compare exact binaries.
4. Test isolated red/blue colors before deciding the extra swizzle's effect;
   make sampler descriptor and shader sysvals describe the same state.
5. Bring older read_surf source builders into the same verified release ABI,
   recording precisely which generated artifact each device proof used.
6. Only after the genuine pair passes its nonuniform oracle, extend real
   userland function/pipeline factories and resource binding. Generic vertex
   layouts, resource arrays, render state, mip support and arbitrary iOS shader
   translation remain separate implementation work.

No success claim should be based on fence completion alone. The current
correctness gate is the nonuniform pixel oracle, and it fails on 0169.
