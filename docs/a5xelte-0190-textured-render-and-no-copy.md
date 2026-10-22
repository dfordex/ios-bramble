# 0190: textured rendering, shared no-copy memory and request compilation

## Changes

The recovered 0189 fragment request changes six of 58 typed constants. Profile
603 now contains a separately compiled textured fragment and compatible vertex
variant, rather than reusing the untextured 602 shader. The native Midgard
emitter binds position/UV/color attributes, matrix and UV uniforms, fragment
LOD bias, actual Texture3 and Sampler0, and the color-write system value.
Indexed and nonindexed paths use the real resource query, submission and fence
interfaces. Exact resource, format, shader identity and render-state checks
remain enforced.

The fragment constants were captured on the phone. The compatible vertex
constants and BGRA8/copy pipeline contract are candidates whose actual pairing
must still be observed. An unrecognized live pairing will be rejected and
logged; host compilation alone does not establish live compositor acceptance.

The final fragment uses the ClampToEdge SPIR-V specialization. Native vertex
code is 2192 bytes and fragment code is 976 bytes. Runtime supports the checked
normalized clamp-to-edge nearest/linear sampler contract with a single source
level; the emitter supplies actual texture dimensions and level count.

`newBufferWithBytesNoCopy` now retains page-aligned Shared external memory
without an initial copy. `contents` is the caller's pointer, and commit-time
reads observe later caller writes. A copied deallocator block is called once,
outside locks, after the last retained buffer/binding/job reference. Invalid
creation does not take ownership. Unsupported storage modes and malformed
spans remain rejected.

The compiler service enters its serial request scan immediately. Baseline
selftests are an explicit mode, no longer a prerequisite for serving requests.
The package and authenticated cache support exact 602 and 603 recipes, with
real AIR-to-SPIR-V validation and released Mesa Midgard compilation. This is
coverage for these verified contracts, not a universal Metal compiler. Other
requests are retained with an explicit unsupported result.

Patch 0189 admits native profile 603 and the exact generic603 recipe path in
the existing pre-launchd installer. The binary identity/path and existing
payload limits remain unchanged.

## Local verification

- Full native Metal API harness passes, including old rendering families,
  indexed 602 and textured 603. The latter checks actual pinned code,
  subresource addresses/dimensions, sampler snapshots, late buffer/index
  writes, ownership, rejected states and terminal fence handling.
- No-copy and sampler ownership tests pass, including deallocator lifetime.
- Generated registry has 26 validated profiles. Constant, pipeline, cache
  corruption, filesystem trust and lifetime tests pass.
- Host request-to-cache tests for both 602 and 603 run the actual translators,
  validate native output and publish immutable cache entries successfully.
- Production Cortex-A53/iOS16 provider and tools build with warnings as errors;
  4 KiB code-signature page validation passes.
- Actual staged kernel installer preflight validates all 16 payload files and
  compressed streams: 39,423,840 raw / 9,417,453 packed bytes.
- Fresh XNU make completes successfully, including symbols. The packaged BOOT
  is 30,273,552 bytes, within the 33,554,432-byte BOOT partition capacity.

Host transport is mocked in API tests. These checks do not prove physical T720
pixels, stock compositor submission, on-phone cache publication or UI survival.
Existing 21 private GPU regression jobs remain in the image.

## Device trial

The image incrementally installs the provider, compiler and recipes before
launchd. It does not require retransferring the USERDATA root image.

Inspect installer completion/sync, the next actual shader and full-pipeline
specialization, no-copy allocation, backboardd crash reason, native Query17 /
Submit18 / fences, framebuffer swaps and actual displayed pixels. Separately
check compiler PUBLISHED and cache-bound markers. Device installation and
runtime results are recorded in A5XELTE_PROGRESS.md.
