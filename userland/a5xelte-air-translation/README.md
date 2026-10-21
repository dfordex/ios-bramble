# QuartzCore graphics to Mali T720: local shader proofs

This directory compiles **two actual stock iOS 16.7.16 QuartzCore graphics
pairs** to Mali T720 Midgard machine code on a Mac. It is a host experiment,
not an iOS Metal device or a hardware run. No Apple metallib, extracted
bitcode, generated SPIR-V, or firmware image is kept here.

## Proven input and path

The source is the staged
`System/Library/Frameworks/QuartzCore.framework/default.metallib`.
Upstream [metal2vulkan](https://github.com/steelbrain/metal2vulkan) translated
the actual `read_surf_vert` and `read_surf_frag` AIR functions into Vulkan
graphics SPIR-V stages using its `vk12-floor` profile and BGRA8Unorm color
attachment. Unlike a generic LLVM `llc -march=spirv64` conversion, these
modules have graphics entry points and stage interfaces. The local translator
outputs are 712 bytes (vertex) and 4352 bytes (fragment); their exact
contents remain outside Git.

`spirv_pair_midgard.c` reads those two SPIR-V modules, calls Mesa 26.2.4
`spirv_to_nir`, applies the narrowly required Panfrost lowering, and calls
`pan_shader_compile` for GPU ID `0x07201000`. It rejects every other SPIR-V
module by its fixture fingerprint because some lowering depends on this
specific function pair. The FNV fingerprint is a scope guard, not a security
hash or a general compiler cache key.

Local result on the translated stock modules:

| Stage | Midgard bytes | Relevant disassembly |
| --- | ---: | --- |
| Vertex | 208 | position varying store |
| Fragment | 1232 | `TEX_FETCH ... texture0`, UBO loads including `+0x40`, color output |

## Resource and lowering contract

The original fragment reflection reports `Texture(0)` with **read** access,
not sampled filtering. `read_surf_frag` uses integer texel fetch and texture
dimension/level queries. T720 Midgard's current Mesa backend handles the
fetch but has no `query_levels` or `txs` shader opcode, so the experiment
rewrites those queries to UBO slot 0:

| UBO 0 offset | 32-bit value | Provenance |
| ---: | --- | --- |
| 0 | texture level count | equivalent to `query_levels` |
| 4 | base level width | equivalent to `txs` x at LOD 0 |
| 8 | base level height | equivalent to `txs` y at LOD 0 |
| 64 | `ColorWriteRule` | original SPIR-V push constant byte 64 |

The host must populate those values for the **same texture0** it binds; the
fixture asks only about LOD 0. The fragment-position input is lowered to the
Midgard position varying. The vertex proof assumes `baseVertex=0` and a
1080×1920 viewport; a runtime must supply these dynamically. The
`fquantize2f16` NIR operation is lowered to f32→f16→f32 because Midgard lacks
the direct opcode. This preserves normal finite half-rounding but has not been
shown to match all source NaN/denormal cases; the upstream translation also
reports half-precision notes. These constraints must be honored or tested
before rendering is claimed correct.

The compiler prints `textures=0` in its shader-info summary despite emitting
`TEX_FETCH ... texture0` in the Midgard disassembly. The descriptor fixture
therefore explicitly binds texture and sampler slot 0; this is a compiler
metadata gap, not evidence that the shader needs no texture.

## Bounded T720 render descriptor fixture

`build_read_surf_job.c` uses Mesa's generated v4 pack/unpack definitions to
create and check one **host-only** 12 KiB GPU descriptor allocation for the two exact
Midgard shader fingerprints above. It accepts only 1080×1920 BGRA8 input and
output, a single texture at LOD 0, four vertex IDs drawn as a triangle strip,
and distinct non-overlapping mapped 40-bit GPU addresses. This draw topology
is a fixture choice; stock QuartzCore call-site draw state is not proven.

| Offset | Resource |
| ---: | --- |
| `0x000`, `0x100`, `0x200` | Vertex, tiler, and separate fragment jobs |
| `0x300` | Framebuffer with BGRA8 target and preload pointers |
| `0x500`, `0x540` | Vertex and fragment renderer states |
| `0x600`, `0x620`, `0x660`, `0x680` | Texture0, linear surface, texture pointer table, sampler0 |
| `0x6c0`, `0x880` | UBO0 descriptor and 80-byte data |
| `0x700`–`0x860` | Special vertex ID, varying attributes/buffers, viewport |
| `0x900`, `0xe00` | Exact fragment (1232 B) and vertex (208 B) code |
| `0xf00`, `0xf40` | GPU-written position and point-size outputs |
| `0x1000`–`0x1a00` | Polygon header and body, allocated as one 0xa00-byte span |
| `0x2000`–`0x3000` | Separate, mapped 4 KiB geometry heap |

The polygon body pointer is `0x1200`, **inside** that span. The full 0xa00-byte
span comes from the 1080×1920 fixture's four 1024×1024 bins and is checked
against every descriptor region. The source image pointer is at `0x620`; the
destination image appears at `0x350` and `0x380`. All other addresses refer to
the descriptor page or its internal varying outputs. UBO0 contains levels=1,
width=1080, height=1920, and `ColorWriteRule=0x2222` at offset 64. That rule
is the translated pipeline's BGRA8Unorm rule, confirmed by upstream
metal2vulkan metadata and its graphics binder test. Zero would select the
wrong fragment behavior.

The builder checks exact shader fingerprints, address bounds and overlap,
descriptor range overlap, and packed readback of the key job links, resource
pointers, counts, polygon extent, and color rule. It does **not** prove that
the T720 accepts or completes these jobs, that polygon heap capacity is
sufficient under all geometry, or that iOS calls this pipeline. No device
submission, Metal device, iOS ownership, shader cache, or synchronization is
provided here.

## Reproduction with locally staged inputs

`translate_stock_quartzcore.py` is a source-only offline front end for two
named stock QuartzCore pairs. Besides `read_surf`, it translates the actual
`buffer_image_blit_vert_lpf` and `buffer_image_blit_frag_lpf` functions to
graphics SPIR-V and rejects a change in their reflected resource ABI. The
second pair uses read-only vertex Buffer1 (storage, whole) and Buffer2
(64-byte uniform), and read-only fragment Buffer1 (16-byte uniform) and
Buffer9 (storage, whole). Its push ranges are vertex bytes 0–7 for two
buffer bind offsets and fragment bytes 64–75 for two bind offsets plus
`ColorWriteRule=0x2222`; it writes one BGRA8Unorm color attachment. This
second pair is **AIR→SPIR-V only**: its Vulkan buffer descriptors still need
lowering to NIR/Midgard. A direct backend attempt stopped at unsupported
`vulkan_resource_index`. No Mali binary, T720 draw descriptor, or phone test
exists for this pair.

These pairs can be translated without adding the proprietary metallib or
generated shader bytes to Git:

```sh
python3 translate_stock_quartzcore.py buffer_image_blit \
  /private/tmp/a5xelte-root-view/System/Library/Frameworks/QuartzCore.framework/default.metallib \
  /private/tmp/a5-blit-pair \
  --translator /private/tmp/a5-metal2vulkan/target/release/metal2vulkan \
  --profile /private/tmp/a5-metal2vulkan/crates/metal2vulkan-validation/profiles/vk12-floor.json
```

On the staged input this produced 7052-byte vertex and 7836-byte fragment
SPIR-V modules. The tool checks resource read access, buffer windows,
push ranges, BGRA8 output, and both SPIR-V magic words. It accepts the same
arguments with `read_surf` as the pair name. Other functions are outside
these checked profiles.

The tested host has Mesa source at
`/private/tmp/a5xelte-mesa-full/mesa-26.2.4` and its Meson build at
`/private/tmp/a5xelte-mesa-full/buildtools`. Given the translated files in
`/private/tmp/a5-read-surf.vert.spv` and `.frag.spv`:

```sh
python3 build_local.py /private/tmp/a5xelte-mesa-full/buildtools /private/tmp/a5-spirv-pair
/private/tmp/a5-spirv-pair \
  /private/tmp/a5-read-surf.vert.spv \
  /private/tmp/a5-read-surf.frag.spv \
  /private/tmp/a5-read-surf.vert.midgard \
  /private/tmp/a5-read-surf.frag.midgard
```

`build_local.py` reuses the exact compiler and linker flags of the local
Mesa `a5_t720_copy_shader` target and builds Mesa's `libvtn.a`. Outputs stay
under `/private/tmp`. This experiment uses the **real translated shader
modules**, with no hand-written replacement shader.

To build and validate the descriptor for a fixed private descriptor VA:

```sh
python3 build_job_local.py /private/tmp/a5xelte-mesa-full/buildtools /private/tmp/a5-read-surf-job
/private/tmp/a5-read-surf-job \
  /private/tmp/a5-read-surf.vert.midgard \
  /private/tmp/a5-read-surf.frag.midgard \
  /private/tmp/a5-read-surf-job-kernel.bin \
  1080 1920 0x10000000 0x10800000 0x12000f00 0x12000f40 0x12000000
```

The source and destination addresses in this command are fixture addresses,
not device allocation evidence. For this exact invocation the private output
was 8192 bytes, SHA-256
`26885bced5b3d15fa00e38b8c41e8a0eb458d42852021873f7d420af48dd8e9a`.
No generated binary is tracked in Git.

## First statically predicted QuartzCore warmup pair

The `downsample_4` profile translates `downsample_blur_vert_lph` and
`downsample_4_frag_lph`, the first fast pipeline predicted from the inspected
QuartzCore warmup table and conservative device profile, row
`PBGRABsovXm_Tds4A2Xhf_Isrc`. The phone crash does not log its dynamic function
name; the table audit is separate static evidence. These entries
declare no Metal function constants. The row's shader layout 4 is separate
from vertex packing: the selected packing is table index 0. The inspected
QuartzCore descriptor uses buffer 1, stride 48, per-vertex stepping, and
attributes Float4 at byte 0, Float2 at 16, Float2 at 24, and Half4 at 32.
The wrapper supplies that complete descriptor, including unused attributes,
rather than deriving a layout from AIR argument types.

```sh
python3 translate_stock_quartzcore.py downsample_4 \
  /private/tmp/a5xelte-root-view/System/Library/Frameworks/QuartzCore.framework/default.metallib \
  /private/tmp/a5-downsample4-checked \
  --translator /private/tmp/a5-metal2vulkan/target/release/metal2vulkan \
  --profile /private/tmp/a5-metal2vulkan/crates/metal2vulkan-validation/profiles/vk12-floor.json
```

The local translation produced 4752-byte vertex and 13332-byte fragment
SPIR-V modules. The bounded profile checks these actual resource interfaces:

| Stage | Metal binding | Reflected use |
| --- | --- | --- |
| Vertex | Buffer 2 | Read-only uniform words, 64 bytes |
| Vertex | Buffer 3 | Read-only uniform words, 16 bytes |
| Fragment | Buffer 1 | Read-only uniform words, 72 bytes |
| Fragment | Buffer 6 | Read-only uniform words, 2 bytes |
| Fragment | Texture 3 | Sampled float 2D texture |
| Fragment | Sampler 0 | Non-comparison, coordinate-sensitive sampler |

Vertex push bytes 0–7 contain buffer bind offsets. Fragment bytes 64–75
contain two buffer offsets and the BGRA color write rule at byte 72.
The wrapper also checks the translator's **bind-time SPIR-V specialization**:
vertex IDs 1 and 2 describe Buffer 2/3 ranges, fragment IDs 3 and 4 describe
Buffer 1/6 ranges, and fragment ID 0 describes Sampler 0 state. These are not
Metal function constants. Their encoded defaults are zero; a renderer must
supply the actual bound ranges and sampler state instead of executing those
defaults as if they described the requested resources.

### Bounded Midgard compilation

The stage compiler accepts this exact module pair only with the explicit
`downsample_4` argument. It specializes buffer-range IDs to 64, 16, 72 and
2 bytes, and sampler state ID 0 to normalized nearest sampling. These values
define a local compile profile; they are not a measurement of the phone's
actual resource ranges or sampler state. Other states need another checked
profile or dynamic specialization.

```sh
python3 build_local.py /private/tmp/a5xelte-mesa-full/buildtools /private/tmp/a5-spirv-downsample-pair
/private/tmp/a5-spirv-downsample-pair \
  /private/tmp/a5-downsample4-checked.vert.spv \
  /private/tmp/a5-downsample4-checked.frag.spv \
  /private/tmp/a5-downsample4-checked.vert.midgard \
  /private/tmp/a5-downsample4-checked.frag.midgard downsample_4
```

Both stages compiled locally: vertex 2048 bytes, fragment 3472 bytes. The
fragment disassembly contains four texture-sampling instructions and UBO
loads. The shader-info texture count remains zero despite those instructions;
the future binder must explicitly bind texture/sampler slot 0.

The lowering replaces Vulkan UBO descriptor indices with this binding contract:

| Stage | Original Metal slot | Midgard binding |
| --- | --- | --- |
| Vertex | Buffer 2 / Buffer 3 | UBO 1 / UBO 2 |
| Fragment | Buffer 1 / Buffer 6 | UBO 3 / UBO 4 |
| Fragment | Texture 3 / Sampler 0 | Texture 0 / Sampler 0 |

UBO 0 is a separate metadata/push block: texture level count at byte 0,
width/height at 4/8, actual sampler min/max LOD and bias at 16/20/24, vertex
bind offsets at 0/4 in the vertex-stage block, and fragment push data at
64–75 (BGRA write rule at 72). Vertex and fragment UBO 0 are distinct stage
bindings. Buffers need physically padded, aligned backing for the generated
uniform loads even where the logical range is only 2 bytes. The local vertex
proof still uses baseVertex 0 and a fixed 1080×1920 viewport.

Mesa NIR validation and compilation passed. Modified modules and use of one
pair under the other profile are rejected before emitting outputs. Rebuilding
the existing `read_surf` pair produces byte-identical 208/1232-byte binaries.
The initial experiment lacked external `spirv-val` and explicitly disabled it.
The corrected wrapper now **requires** a real validator and enables the
translator's profile-specific validation before any shader output is written.
Supply `--spirv-val /path/to/spirv-val`, set `METAL2VULKAN_SPIRV_VAL`, or put
SPIRV-Tools on PATH. Missing validation fails the translation. For this Vulkan
1.2 profile the validator enables `--uniform-buffer-standard-layout`, matching
the profile's actual `uniformBufferStandardLayout` feature; without that
feature a tightly packed `uint[]` uniform block correctly fails validation.

The real AIR stages now have a host Midgard compilation path. This supplies
no draw descriptors, vertex/UBO/sampler binding in the iOS provider,
source-over blending, or device pixel result. The phone provider still vends
only its existing `read_surf` pair. No additional function object is returned
merely because these host binaries exist.

No BOOT, SYSTEM, or USERDATA write was made for this experiment.

## Release compiler ordering and regression gate

The corrected compiler follows Mesa 26.2.4 `pan_compiler.h`:

1. Early graphics I/O and system-value lowering.
2. `pan_preprocess_nir`.
3. The authenticated texture/buffer descriptor, fragment-position,
   push-to-UBO and half-quantization lowerings, followed by DCE and NIR validation.
4. `pan_postprocess_nir`, followed by NIR validation.
5. Only generated system-value inlining, followed by final NIR validation.
6. `pan_shader_compile`.

The T720 postprocess itself generates viewport and sampler LOD system values
(the latter for the Midgard LOD erratum). Their final replacement with the
fixture viewport or actual sampler UBO is the release contract's permitted
sysval-inline phase. Half arithmetic no longer runs after postprocess. The
compiler requires active NIR validation and refuses an `NDEBUG` build. Its
varying policy still uses the upstream untrusted high-precision uint producer;
the job builder must describe that producer as uint independently of the
fragment consumer's float interpretation.

Both actual AIR pairs were freshly translated using SPIRV-Tools v2026.4
(`vulkan1.2: PASS`) and recompiled after these ordering changes. All four
Midgard binaries remain byte-identical to their earlier authenticated values:

| Pair/stage | Bytes | First tag | Work registers | TLS/WLS | SHA-256 |
| --- | ---: | ---: | ---: | --- | --- |
| read_surf vertex | 208 | 5 | 1 | 0/0 | `c6ee709a69f08c5d556399155fd881b648f50ba368f630ccf315824aa467eef7` |
| read_surf fragment | 1232 | 5 | 6 | 0/0 | `a87ae5aef8fd86863bf2d62b57924243107defddcb2da91ae172affc646a3b23` |
| downsample_4 vertex | 2048 | 5 | 8 | 0/0 | `f5556b29f212c3674cb16b166a7dbf93671b4c27b7c65e54b78d77a2837f2be1` |
| downsample_4 fragment | 3472 | 5 | 7 | 0/0 | `1771f55d5bf91525734b33166e001bdf2b402e7467988c366016c8c1f8ff2a82` |

Run the complete host regression against staged proprietary inputs:

```sh
python3 test_compiler_profiles.py \
  /private/tmp/a5xelte-mesa-full/buildtools \
  /private/tmp/a5xelte-root-view/System/Library/Frameworks/QuartzCore.framework/default.metallib \
  /private/tmp/a5-metal2vulkan/target/release/metal2vulkan \
  /private/tmp/a5-metal2vulkan/crates/metal2vulkan-validation/profiles/vk12-floor.json \
  /private/tmp/a5-spirv-tools/spirv-tools/1.4.363.0/bin/spirv-val \
  /private/tmp/a5-compiler-profile-regression
```

This gate validates both genuine SPIR-V pairs, compiles four authenticated
stages with matching renderer metadata, verifies malformed SPIR-V is rejected
by the actual validator, rejects a module used under the wrong compiler profile,
and checks missing validation fails before translation. Logs and the metadata
manifest remain in the private output directory. No generated shader is added
to Git. These are compiler checks; unchanged shader bytes do not establish
correct device pixels, and the earlier 0169 DS4 device pixel oracle failed.


## Release Panfrost correction candidate 0170

The released v4 job contract now includes vertex task split5, distinct U32 VS
varying and F32 FS consumer formats for DS4, tile-unit fragment bounds,
contiguous varying buffers, special position/point-size formats and a real
nonempty read_surf heap. The generated read_surf allocation is12 KiB; historical
8 KiB hashes above describe earlier trials. Kernel AS1 maps all three pages.
Actual source/destination byte strides are relocated by the validated kernel
read_surf path, so padded4352-byte IOSurfaces do not require repacking to4320.
The genuine pair's shader bytes remain unchanged after the compiler-order fix.
The candidate still requires new device pixel evidence.
