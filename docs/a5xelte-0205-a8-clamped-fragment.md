# 0205: A8 alpha texture and the captured coord5/image17 fragment

## Device evidence and scope

The complete [0204 recovery](a5xelte-0204-long-log-review.md) records an A8Unorm
texture rejection followed by backboardd's fragment-specialization abort. Its
first complete 58-constant capture differs from603 only in
`fc_coord_function0=5` and `fc_image_function0=17`. This build implements that
actual specialization as606, together with its newly live uniform buffer and
alpha-only texture. It preserves the physically verified0204 storage path.

PosterBoard's separate first-time switcher-state assertion is not repaired by
this shader. Other uncaptured functions and unsupported render states still
fail explicitly. This is not a claim that every iOS graphics path is complete.

## Real shader and resource contract

- The pinned stock AIR translates through SPIR-V validation and release Mesa
  26.2.4 Midgard compilation.606 uses the existing2192-byte vertex and its own
  896-byte fragment, five registers, no TLS/WLS. Four admitted normalized
  sampler combinations produce identical native code.
- FragmentBuffer1 is now live: float4 at byte112 contains UV minXY/maxXY.
  The renderer retains at least128 bytes, binds native UBO3 and snapshots late
  writes at commit. Missing/short data is rejected before GPU submission.
  FragmentBuffer2, Texture3 and Sampler0 retain their distinct bindings.
- The fragment clamps UV using that float4 and replicates sampled alpha into
  RGBA. Its exact typed constants, reflection, native code and push layout are
  validated through specialization, pipeline admission, registry and cache.
- A8Unorm keeps its alpha identity throughout allocation, linear buffer views,
  IOSurface import, raw-byte copies and GPU sampling. Its private import tag is
  A008, distinct from R8. T720 uses R8 storage with000R sampling swizzle,
  matching the pinned released Panfrost format table. The rejected576x301,
  row576, offset64 layout is covered by bounds tests.
- Kernel patches0199/0200 add A8 import,606 queue admission and the exact
  generic606 recipe installer path. No global resource validation is relaxed.

## Automatic compiler

The signed phone package contains602–606 recipes and a rebuilt combined
Midgard backend whose module whitelist actually includes606. Packaging checks
the backend/source/module provenance rather than accepting an older binary
with a newer JSON recipe. A complete606 pair can retire its matching old
root-private unsupported status and compile automatically; unrelated statuses
and unknown requests remain terminal. Standalone unknown functions are not
silently substituted. Final cache receipts validate602–606 independently.

## Local verification

- Full native transport suite passes, including earlier profiles and nine606
  cases: copy/blend entry points, commit-time B1 capture, missing/127-byte B1,
  query/bulk/submit failures, cleanup and terminal fences. iOS Cortex-A53 API
  and provider compilation and4KiB signature checks pass.
- Actual AIR to SPIR-V to combined Midgard to cache publication passes for606.
  Status ownership/mode/link/identity and cache corruption negatives pass.
  All256 alpha values and actual kernel import bounds pass host tests;
  extracted kernel helpers use ASan/UBSan.
- Preserve23 existing physical GPU test inputs byte-identically. Append two
  independently calculated full4096-byte oracles for asymmetrical A8 sampling
  with nontrivial UV limits and source-over blending. Their emitted descriptors
  reference the real128-byte B1. Output starts poisoned/nonzero, not CPU drawn.
  Total25 cases are embedded; execution of the two new cases is pending device.
- Exact0200 patch reproduction matches staged sources;0199 applies without
  fuzz. Repository validation passes200 contiguous patches and tool syntax.
- Final19-file installer payload passes the actual kernel preflight:
  39,575,488 raw bytes,9,459,982 packed bytes. Full XNU build passes.
  BOOT0205 is30,375,952 bytes, within33,554,432-byte p10. Four tested CPUs,
  input, logging, negative-Y viewport and32-sector storage batching remain.

The next recovered device log must establish25/25 pixels, real606/A8 pipeline
acceptance, successful GPU jobs and any remaining backboardd failure. Visible
home-screen progress requires physical observation.

## Installation

Source `c49357f` was pushed before flashing. Exact recovery, model, TWRP,
BOOT p10 mapping and33,554,432-byte capacity checks passed. Direct streaming
acknowledged30,375,952 bytes, sync completed and reboot was requested. No
BOOT backup, post-write hash/readback, formatting or whole USERDATA transfer
was performed. Runtime results remain pending the next recovered capture.
