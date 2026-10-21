# AIR entry point for a future A5XELTE Metal backend

`metallib.c` is a portable, allocation-free reader for the `MTLB` function
table and wrapped LLVM AIR bitcode. It returns borrowed, bounded function views
to the caller. It can be compiled into an iOS Metal provider. `air_inspect` is
only a host inspection tool; it does not belong in a device boot image.

Build and inspect a local, uncommitted metallib:

```sh
clang -std=c11 -Wall -Wextra -Werror -pedantic \
  metallib.c air_inspect.c -o /tmp/a5-air-inspect
/tmp/a5-air-inspect /path/to/default.metallib
/tmp/a5-air-inspect /path/to/default.metallib function_name /tmp/function.bc
llvm-dis /tmp/function.bc -o /tmp/function.ll
```

On the staged QuartzCore `default.metallib` from this lab's iOS root,
the parser found 141 functions: 39 vertex, 95 fragment, and 7 compute.
LLVM 22 disassembled every extracted bitcode payload. 122 functions contain
at least one `air.*` intrinsic; examples include texture sampling, saturation,
and framebuffer access. The inspected `std_vert0_lpf` has target triple
`air64-apple-ios16.7.0` and AIR vertex metadata. The first extracted payload
matched a separate direct wrapper extraction byte for byte. These are
container and IR observations, **not a runnable shader translation**.

The required implementation path is:

1. Parse the stock metallib/AIR entry points and bind their AIR arguments to
   Metal pipeline state, render targets, textures, samplers, buffers, and
   function constants.
2. Lower AIR instructions and Metal semantics to a portable shader IR. The
   [metal2vulkan translator](https://github.com/steelbrain/metal2vulkan)
   describes an AIR-to-SPIR-V route, but its Vulkan runtime cannot run on the
   Mali T720 without a Vulkan driver. The translator alone would still need a
   SPIR-V-to-NIR integration, the complete Mesa Midgard compiler, and validated
   descriptor/resource mapping.
3. Compile NIR to Midgard machine code, package shader descriptors and state
   in kernel-owned BOs, and expand the typed 0151 queue to the needed draw,
   blend, texture, and synchronization operations.
4. Integrate a real Metal device/queue/pipeline provider with iOS and verify
   output on the phone. The current private 0151 queue accepts only BGRA8
   clear/copy. It does not accept AIR, NIR, SPIR-V, or arbitrary iOS drawing.

No proprietary `.metallib`, AIR bitcode, or extracted iOS file is stored here.
Unsupported library layouts and malformed offsets return an error rather than
guessing a function or shader.
