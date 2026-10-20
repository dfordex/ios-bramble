# A5XELTE Mali full-frame map (0143)

Patch 0143 provides a fixed kernel-only Mali AS0 resource map for one
1080 × 1920, 32-bit BGRA IOSurface with 4352-byte source stride and the
existing DECON physical panel buffer with 4320-byte stride. It does not
connect iOS CoreAnimation, Metal, or IOSurface swaps to GPU rendering.

## Layout

| Mali VA | Region | Size | Page tables |
| --- | --- | ---: | --- |
| `0x02000000` | Existing descriptor/16 × 16 fixture | 16 KiB | Existing L3 at private backing `+0x3000` |
| `0x04000000` | Retained BGRA source IOSurface, stride 4352 | 8,355,840 bytes, 2040 pages | Four L3 pages at private backing `+0x8000` |
| `0x05000000` | Fixed panel physical buffer `0x67000000`, stride 4320 | 8,294,400 bytes, 2025 pages | Four L3 pages at private backing `+0xc000` |

The page tables fit inside the existing physically contiguous 64 KiB driver
backing. The source must have exact width, height, stride, pixel format,
offset, allocation length, and page-aligned physical segments. The mapper
retains its `SweetSurface` and stores its CPU cache before GPU access. It
never accepts user-supplied physical addresses, Mali VAs, or page entries.

`a5g3d_frame_map_begin` reserves the one-job queue and holds the composite
fixture lock. A caller can submit a job with the returned token, call
`a5g3d_frame_map_reacquire` after a verified completion fence, and finally
call `a5g3d_frame_map_end`. The mapper stores the page tables and performs
Panfrost-style AS0 LOCK / FLUSH_PT under the queue reservation. If this
becomes uncertain after page-table mutation, the queue is poisoned and both
the old and new source are retained until reboot.

The caller must present the surface after its producer writes are complete
and keep the pixels unchanged through the final GPU fence. The mapper only
stores CPU caches; it does not implement an IOSurface producer fence. Current
SweetFramebuffer receives a retained surface ID but no producer-completion
fence, so this path is experimental and can show a stale or torn frame.

## Remaining proof

- Static checks: patch application, repository validation, and XNU build.
- Hardware: AS0 page-table flush and bounded full-frame source reads.
- Presentation: validated T720 tiler/fragment descriptors and GPU-to-panel
  fence followed by a visible frame. The current 16 × 16 shader fixture
  does not draw a full frame by itself.
- iOS acceleration: an authenticated resource/command ABI and compositor
  integration remain separate. A successful kernel framebuffer copy does not
  imply CoreAnimation or Metal rendering has moved to Mali.
