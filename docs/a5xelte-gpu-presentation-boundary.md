# A5XELTE GPU-to-display boundary

Status: source inspection on 2026-10-20. This is a design boundary, not a
claim that iOS frames are drawn by Mali.

Patch 0144 now stages an opt-in full-panel texture copy, conditional on a
successful 256-pixel live IOSurface sample from patch 0140. That sample
validates the fixed texture descriptor and shader; patch 0143 independently
validates the geometry and physical page map of every later swap buffer. It has passed
patch application checks only; no full-frame Mali job or frame quality has
been verified on the phone. The iOS producer's actual surface row stride is
4352 bytes (8,355,840 bytes total), while DECON's destination is 4320 bytes
per row (8,294,400 bytes total). Patch 0143 maps those as separate fixed
resources. `a5fb_gpu=1` selects the exact one-layer, full-screen path; all
other swaps retain CPU copying. An uncertain fragment fence freezes panel
updates because direct DECON DMA might still be active.

## Current scanout path

`AppleCLCD::present()` reads each enabled `SweetSurface` by IOSurface ID and
copies its clipped BGRA rectangle, one row at a time, into the loader's
continuous-splash buffer. The panel's DECON controller scans out that buffer
at physical address `0x67000000`, 1080 × 1920 pixels with a 4320-byte row
stride. One full frame is 8,294,400 bytes. The 60 Hz timer sends vsync
notifications, while `a5fb_hz` caps copies to the panel buffer at 30 Hz by
default. `SwapEnd` only records the latest frame; it does not run a GPU job.

The measured 0124 full-frame CPU copies usually took about 5–6 ms, whereas
only 23 frames reached `present()` in 63.857 seconds. The 0137 trace had 19
`SwapEnd` records over 771 seconds. These observations make the frame producer
and graphics service path the first bottleneck to investigate. Replacing the
final CPU copy alone cannot turn a sparse stream of frames into a fluid UI.
The recovered 0139 log has 154 measurement windows spanning 818.9 seconds:
12 swaps and nine presentations. One 8.29 MiB presentation took 5.267 ms.
This capture again shows low upstream frame production, not a 30 Hz copy cap.

## What the current Mali work proves

Patch 0138 owns a pinned private backing and a serialized one-job Mali queue.
Its GPU-visible AS0 window is 16 KiB. Patch 0139 stages a 16 × 16 tile from a
retained IOSurface through a CPU copy into that backing, then uses the existing
private texture fixture. Even a successful pixel match means only that the GPU
can sample those 256 pixels. Neither patch maps the live IOSurface or DECON
scanout buffer into Mali, describes a full-screen blit, or exposes the
`IOGPU`/`IOAccelerator`/Metal contract used by iOS.

The earlier opt-in patch 0133 did map 16 physical DECON pages and render a
green 16 × 16 square directly into active scanout. The user saw the square,
and the device log had job completion without Mali MMU faults. That proves a
small direct write to the display, not a complete frame, an ongoing present
queue, or source IOSurface sampling in the same job.

## Conditions for a useful GPU presentation path

1. Determine which side is slow with the bounded `A5XELTE FB:` counters:
   `swap_hz`, `shown`, `avg_copy_us`, `avg_wait_us`, and IOSurface activity.
   Compare an interactive, steady workload rather than an idle boot interval.
2. Extend the Mali page-table and resource owner to cover complete pinned
   source and destination surfaces, including noncontiguous pages, row stride,
   clipping, and cache ownership. A 16 KiB fixture cannot address an 8.3 MiB
   frame. Do not let a GPU job outlive an IOSurface or free backing after an
   ambiguous timeout.
3. Build a real bounded Mali blit job for BGRA rectangles and validate pixel
   equivalence, completion fences, and fault reporting on the phone. Compare
   end-to-end latency with the current CPU copy, including staging and cache
   operations. Keep the CPU path for unsupported formats and errors.
4. Establish scanout ownership before GPU writes to the physical DECON buffer.
   The continuous-splash setup has no page-flip or double-buffer handshake in
   the current bridge; writing while DECON reads can tear. A fence must precede
   visible reuse of a destination buffer.

Even after such a blit, iOS application rendering stays on the CPU until a
Mali-backed graphics stack satisfies the userland device, resource, command
queue and synchronization interfaces. A service-name match or a private GPU
pixel test does not establish that SpringBoard submits drawing work to Mali.
