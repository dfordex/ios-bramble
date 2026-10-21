# GPU mipmap support: verified gaps

This is a source audit of the 0163 kernel and the following userland work.
It does not add mipmap generation or establish a GPU pixel result.

## What the existing path actually supports

- `A5MaliMetalAPI.m`, `newTextureWithDescriptor:`, allocates only shared,
  single-level BGRA8 2D textures. Its IOSurface row size is exactly `width * 4`.
  The IOSurface import overload rejects a different stride. The size/alignment
  helper in `A5MaliMetalDeviceResources.m` has the same private/mip exclusions.
- Kernel operation 3 is named `DrawTexturedQuadBGRA`, with a misleading
  "scaled rectangle" enum comment. `A5XELTEGPUAS1.cpp` routes operations 2 and 3
  to the same `a5_midgard_encode_copy()` in
  `userland/a5xelte-gpu-translation/midgard_encode.c`. That encoder explicitly
  rejects unequal source/destination rectangle widths or heights. Current
  operation 3 therefore cannot downsample.
- The copy shader is a real Mesa-generated T720 fragment shader. Its generator,
  `tools/a5xelte-gpu/gen-t720-copy-shader.c`, uses `nir_texop_txl` with
  interpolated texture coordinates. Source coordinates and destination
  positions already occupy separate descriptor arrays. This provides a
  plausible fixed-shader basis for a filtered resize without a general Metal
  shader compiler, but the resize has not been implemented or measured.
- Its sampler is nearest, not a downsample filter:
  `gen-t720-texture-fixture.c` sets both `minify_nearest` and `magnify_nearest`
  true. `t720_fixture_words.inc` stores that sampler at `0x780` with word `3`.
  Mesa's local Midgard v4 schema identifies those as bits 1 and 0. Clearing
  them selects linear filtering; that descriptor change still needs a real
  hardware pixel test.
- Kernel operation 4, `ReadSurfBGRA`, is an exact 1080x1920, stride-4320 fixture.
  It cannot serve arbitrary mip dimensions.
- The descriptor encoder requires GPU addresses aligned to 4 KiB, dimensions
  1..2048, and rows aligned to 16 bytes. The AS1 IOSurface mapper permits only
  offset-zero BGRA surfaces, backed by retained IOBufferMemoryDescriptors, up
  to an 8 MiB mapping. A mip chain packed at arbitrary byte offsets is not
  accepted by this ABI.
- The user client can retain 32 imported resources, but AS1 maps only four
  surfaces simultaneously. Ten retained mip levels are not the same as ten
  simultaneous mappings. A sequential implementation can map only the source
  and destination level, complete the GPU fence, then unmap them. Existing
  batch capacity is eight commands, so a nine-step chain also needs ordered
  batch splitting or an explicit bounded mip-chain kernel operation.

## The observed warmup request

The requested private 776x24 2D texture has ten levels. The current factory
rejects it. Handling `generateMipmapsForTexture:` with a command-buffer error
removes the missing-selector exception without claiming successful mip work.
The inspected warmup does not commit this command buffer. This observation
does not justify completing a committed mip request without GPU work.

For a BGRA8 implementation, the logical level sizes and minimum 16-byte rows
would be:

| Level | Size | Aligned row bytes |
| --- | --- | --- |
| 0 | 776x24 | 3104 |
| 1 | 388x12 | 1552 |
| 2 | 194x6 | 784 |
| 3 | 97x3 | 400 |
| 4 | 48x1 | 192 |
| 5 | 24x1 | 96 |
| 6 | 12x1 | 48 |
| 7 | 6x1 | 32 |
| 8 | 3x1 | 16 |
| 9 | 1x1 | 16 |

Exact `width * 4` rows fail the encoder at levels 2, 3, 7, 8 and 9.
The request's actual pixel format must also be accepted deliberately; the
existing BGRA-only path cannot support other formats by relabelling them.

## Minimum route to real GPU generation

1. Add an explicitly bounded filtered-resize operation. Preserve operation 2's
   equal-size copy contract. Validate source/destination bounds and distinct
   pinned backing, use the existing fixed sample shader, select linear
   filtering, and encode independent source coordinates and target positions.
   Validate texel-center behavior, clipping, framebuffer bounds, and very small
   targets; merely deleting the size check is insufficient.
2. Allocate and retain real per-level storage, including aligned rows, level
   dimensions, logical storage mode, and lifetime. Separate internal surfaces
   per level can reuse the existing offset-zero import ABI; one packed
   allocation instead requires explicit subresource offsets and corresponding
   kernel bounds checks. Private textures must not expose a shared IOSurface
   through the public texture API while claiming private semantics.
3. Encode each level from the previous level, retaining all levels through
   execution. Map a bounded source/destination pair, perform existing cache
   maintenance, submit JS1 tiler then JS0 fragment, require terminal fences,
   and only then advance/unmap. Preserve current timeout poisoning and pinned
   backing behavior. Report command-buffer completion only after all levels
   complete successfully.
4. Add explicit level selection to texture-copy/view and resource-query
   selectors used by QuartzCore. A metadata-only `mipmapLevelCount = 10` does
   not make those levels accessible or correct.

No general shader compiler is required for this narrow fixed-format resize
primitive if its current sampling shader is confirmed suitable. General
QuartzCore rendering and arbitrary Metal pipelines remain separate work.

## Required device proof

Use a nonuniform pattern whose filtered values differ from nearest selection.
Verify actual GPU-produced bytes for even and odd dimensions, a 1-pixel axis,
and final 1x1 output against a defined filtered reference with an explicit
rounding tolerance. Check padding canaries and neighboring allocations, then
verify every level of the real ten-level chain. A terminal fence alone,
zero-initialized textures, or an uncommitted warmup buffer proves no mip pixel
correctness. Check the completed command-buffer status and all existing cache,
resource-retention, and fence rules during this test.
