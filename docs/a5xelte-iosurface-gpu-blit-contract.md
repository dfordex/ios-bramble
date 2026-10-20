# A5XELTE IOSurface to Mali frame transfer

## Current boundary

`SweetFramebuffer.cpp` receives four layer IDs and source/destination rectangles
in `SwapEnd`. The vsync timer keeps the newest record and `AppleCLCD::present`
copies each enabled 32-bit IOSurface row to the loader's DECON buffer at
`0x67000000` (1080 × 1920, 4320 bytes per row). `SweetSurface.cpp` allocates
user-shared `IOBufferMemoryDescriptor` objects, which are not required to be
physically contiguous. The existing A5XELTE GPU driver has a one-job-at-a-time
private address space and finite polled fences. Its `a5gpu=6` test completed
two private 16 × 16 clears on hardware. The `a5gpu=7` texture fixture only
maps four private pages and tests a 16 × 16 RGBA8 texture source; it does not
accept an IOSurface or a live framebuffer rectangle. The phone log shows both
fences completed without MMU/GPU faults and all 256 destination pixels matched.

Copying an IOSurface pointer or its first physical segment into that fixture
would let the GPU read beyond mapped memory. Reusing a source or destination
before completion could corrupt a frame. The fixture is therefore not a
callable frame-transfer API, and the boot image must retain CPU presentation.

## Narrow API to implement after fixture validation

Keep the API private to the A5XELTE kernel sources, not an IOGPU or Metal
service. One candidate signature is:

```cpp
enum A5BlitResult { kA5BlitComplete, kA5BlitUnsupported,
    kA5BlitBusy, kA5BlitFault };

A5BlitResult a5g3d_copy_rect(
    IOMemoryDescriptor *source, uint64_t sourceOffset,
    uint32_t sourceStride, uint32_t sourceFormat,
    IOMemoryDescriptor *destination, uint64_t destinationOffset,
    uint32_t destinationStride, uint32_t width, uint32_t height);
```

The caller must retain both descriptors until a successful completion fence.
For the first implementation, make the call synchronous, allow one rectangle
at a time, cap dimensions and total pages, and return `Unsupported` on every
unknown format, alignment, overlap, or geometry. `AppleCLCD::present` should
use the GPU only under a separate opt-in boot argument and fall back to its
existing CPU copy on `Unsupported` or `Busy`. If a submitted job times out or
faults, keep its pages pinned and disable later GPU jobs for that boot; a CPU
copy is safe only after confirming that no GPU write to the destination can
still be in flight.

## Required implementation steps

1. Preserve the phone-verified 0135 tiler then fragment result: no MMU/job
   faults, completed fences, and all 256 destination pixels equal the source.
   Keep this proof separate from the older two-clear result.
2. Add descriptor page walking with `getPhysicalSegment` across the *entire*
   source and destination ranges. Reject holes, short segments, address
   overflow and physical addresses outside the GPU's supported width. Build
   bounded Mali-LPAE mappings for every page, never an identity mapping of
   all RAM. The DECON physical buffer needs its own bounded mapping.
3. Validate `sourceOffset + (height - 1) * sourceStride + width * 4` and the
   corresponding destination end against each descriptor's length before
   submitting. Verify BGRA/RGBA channel order with a four-color fixture,
   including nonzero source/destination offsets and 4320-byte destination
   stride. A 16 × 16 red square alone does not prove channel order or stride.
4. Replace fixed 16 × 16 tiler, texture, and framebuffer descriptors with
   checked dimensions and bounded tiles. Test an odd-width rectangle, partial
   right/bottom edge, and a full panel-width row. Avoid one giant allocation
   when the page-table or job limits are unknown.
5. Flush CPU-written source pixels and descriptors before JS1/JS0 starts;
   invalidate GPU-written destination data before CPU inspection. Keep the
   AS0 mapping, descriptors, surface retains, and destination alive through
   both fences. Serialize submitters with a lock; preserve the existing
   sticky halted state on ambiguous completion.
6. Enable the display call site only after a GPU copy of a retained IOSurface
   into a private destination passes an exact pixel comparison, then a
   small clipped rectangle to DECON passes visual inspection. The next boot
   can opt in to general rectangles while keeping CPU fallback. Measure
   swap rate, shown rate, copy latency and dropped frames using 0136 counters.

This path can offload the final pixel transfer. It cannot make CoreAnimation
or SpringBoard render through Mali. That requires an iOS-visible graphics
service, command-buffer/texture ABI, shader translation and synchronisation;
the service-discovery work in 0137 is diagnostic only.
