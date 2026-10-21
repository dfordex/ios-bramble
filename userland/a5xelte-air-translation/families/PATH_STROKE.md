# Actual QuartzCore path and stroke compilation

`translate_path.py` runs the original staged metallib through metal2vulkan,
mandatory real `spirv-val`, and Mesa 26.2.4 Panfrost T720. All Apple input,
SPIR-V, machine code and verbose logs must stay in a private output directory.
This is host compiler coverage, not proof of correct phone rendering or a
complete Metal implementation.

Build the source-only family compiler:

```sh
python3 build_path.py MESA_BUILD PRIVATE_OUTPUT/path-midgard
python3 translate_path.py --metallib PRIVATE_METALLIB \
  --translator METAL2VULKAN_HOST --validator SPIRV_VAL \
  --profile VK12_FLOOR_JSON --compiler PRIVATE_OUTPUT/path-midgard \
  --output PRIVATE_OUTPUT
```

The JSON manifest records each exact entry pair, row, attachment format,
reflected interfaces, actual input/output digests, compiler counts, and failure
stage. Translation failures remain failures; no shader is substituted.

## Exact attachment and input evidence

For QuartzCore UUID `9e40b2eb-260c-3af1-ae45-a1a551a8c1b9`:

- Rows 152/153/263 use `PBGR...`: Metal80 BGRA8Unorm.
- Row283 uses `PRGhA...`: Metal115 RGBA16Float, **not** Metal65 RG16Float.
  The actual `MetalContext::MTLPixelFormat_codes` table at `0x1d5b46d78`
  (eight byte string pointers) has index115 `RGhA`, index65 `2C0h`,
  index80 `BGRA`, and index10 `L008`.
- All four names lack `L`, selecting packing0. At `0x188565090`, header
  `0x0130` gives stride48/count4. Entry words `0x00f8`, `0x10e9`, `0x18ea`,
  `0x20db` give Float4@0, Float2@16, Float2@24, Half4@32, all vertex buffer1.
  Setter code is `0x1883816b0..0x188381714`.
- The successful path_cubic/path_rect/stroke_line translations actually have
  no Vulkan vertex attributes: they pull vertex data from Metal buffer1 SSBO.
  The descriptor is supplied faithfully, but no dummy input is inserted.

## Native resource contract

The shared `misc_resource_lowering.h` preserves SSBO global memory reads.
Vulkan uniform binding N maps to hardware UBO N+1. Vertex uniform buffer2
requires64 actual bytes; buffer5 requires16 (paths) or24 (stroke). These exact
nonzero `RangeAtBindOffset` specializations come from reflected bounded windows.
Stage UBO0 contains actual push bytes, plus:

| Byte | Actual runtime value required |
| --- | --- |
| 96+16*N | SSBO binding N GPUVA:u64, byte size:u32, reserved:u32 |
| 512 | viewport scale float3 |
| 528 | viewport offset float3 |
| 544 | raw vertex offset u32 |
| 552 | base instance u32 |

These are required runtime bindings, not constants or proof that the current
stock Metal submission implementation already supplies them. The compiler
remaps descriptors, lowers explicit SSBO I/O using upstream `nir_lower_ssbo`,
then lowers `load_ssbo_address/get_ssbo_size` using those actual records. It
runs active NIR validation before/after the Panfrost preprocess/postprocess
boundary and before native compilation. Hardware UBO count is recomputed after
remapping. Built-in vertex/instance IDs account for the native attribute count;
they must receive proper native special attribute descriptors at submission.

## Complete attachments; revoked empty-fragment result

All four actual `A3w` pipeline profiles have three attachments: 0/1 use the
primary format (BGRA8Unorm or RGBA16Float), and2 is R32Float. Both path_cubic
and path_rect AIR return a real float `coverage` output at render_target2.
Stroke returns the same half4 value at render_target0 and1.

**The earlier empty fragment result was an incomplete descriptor test.** Giving
only attachment0 caused metal2vulkan to eliminate the real attachment2 output.
It is revoked as actual QuartzCore pipeline evidence; these are not stencil-only
or canonical no-FS paths. The recipe now supplies all three exact formats.
The full fragments compile to real machine code (cubic1728B, rect560B,
stroke1568B at this profile).

An additional compiler defect surfaced with those real fragment bodies:
fragment-position lowering used base0, colliding with generic varying0. It now
uses the next unique input descriptor index, preserving the hardware fragment
coordinate special descriptor37 independently of flat generic inputs.

