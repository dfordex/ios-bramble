# QuartzCore `read_surf` to Mali T720: local graphics shader proof

This directory compiles **one actual stock iOS 16.7.16 QuartzCore graphics
pair** to Mali T720 Midgard machine code on a Mac. It is a host experiment,
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
create and check one **host-only** 8 KiB GPU descriptor page for the two exact
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

No BOOT, SYSTEM, or USERDATA write was made for this experiment.
