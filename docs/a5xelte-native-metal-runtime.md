# Native Metal function and resource connection

## Scope

The 0175 suite established GPU pixel correctness for 21 bounded jobs. It did not
use the stock Metal render encoder. This change connects authenticated function
lookup and descriptor selection to actual application resource bindings and a
native T720 queue. Device execution of this new route remains to be measured.

## Implemented path

1. A private build-time registry authenticates the original QuartzCore metallib,
   translated vertex/fragment bytes, formats, resource slots, native bindings,
   push offsets, vertex layout and supported specialization state. Shader bytes
   and generated includes stay outside Git.
2. Function lookup returns only registered real programs from the pinned library.
   Pipeline selection checks both genuine functions, all eight attachment slots,
   blend/depth/sample state and the actual vertex layout. Native Apple pipeline
   libraries and unknown constants remain unsupported.
3. Executable initial profiles are DS4 and nine downsample/blur attachment
   variants, IDs 99–108. The encoder captures actual buffer/range identities,
   texture slot 3, sampler slot 0, viewport/scissor and draw geometry. Shared
   buffer data is captured at commit; setBytes is copied at encoding. Private
   buffers retain real kernel handles and failed uploads cannot be drawn.
4. The runtime emitter uses released Mesa 26.2.4 v4 packing and the authenticated
   native code. It stages actual uniforms/vertices, derives target tile bounds
   from real dimensions and emits real vertex, tiler and fragment jobs. There
   is no fixture image, expected output or CPU pixel renderer in this path.
5. NativeQuery (17) returns kernel-selected addresses for retained per-client
   AS1 resources plus a mapping epoch. NativeSubmit (18) snapshots the encoded
   data, verifies the epoch and selected resource generations/permissions, owns
   the GPU queue through terminal fences and invalidates outputs before return.
   Faults/timeouts pin the AS1 context and potentially visible allocations.
6. Logical IOSurface handles are separate from the four physical AS1 windows.
   A query protects its selected resources while recycling idle windows; any
   mapping change invalidates earlier address tickets. This removes the former
   failure on allocation of the fifth live texture, within the existing bound
   of 32 retained handles and four simultaneously mapped surfaces.

## Exact bounds

- The shader viewport lowering is currently fixed at (0,0,1080,1920,0,1).
  Other viewports are rejected, not approximated. Actual target dimensions,
  scissors and source dimensions may vary within mapped bounds.
- Zero base vertex; 3–256 vertices; triangles or triangle strip; one instance.
- BGRA8 copy and premultiplied source-over use the released blend equation.
  RGBA16Float uses native raw half packing; fixed-function blending of that
  packed export is rejected.
- Descriptor/code/scratch allocation is 256 KiB. TLS assumes the verified
  T720 shader-present mask 3 and checks the core-ID range before submission.
- BGRA8 and RGBA16Float IOSurface imports are checked by actual element size,
  FourCC, row pitch, allocation size and single-plane geometry. Existing typed
  BGRA operations still reject half-format surfaces.

The native interface is an explicitly privileged lab interface enabled only by
`a5native=1` on the existing entitlement-gated connection. Unlike the earlier
four typed operations, it accepts native shader/descriptor data from this
provider. It is not an interface for untrusted shader clients or a production
security boundary. Physical addresses, page tables and MMIO are never accepted.

## Remaining compositor coverage

Compiled function/format metadata for misc and original path pipelines is
separate from executable runtime admission. Their multi-target, storage-buffer,
instancing and ordered framebuffer-read semantics need actual pass encoders and
resource lifetimes. Original path-blit is not replaced with a texture fixture.
Unsupported paths return errors; metadata or function creation must never count
as GPU drawing. Consequently this change alone cannot promise that backboardd
will stop aborting at the next unsupported compositor pipeline.

## Verification

- 0175 hardware results: [shader suite results](a5xelte-shader-suite-results.md).
- Real-registry host tests cover source identity, native-code tampering,
  function/device ownership, exact formats/layouts and negative descriptors.
- Runtime packing tests use actual compiled code and the previous device-passed
  blur payload to compare real resource bytes and descriptor contracts; they
  also exercise changed dimensions, offsets, blend and rejected inputs.
- Native bridge tests check exact wire sizes, selected token replies, terminal
  fence handling and rejected input sizes/capabilities. These are transport
  tests, not hardware execution.
- iOS arm64 Cortex-A53 builds are distinct from the next device result.