## Native framebuffer fetch and T720 MRT limit

`path_blit_frag_lph` reads and writes framebuffer attachment2. The ordinary
Vulkan1.2 floor profile correctly rejects ordered attachment access. The recipe
preserves that rejection, then separately compiles a **native ordered tilebuffer
profile**. This does not advertise a Vulkan extension implementation.

The actual QC row152 descriptor has attachment0/1 BGRA8Unorm and attachment2
R32Float. Token `w` at NameDecoder table `0x1d5b47fd0` calls `0x18848794c`,
setting PipelineSpec byte0x15 bit7; pipeline creation `0x188381774..0x188381798`
selects Metal55 for attachment2. `add_path_buffer_texture` at `0x188343a28`
creates R32Float, memoryless storage3, usage5 (ShaderRead|RenderTarget).
`start_render_encoder` at `0x1882d46d4..0x1882d46f8` forces clear loadAction2
for this attachment. `set_surface` at `0x1882ede2c..0x1882ede90` sets zero clear
color and DontCare storeAction0 for memoryless storage. These requirements are
recorded in the manifest. They cannot be replaced with a zero read: subsequent
fragment invocations read actual accumulated values within that pass.

The adapter checks the original SubpassData image binding3/index2, single-sample
(non-MS) type, float32 result, zero pixel offset and LOD0. It preserves the
native attachment number with `load_output(FRAG_RESULT_DATA2)`. Released Mesa
`pan_nir_lower_framebuffer` performs R32Float raw unpack; component reordering
is identity for this single-channel format. Released Midgard emits an actual
RT2 `LD_SPECIAL.u32` instruction, not a sampled texture or a constant.

Source references: Mesa26.2.4 `pan_shader.c:173..177` applies framebuffer
lowering to ordinary Midgard fragment shaders; `pan_nir_lower_framebuffer.c`
uses actual render-target format; `midgard_compile.c:1725..1785` emits native
raw/typed tilebuffer reads, including the T720 OLD_BLEND opcode path. Native
runtime correctness still requires the actual three-attachment renderer state,
load/store/clear behavior, ordered tile execution, and draw/resource bindings;
this host compilation does not establish those device-side conditions.


## Isolated device suite

`build_path_suite.py` compiles actual single-target variants from the complete
validated SPIR-V; it never synthesizes shader bodies. It emits source-only
`build_path_suite.c` descriptors plus private 0x40000-byte payloads, expected
pixel files, byte masks, immutable-region definitions and a runner manifest.

T720 is v4: released `pan_get_max_cbufs` (`pan_props.h:105..108`) returns1 for
arch<5; the v4 `pan_emit_fbd` branch asserts `rt_count<=1` and emits a single
color plane. Therefore original simultaneous MRT execution is not claimed.

The isolated variants explicitly perform these portability transformations:

- Cubic and rect: remap their sole R32Float coverage output2 to sole SFBD
  output0, preserving the actual fragment computation and resource reads.
- Stroke: specialize both actual RGBA16Float color rules to0x3333, use NIR
  CSE and prove the two output SSA values/write masks identical, then collapse
  duplicate output1 into output0. Failure of equivalence rejects compilation.
  Released Panfrost framebuffer-format packing converts the real result into
  native v4 raw half storage; no CPU rendering or dummy fragment is substituted.
- Original path_blit remains blocked: it consumes ordered R32Float output2,
  writes zero back there, and writes colors0/1. A general dependency-aware
  multipass implementation is still needed. No unsupported MFBD is submitted.

Fixtures bind real SSBO pointers, lengths, UBOs, viewport and draw builtins.
Vertex IDs use ordinary attribute slots16/17 referring to released vertex-ID
and instance-ID special buffer encodings; instance0 is actually generated.
Flat varying descriptors use U32, smooth values F32, and fragment coordinates
have a separate hardware special descriptor37. A real heap, source/shader
immutability checks and a guard region surround writable job state.

The32x32 oracles check nonzero interiors plus clear zero exteriors and mask
raster boundaries. Rect is `[-.5,.5]^2` with orientation1. Cubic uses the actual
polynomial coefficients `P(t)=(2t-.5,2t-.5)` for the first half interval,
with baselineX=.5, producing a nontrivial triangular coverage pattern. Stroke
uses endpoints(8,16)/(24,16), sidePad4, endPad0, and exact dyadic color
(.25,.5,.75,1). These are isolated numerical and binding tests, not proof of a
complete live QuartzCore rendergraph.
