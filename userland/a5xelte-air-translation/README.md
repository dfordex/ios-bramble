# QuartzCore AIR to Mali T720: verified compiler boundary

This note is based on a **local, read-only** inspection of the staged iOS
16.7.16 root and the locally available Mesa 26.2.4 source/build tree. It does
not include Apple shader bodies, extracted bitcode, generated SPIR-V, or a
Metal provider. It is not a shader translator or a claim that iOS rendering
has reached Mali.

## An actual iOS graphics input

`System/Library/Frameworks/QuartzCore.framework/default.metallib` contains
141 function records: 39 vertex, 95 fragment and 7 kernel functions (the
`TYPE` values are respectively 0, 1 and 2). Each has `NAME`, `TYPE`, `HASH`,
`OFFT`, `VERS`, `MDSZ` and `RFLT` tags. One vertex entry is
`std_vert0_lpf`. Its embedded bitcode wrapper starts with the known LLVM
bitcode magic and has a declared payload offset and length.

The first payload was extracted **only to `/private/tmp`**, using the wrapper's
exact length. Homebrew LLVM 22.1.8 `llvm-dis` accepted it. The resulting IR
identifies `air64-apple-ios16.7.0`, `!air.vertex`, `air.position`, vertex input
locations, and a constant-buffer matrix input. This demonstrates that the
input is a graphics-stage AIR module whose parameter metadata is needed to
produce a vertex shader interface. Passing the entire metallib, or the
wrapper plus trailing bytes, to `llvm-dis` fails; the exact payload bounds
matter.

## Why generic LLVM does not yield a Mali shader

After removing an empty `@llvm.global_ctors` declaration from the temporary
IR, LLVM 22 `llc -march=spirv64 -filetype=obj` emitted a SPIR-V binary. Its
text form begins with `OpCapability Kernel`, `OpCapability Addresses`,
`OpMemoryModel Physical64 OpenCL` and `OpSource OpenCL_CPP`. It exports the
function with `LinkageAttributes`; it has **no graphics `OpEntryPoint`**.
These facts are observable without retaining or publishing the shader body.
This SPIR-V is not a Vulkan vertex shader and cannot be passed directly to
the Mesa Midgard graphics path while preserving Metal's vertex parameters,
bindings and output semantics. The same problem exists for fragment outputs,
textures, samplers, interpolation and render state.

Mesa's Midgard entry point is `midgard_compile_shader_nir(nir_shader *,
const pan_compile_inputs *, util_dynarray *, pan_shader_info *)` in
`src/panfrost/compiler/midgard/midgard_compile.h`. It compiles **NIR**, after
stage-specific Mesa/Panfrost lowering. The local Mesa build has
`libpanfrost_midgard.a` and `libnir.a`, but linking those libraries to an
untranslated AIR module does not supply a `nir_shader` with correct graphics
stage interfaces or resource binding information. The existing XNU fixed
BGRA encoder is also not an AIR/NIR shader compiler.

The open-source [metal2vulkan](https://github.com/steelbrain/metal2vulkan)
project explicitly translates AIR with Metal-shaped pipeline inputs into
SPIR-V graphics stages. Its **runtime** requires a Vulkan 1.2 device. The
Mali T720 is Midgard and the [Mesa Panfrost capability table](https://docs.mesa3d.org/drivers/panfrost.html)
lists its OpenGL/GLES path, not a Vulkan implementation. Using that runtime
would not create a T720 backend. Its translator could inform a future
AIR-to-NIR bridge, but the bridge must preserve Metal reflection, render
pipeline state, descriptor/buffer layouts and errors, and feed the Midgard
compiler plus XNU job/resource queue.

## Completion criterion

For a concrete first shader, select `std_vert0_lpf` and a matching QuartzCore
fragment function, compile both to NIR with the actual AIR argument metadata,
then to Midgard binary and a full render-job descriptor. Validate the output
pixels and synchronization from an actual QuartzCore command on the phone.
An `MTLCreateSystemDefaultDevice` success, a metallib parser, or a SPIR-V
binary with OpenCL `Kernel` capability would not satisfy this criterion.

No BOOT or SYSTEM write was made during this inspection.
