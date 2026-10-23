# 0209: zero-input ordered fetch and indexed blur

## Two blockers from 0208

The phone compiled and published the actual 2448-byte `fixed_frag_lph_cph`
fragment, but the pipeline factory and native resource graph required a sampled
texture and UV interpolant. Its authenticated optimized ABI instead has no
fragment inputs, textures or samplers, and reads the ordered color attachment.
The adjacent indexed-draw rejection lacked its active profile; source inspection
also confirmed that the ten blur/downsample profiles had no indexed entry path.

## Implemented paths

- Admit a reflected zero-input fragment only with zero textures/samplers/live
  textures and a real ordered framebuffer-fetch attachment. The independent
  native graph gate requires exactly that attachment and forbids sampled,
  immutable, color-varying and FragCoord resources for this path. Keep its actual
  UBOs, output shape, shader identity and blend/state checks. Emit zero FS
  texture/sampler/varying counts and zero corresponding DRAW pointers; preserve
  actual VS exports and ordered tilebuffer preload.
- Route indexed blur profiles99..108 through the real released-Mesa emitter.
  Snapshot shared/private u16/u32 indices at command-buffer submission, validate
  their referenced vertex range, and emit the genuine JM index descriptor.
  The VS processes0..maxIndex and the vertex snapshot covers that exact span.
  No CPU vertex expansion or pixel rendering is introduced. Preserve profile100
  inactive RT1 mapping, resource lifetimes and genuine terminal fences.
- Keep bounded indexed failure metadata: actual profile, primitive, index count,
  width, offset, buffer length/readiness and reason. Do not infer the profile
  from the preceding unrelated pipeline log or silently ignore rejected work.

## Local checks

The full17-binary native suite passes, with real Mac IOSurfaces and production
Metal factories/emitters; kernel transport is mocked. The new indexed test
covers u16/u32 reordered indices, all overloads, commit snapshots, rebinding,
shared/private reads, bounds, alias, allocation and fence failures. All ten blur
profiles pass descriptor tests and ASan/UBSan. The Cortex-A53/iOS provider builds.

The exact58 typed constants load the phone's actual2448-byte stage through the
production library/function/pipeline factory and C emitter. Copy and source-over
each pass34 grouped descriptor checks; four mock native submissions cover two
successes and two injected terminal-fence failures. Five malformed IO metadata
mutations reject. The actual4672-byte textured fetch/noise stage still passes29
checks for each blend mode and rejects malformed sampler/tag metadata.

## Device pixel oracles

The candidate adds genuine reordered u16/u32 blur draws using the existing
independently verified blur8 reference. The exact2448-byte phone stage is also
retranslated byte-identically from its captured AIR specialization. Its
optimized NIR computes a3x4 FP16 matrix over fetched color and preserves alpha.
A0/1 coefficient matrix swaps red/blue in a nonzero destination. Full-target and
same-job overlapping draws distinguish one swap from two ordered swaps. Expected
pixels are derived independently; they are not prewritten into GPU output.

The old31 cases remain byte-identical. Their four existing failures remain open;
this work does not claim complete compositor support or a working home screen.
New pixel execution and backboardd progression require the next phone capture.

## Image and installation

The signed provider and actual19-file kernel payload preflight pass (40,578,576 raw /9,815,469 packed bytes). Full XNU compile/link/dSYM/symset passes. BOOT is31,524,880 bytes, below32MiB; its loader and ADT are byte-identical to0208 (which preserves the proven0207d loader). The exact new compressed provider and all four new case names occur in the linked kernel. An initial packaging attempt placed generated data in the harness include; the compile rejected this before any device write. The original source-only harness was restored from0175/0176/0180 and the35 cases placed in its Data include before the successful build. Installation is recorded below. The proven
0207d strict-alignment loader, four-core configuration and existing storage/input
paths are preserved. Only BOOT p10 is explicitly written; the existing in-kernel
installer updates its exact embedded userland files. No whole root-image
transfer, BOOT backup or post-write readback/hash is performed.
