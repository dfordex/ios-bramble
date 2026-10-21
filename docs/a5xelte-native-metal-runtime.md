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
3. Executable profiles include DS4/blur 99–108, misc 200/202/204/206/207
   and rect/cubic/stroke 300–302. The complete registry has 22 logical profiles,
   including metadata-only original paths; 22 native passes are executable
   and four original path metadata passes remain gated. Shared buffer bytes are captured at commit, while setBytes is copied
   at encoding. Large storage buffers use real kernel allocations and bounded
   bulk uploads rather than truncation to the descriptor arena.
   Private buffers retain real handles; failed uploads cannot be drawn.
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

## Formats, layouts and exact bounds

- Linear Metal formats 80 BGRA8, 10 R8, 30 RG8, 55 R32Float and 115
  RGBA16Float use their actual FourCC, element size, row pitch and allocation
  bounds. Shared external imports preserve shared storage. One-level private
  textures own real IOSurface backing, expose Private storage and hide the
  IOSurface from the public Metal API. There is no fake mip chain.
- Blur and path vertex programs load actual viewport scale/offset from UBO0
  offsets 512/528; offscreen viewport state is not replaced with 1080×1920.
- Blur geometry supports zero base vertex, 3–256 vertices, triangles or triangle
  strip and one instance. VertexID/InstanceID misc and path contracts currently
  support one four-vertex quad. Indexed or general instanced geometry is not
  implemented.
- Misc MRT outputs are real ordered native passes retaining their actual
  targets. Home uses two actual source textures with the AIR constexpr sampler
  state. Rect/cubic write only RT2 R32Float with additive destination loads;
  stroke writes only RT0 RGBA16Float with inline premultiplied source-over.
  These masks follow QuartzCore pipeline construction, not just AIR exports.
- BGRA blur copy/source-over use the released blend equation. RAW64 blur
  RGBA16Float permits copying; blending its packed export remains rejected.
- GPU clear submits a real fragment job for each supported format; its clear
  packing is compared against the unmodified released Mesa pan_clear.c.
- Descriptor/code/scratch storage is 256 KiB; four buffer windows support up
  to 8 MiB each with transfers of at most 1 MiB. Logical IOSurface handles
  remain bounded at 32, with four simultaneously mapped 32 MiB surface windows
  so full-screen RGBA16Float targets fit.
- Native jobs have a nominal two-second poll delay budget plus MMIO overhead;
  existing typed jobs retain their previous budget. Faults terminate polling
  immediately and uncertain DMA backing stays pinned until reboot.
- TLS assumes the verified T720 shader-present mask 3 and checks core-ID bounds.

The native interface is an explicitly privileged lab interface enabled only by
`a5native=1` on the existing entitlement-gated connection. Unlike the earlier
four typed operations, it accepts native shader/descriptor data from this
provider. It is not an interface for untrusted shader clients or a production
security boundary. Physical addresses, page tables and MMIO are never accepted.

## Remaining compositor coverage

Original path-blit needs ordered framebuffer read/clear of RT2 together with
color outputs. It remains explicitly nonexecutable: an immutable texture replay
cannot preserve that ordering. Constant-specialized generic programs, mip chains,
memoryless attachments and general indexed/instanced geometry are also outside
this implementation. Unsupported paths return errors. Function discovery or
successful pipeline creation alone never counts as GPU drawing or proof that
backboardd is stable.

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

The new dynamic viewport and inline path blend variants require device proof
separate from 0175. The next image includes GPU oracle cases with nonzero old
destination values so overwrite cannot accidentally pass as additive/source-over.
Host transport tests run the real registry and v4 emitters, mocking only IOKit;
real Mac IOSurface allocation tests and the iOS Cortex-A53 build are separate
checks from execution on the phone.
