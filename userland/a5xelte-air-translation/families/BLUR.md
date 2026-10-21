# Bounded QuartzCore blur compilation

`translate_blur.py` compiles the eight requested real fragment functions,
paired with the actual `downsample_blur_vert_lph`. It reads the local metallib,
requires real SPIRV-Tools validation and checks the reflected ABI before
passing its generated SPIR-V to released Mesa26.2.4's T720 compiler. The
isolated backend keeps NIR validation enabled. Shader bodies, generated code,
metadata and compiler logs remain in the private output directory.

```sh
python3 translate_blur.py \
  --metallib /private/path/default.metallib \
  --translator /private/path/metal2vulkan-host \
  --spirv-val /private/path/spirv-val \
  --profile /private/path/profile.json \
  --mesa-build /private/path/mesa-build \
  --inventory /private/path/a5-quartzcore-coverage-0164.json \
  --output /private/path/blur-results
```

All selected warmup entries have no Metal function-constant values.
Their SPIR-V resource specializations are checked independently: vertex
range IDs1/2 are64/16 bytes; fragment sampler ID0 is the normalized-nearest
state0, range ID3 is the actual window below, and range ID4 is2 bytes.
These nonzero ranges preserve the shader's resource accesses. Weights,
matrices, offsets and EDR scale remain dynamic buffer data; the compiler
supplies no replacement values for them.

| Fragment | Fragment Metal buffer1 window | Native fragment bytes | Work registers | TLS bytes |
| --- | ---: | ---: | ---: | ---: |
| downsample_8_frag_lph | 32 | 8624 | 9 | 0 |
| narrow_blur_7_frag_lph | 82 | 3392 | 8 | 0 |
| narrow_blur_11_frag_lph | 82 | 4160 | 12 | 0 |
| narrow_blur_15_frag_lph | 82 | 4880 | 13 | 0 |
| narrow_blur_19_frag_lph | 82 | 5744 | 16 | 0 |
| narrow_blur_23_frag_lph | 82 | 6672 | 16 | 32 |
| narrow_blur_27_frag_lph | 82 | 7472 | 16 | 64 |
| single_pass_blur_3_lph | 82 | 3456 | 7 | 0 |

The recipe also compiles `narrow_blur_23_frag_lph` with RGBA16Float: actual
translated Vulkan format97 and color-write rule0x3333, followed by a successful
T720 compile. The SPIR-V bytes match the BGRA variant because its color-write
rule is dynamic; the actual native fragment now additionally follows released
Mesa's RAW64 half packing:6752 bytes,16 registers,32-byte TLS. The source helper
`misc_native_rt.h` converts the genuine half4 color to packed RG/BA words with
`pan_nir_lower_framebuffer`; changing only the SFBD is insufficient. The dynamic
color-write rule must be0x3333 rather than0x2222 for this attachment. The manifest preserves all10 blur
warmup row identities, including separate row247 BGRA and row287 RGBA16Float.

The attachment mapping comes from QuartzCore UUID
`9e40b2eb-260c-3af1-ae45-a1a551a8c1b9`, symbol
`MetalContext::MTLPixelFormat_codes` at`0x1d5b46d78`, with8-byte entries:
Metal format115 maps to`RGhA` (RGBA16Float),80 to`BGRA`, and65 to`2C0h`
(RG16Float). Prefix similarity alone is insufficient evidence for RG16Float.
The source-only native format-table audit belongs to the parent integration.

These are host compilation results for the reviewed local input/profile.
The manifest records input/tool/output digests and per-stage resource data;
changed inputs must pass the reflection checks and compile again. All eight
vertex outputs are2048 bytes with8 work registers and no TLS/WLS. This does
not establish correct rendering or compositor integration on the phone.

## Native binding contract

The vertex descriptor is Float4@0, Float2@16, Float2@24, Half4@32 with48-byte
stride in Metal vertex buffer1. It is checked against the shared downsample
contract. Actual vertex resources Metal buffers2/3 map to UBO1/2; actual
fragment buffers1/6 map to UBO3/4. A single sampled2D texture in Metal slot3
and sampler0 map to native descriptor0. Resource descriptor set/binding and
uniform-buffer shape are checked in the NIR lowering; unsupported shapes fail.

Stage-local UBO0 preserves push data (vertex bytes0..7, fragment bytes64..75),
texture level/width/height values at byte offsets0/4/8 and sampler minLOD,
maxLOD and bias at16/20/24. The native viewport is explicitly1080x1920 with
baseVertex0. A different viewport, sampler specialization or resource layout
needs its matching binding contract. No runtime code is installed by this tool.

The larger shaders need allocation by their actual code size. In particular,
blur23/27 require genuine Midgard per-thread TLS allocation of32/64 bytes;
zero-scratch runtime paths cannot consume them. Instruction compilation alone
does not implement that resource or authorize submitting a mismatched job.

## Executable GPU fixtures

`build_blur_suite.py --compiled PRIVATE/manifest.json --mesa-build MESA_BUILD
--output PRIVATE/gpu-fixtures` emits nine complete256KiB payloads and independent
CPU pixel oracles. Jobs are at0/0x100/0x200 and baseVA is0x02000000. The builder
reads actual native code bytes with digest/length checks and reads packed v4
state back before publishing each payload. The manifest lists output windows,
integer element comparison widths, tolerances and immutable source/guard ranges.

Each fixture samples a nonconstant64x64 RGBA8 stripe pattern and renders32x32.
The source's channels are exactly0/1. DS8 uses the actual16 signed-reflection
taps and fixed1/16 coefficient. Narrow blur uses its actual symmetric2..7 tap
pairs with nonzero dyadic coefficients summing to1/2; the `divide` field is1,
so the real normalization branch runs with exact alpha1. Single-pass3 uses its
actual four offsets with coefficient1/4. Nonzero offsets cross stripe edges;
all variants use EDR1/2. The CPU oracle evaluates these tap/coefficient rules,
not the generated machine code. RGB values remain exactly representable in half;
BGRA8 comparisons allow one byte and RGBA16Float allows one positive half ULP.

The64KiB TLS allocation at+0x10000 covers up to4 core IDs with256 threads/core
and64 bytes/thread, following `pan_scratch.c`. Fixtures require measured
SHADER_PRESENT=3 before dispatch. TLS is packed in the framebuffer's actual
LOCAL_STORAGE descriptor (shift1 for32B,2 for64B). Source data and guards remain
separate from shader code, tiler lists/heap, output and TLS. Payload creation and
packed readback establish a runnable input contract; device execution and pixel
comparison remain separate evidence.

## Measured phone result

0174 executes all nine fixtures successfully on T720: complete vertex/tiler
and fragment fences, MMU IRQ0, full output reference matches and intact immutable
regions. This includes native TLS32/64 and RGBA16 half packing. See
`docs/a5xelte-shader-suite-results.md` for scope and remaining other-family failures.
