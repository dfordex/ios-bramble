# Captured QuartzCore generic fragment, host compilation

`compile_0185.py` reproduces one narrowly identified shader compilation. A
device log captured 58 named function constants while QuartzCore requested
`fixed_frag_lpf_cpf`. That function does not exist in the staged stock
QuartzCore library. After the Metal provider reports the T720's actual native
FP16 support, QuartzCore's selection logic is expected to request the stock
`fixed_frag_lph_cpf`. This script translates that real function with all 58
captured constants. It does not rename or substitute the missing function.

Inputs are the private capture JSON, stock QuartzCore `default.metallib`,
`metal2vulkan-host`, `spirv-val`, its Vulkan 1.2 floor profile, and a Mesa
Panfrost build directory. Invoke `python3 compile_0185.py --help`. Keep
`--output` outside the checkout. The script requires an empty output folder,
validates both SPIR-V stages, privately patches the existing host backend to
lower initialized NIR temporaries, compiles T720 Midgard, and writes
`receipt.json`. The four SPIR-V/Midgard hashes are pinned in the source. An
integrator can import `validate_receipt(receipt_path, capture_path,
metallib_path)` before consuming the private output.

For the captured constants, host optimized native fragment reads only
interpolated `VAR0` float4 and hardware UBO 0 at byte `0x44` (ColorWriteRule),
then writes render target 0. Fragment Metal Buffer 1 (168 bytes) and the
translator's 16 byte SyntheticConstantBlob remain declared in reflection but
are dead in native code for this exact specialization. There are no surviving
texture, sampler, storage, or input attachment reads. A real color rule value
is still required; BGRA8Unorm uses `0x2222` in the available metadata.

The candidate `std_vert0_lph` vertex shader reads original Metal Buffer 1,
stride 48: Float4 at offset 0 and Half4 at offset 32. It reads a 64 byte
matrix from Metal Vertex Buffer 2 (hardware UBO 1), and viewport scale/offset
from hardware UBO 0 at bytes `0x200` and `0x210`. It emits position, point
size, and `VAR0` color. The 0185 phone capture did **not** include the actual
vertex function, vertex buffer layout, topology, color attachment format, or
blend state. BGRA8Unorm and triangle topology are host assumptions. A pair or
draw must not be reported as device verified from this compilation alone.

This directory contains no stock AIR, metallib, SPIR-V or Midgard bytes. Keep
generated outputs private and out of Git.
