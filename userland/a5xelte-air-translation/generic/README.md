# Captured QuartzCore generic fragment, host compilation

`compile_0185.py` reproduces three narrowly identified host compilations. The
0185 device log captured 58 named function constants while QuartzCore
requested `fixed_frag_lpf_cpf`, which does not exist in the staged stock
QuartzCore library. The earlier `fixed_frag_lph_cpf` compilation was an
**offline probe of an available stock function**, not a device-observed
replacement or a name alias. After the provider's FP16 capability correction,
the 0186 device log actually requested `fixed_frag_lph_cph` with the same 58
constants. The 0186 profile compiles this exact stock function. QuartzCore's
CP precision selection depends on another config bit; native FP16 alone did
not imply the earlier CPF prediction.

The 0187 device capture names the actual vertex function
`fixed_vert_lph_spc` and four named function constants, all zero. Supply its
JSON with `--vertex-capture` alongside the 0186 fragment capture to select
profile 602. The script requires the exact capture hashes and compiles the
actual vertex and fragment AIR rather than a substituted vertex name. Without
`--vertex-capture`, profiles 600 and 601 retain the earlier `std_vert0_lph`
host candidate; profile 601 alone is not proof of the live vertex stage.

Inputs are the private capture JSON, stock QuartzCore `default.metallib`,
`metal2vulkan-host`, `spirv-val`, its Vulkan 1.2 floor profile, and a Mesa
Panfrost build directory. Invoke `python3 compile_0185.py --help`. Keep
`--output` outside the checkout. The script requires an empty output folder,
validates both SPIR-V stages, privately patches the existing host backend to
lower initialized NIR temporaries, compiles T720 Midgard, and writes
`receipt.json`. The four SPIR-V/Midgard hashes are pinned in the source. An
integrator can import `validate_receipt(receipt_path, capture_path,
metallib_path)` before consuming the private output.

For these exact constants, the two optimized native fragment binaries are
byte-identical. The resulting fragment reads only
interpolated `VAR0` float4 and hardware UBO 0 at byte `0x44` (ColorWriteRule),
then writes render target 0. Fragment Metal Buffer 1 (168 bytes) and the
translator's 16 byte SyntheticConstantBlob remain declared in reflection but
are dead in native code for this exact specialization. There are no surviving
texture, sampler, storage, or input attachment reads. A real color rule value
is still required; BGRA8Unorm uses `0x2222` in the available metadata.

The actual `fixed_vert_lph_spc` shader in profile 602 and the earlier
`std_vert0_lph` candidate compile to byte-identical native vertex code for
these constants. QuartzCore configures original Metal Buffer 1 with stride
48 and four attributes: Float4 at offset 0, Float2 at offset 16, Float2 at
offset 24 and Half4 at offset 32. The specialized vertex shader uses only
the Float4 and Half4 inputs. It reads original Metal Buffer 1,
stride 48: Float4 at offset 0 and Half4 at offset 32. It reads a 64 byte
matrix from Metal Vertex Buffer 2 (hardware UBO 1), and viewport scale/offset
from hardware UBO 0 at bytes `0x200` and `0x210`. It emits position, point
size, and `VAR0` color. The 0187 capture identifies the live vertex function,
but no phone capture establishes the render target format, blend state,
topology, resource contents, or executed GPU job. BGRA8Unorm and triangle
topology remain host assumptions. A draw must not be reported as device
verified from this compilation alone.

This directory contains no stock AIR, metallib, SPIR-V or Midgard bytes. Keep
generated outputs private and out of Git.

## 0189 textured variant

`compile_0189.py` separately compiles the 0189 device-captured
`fixed_frag_lph_cph` request with its exact 58 named constants. The matching
`fixed_vert_lph_spc` specialization with four named constants is a **host
candidate** until a live vertex request confirms it. The recipe requires the
stock QuartzCore library SHA, exact capture hash, reflected ABI, validated
SPIR-V, final native metadata and both native hashes. SamplerState spec ID 0
is fixed at 1 for ClampToEdge; the runtime must admit only that sampler state.

The candidate vertex reads Float4 position, Float2 UV and Half4 color from
the original 48-byte Metal vertex layout. It also reads Metal Vertex Buffers
2 and 3. The fragment samples Metal Texture 3 with runtime Sampler 0, reads
Metal Fragment Buffer 2 for LOD bias, and reads texture dimensions from UBO 0
at bytes `0x164` and `0x168`. The BGRA8Unorm ColorWriteRule push is at byte
`0x48`. Fragment Buffer 1 and SyntheticConstantBlob are declared but dead in
the optimized native shader. The host result is 2192 vertex bytes and 976
fragment bytes; it does not establish phone execution or visual correctness.
