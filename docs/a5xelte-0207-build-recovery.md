# 0207 local build restoration

The prior temporary build trees had disappeared. This build restores their
inputs without reading BOOT as a backup, modifying recovery or transferring the
whole USERDATA filesystem. Generated Apple artifacts remain private.

## Recovered inputs

- The pinned donor buildtree from its successful CI run supplies XNU8796,
  shared HFS/pthread/BearSSL sources and exported headers. Samsung patches82–202
  are applied to that donor checkpoint.
- Exact HFS metadata and selected file ranges recover the installed QuartzCore
  metallib, launchd cache, signed validator and known compiler recipe JSON files.
  The stock metallib is1,014,944bytes and retains the existing pinned SHA256.
- The installed unstripped Metal provider exposes local registry symbols.
  Bounded chained-offset pointers recover all29 profiles, binding/state arrays,
  typed constants and native code. Every native shader hash is verified.
  Re-emitting the old registry reproduces its installed Info.plist SHA256
  **a1cb8d3b0fe6af51c2aa2f52a688f8a01a4a011d67440ce0343b6672b9eea3f0**.
  Adding explicitNULL/0 initializers for the new immutable-sampler fields changes
  only the generated structure initialization; earlier contract fields remain.
- Official Mesa26.2.4 and SPIRV-Tools sources restore host compilation tools.
  Actual Xcode MIG tools, Apple AvailabilityVersions121 and a newly compiled
  Cortex-A53 libdispatch1415.140.2 firehose library restore kernel prerequisites.
  Disassembly contains no LSE operations. Supported `DO_CTFMERGE=0` omits CTF
  debugger metadata; the unstripped kernel and dSYM remain available.

## Source reconstruction

Some historical patches have short/miscounted hunks, zero-context insertions and
blank-only context drift. Replacing an entire hunk after ignoring blank lines
was incorrect: it removed otherwise unchanged blank lines and displaced later
insertions into declarations or functions. That intermediate tree was rejected.

`tools/a5xelte-apply-patches.py` first uses Git's recount/unidiff-zero handling.
Its fallback requires exact nonblank source lines, preserves unmatched blank
context, tracks actual hunk offsets and rejects ambiguous placements. It refuses
an existing Samsung overlay and requires the contiguous requested patch series.
It operates only on local source paths; it does not access a phone.

A second fresh replay of82–202 matches all5,263 donor/source files byte for byte
against the final staged tree. Eleven final checks cover suite and native-queue
file scope, gated suite invocation, preload bounds, resource-slot fields,
mapping-method scope, epoch updates before mapped-state reset, complete ABI
assertions and real OOL descriptor prepare/complete. The final full XNU make
exits0. These checks establish reproducible build placement, not device behavior.

## Pixel-test reconstruction

The deleted private27-case payload hashes are unavailable. The prior27 cases are
therefore reconstructed, rather than claimed byte-identical to their old
payloads: nine real blur translations, nine miscellaneous cases, three path
cases, two604/605 cases, two606 A8 cases and two real worker-published unknown
A8-stage cases. Their independent pixel oracles, poisoned initial outputs,
immutable guards and terminal-fence requirements remain. Four new fetch/noise
cases produce31 embedded cases in total. Host embedding validates all31 payload
and oracle contracts; physical results await the next boot.

## Samsung packaging

A public a5xelte TWRP3.3.0 image supplies only the offline Android BOOT header
and DTBH template, including Exynos7580 hardware revision4. The repository's
Samsung EL1 loader and ADT are rebuilt from source. The template's OS-version
field is normalized to0 for the existing packer; current four-CPU, storage,
input, display and graphics boot arguments are preserved. The intermediate
reference has a dummy kernel payload and must never be flashed. The final
packer replaces it with the newly linked real kernel. No installed recovery or
BOOT partition is read or modified during this reconstruction.
