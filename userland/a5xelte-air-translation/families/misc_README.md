# Miscellaneous QuartzCore families and real GPU fixtures

`misc_compile.py` translates exact stock functions with all actual AIR outputs,
requires real SPIRV-Tools validation, then compiles selected per-target T720
stages. `misc_manifest.json` records full-attachment metadata and nine explicit
replay profiles. Generated shaders and raw logs stay outside Git.

| Family | Original rows | Native outputs | VS / selected FS bytes |
| --- | --- | --- | --- |
| `buffer_image_blit_*_lph` | 141,264,280 | BGRA/BGRA; R8/RG8; RGBA16/RGBA16 | 2000 / 1776 UNORM,1872 RGBA16 |
| `std_vert1_lph` / `home_affordance_base_lph` | 204 | BGRA | 2192 / 3424 |
| `path_blit_vert_lph` / `attachment_clear_frag_lph` | 166 | BGRA/BGRA | 960 / 176 |

The first single-color0 experiment omitted real RT1 outputs for blit/clear.
Those partial outputs are superseded. Full translation now retains both RT0
and RT1; the `w` blit pipeline configurations also declare attachment2 R32Float
(the actual AIR does not write RT2). R8's secondary format is RG8, as verified
from QuartzCore's actual attachment setter.

## Explicit SFBD replay

Released v4 supports one SFBD color target. The two blit AIR return members are
both the same computed `half4`; clear returns two zero `half4` members. These
functions have no memory writes, framebuffer reads or ordering side effects.
The compiler preserves full AIR/SPIR-V first, then explicitly selects RT0 or
RT1 and maps that target to the SFBD output. Separate fixture cases verify both
logical outputs. This is not a claim of native MRT support.

## Native resource and format contract

`misc_resource_lowering.h` maps uniform binding N to hardware UBO N+1, reserving
stage UBO0. Actual SSBO global loads read GPUVA/size records from UBO0 byte
`96+16*N`, following released `nir_lower_ssbo` and Panfrost sysvals. No storage
buffer is replaced by a UBO or empty data. Viewport and draw values are dynamic.

`misc_native_rt.h` converts actual half4 output values through released
`pan_nir_lower_framebuffer` packing. RG/BA become two32-bit raw words for
`RAW_VALUE`/`2_32B_CHANNELS` SFBD RGBA16 storage. This changes actual machine
code, unlike relabeling the former UNORM output.

Home affordance retains two separate sampled textures and actual constexpr
linear/clamp sampler state. Renderer metadata includes the correct mapped UBO
table extents and texture bitsets. Storage vertices require18 attribute slots,
including released VertexID/InstanceID special descriptors.

## On-device test payloads

`make_misc_suite.py` plus `build_misc_suite.c` produce nine private payloads,
each exactly256KiB at GPUVA `0x02000000`, with vertex/tiler chain0/0x100 and
fragment job0x200. Packing readback verifies job, framebuffer, heap, renderer
and special attribute fields. Input shaders must match the compilation manifest.

Independent pixel oracles cover nonuniform byte-mask times tint, the two-texture
home source/luminance/lookup operation, and clear outputs. The GPU destination
starts with poison, never CPU expected pixels. Sources, uniforms, output padding
and outer guards are immutable checks. All stages have zero TLS/WLS.

These are prepared GPU tests. Device fence completion, pixels and guard results
must be read from the phone before claiming runtime success or iOS integration.
