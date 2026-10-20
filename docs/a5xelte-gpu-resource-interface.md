# A5XELTE Mali resource import boundary

## Implemented private kernel API

Patch 0139 adds `A5XELTEGPUResources.{h,cpp}`. An imported resource retains the
actual `SweetSurface` object either from its Mach port in the caller's task or
from an ID used inside the kernel. It accepts only one-plane 32-bit BGRA with
ordinary one-pixel elements. A 16 × 16 tile is copied, row by row, from the
surface's `IOMemoryDescriptor` into the queue's pinned private backing. The
source and destination extent checks use 64-bit arithmetic, check the full
last row and reject a surface whose declared allocation exceeds its memory
descriptor. The staging buffer is cache-stored before the GPU can read it.

With `a5gpu=8`, one first-swap diagnostic retains a real IOSurface, snapshots
its center tile, and submits the existing tiler then fragment texture fixture
through the private queue. The source surface stays retained through both
fences. The code compares all 256 GPU output words with the captured input
words and records `A5G3DLiveSurfaceResult` in the registry and persistent
log. The regular framebuffer still presents through the CPU; the probe stops
after its first supported surface.

The private backing stays owned by the queue through its completion fence. On
a timeout or an ambiguous job, it remains pinned for the rest of that boot.
The GPU sees only the queue-owned backing and its bounded AS0 mapping. This is
a copy-based import; the IOSurface's potentially noncontiguous physical pages
are never placed into Mali page tables or represented by an unchecked GPU
virtual address. The mode 8 live swap test has compiled, but phone output is
still needed to establish its result.

## Versioned user-client contract to implement next

This document reserves a private `A5XELTEGPUResourceUserClient` protocol for a
future Mali-compatible iOS backend. It is **not registered** by 0139, and no
`IOGPU`, `IOAccelerator`, or Metal service is advertised. Protocol version 1
would use fixed-size little-endian requests with a `version`, `size`, and
reserved-zero header. A client would open a per-task connection and receive
opaque generation-checked handles. It would never submit a raw Mali job,
page-table entry, physical address, or GPU virtual address.

| Selector | Request | Result | Failure rule |
| --- | --- | --- | --- |
| 0 Query | version and struct size | capabilities and hard limits | Unknown version returns `kIOReturnUnsupported` |
| 1 ImportSurface | IOSurface Mach port in this task, usage bits | retained resource handle | Invalid right, format or extent is rejected |
| 2 AllocatePrivate | byte length and usage | owned private handle | Exceeds per-client count or byte budget is rejected |
| 3 Release | handle | status | Busy resources remain retained until their fence |
| 4 SubmitTile | source handle, clipped rect, destination handle | monotonic fence | Only kernel-built operations are accepted; no generic shaders |
| 5 WaitFence | fence and finite timeout | terminal status | Timeout halts the queue and pins GPU-visible pages |

The first implementation should limit a client to 32 resources, 64 KiB of
private GPU-visible backing and one in-flight job. Handle slots need a
generation counter so a released handle cannot name a later allocation.
Imports must use a Mach send right in the opening task, not a globally
guessable IOSurface ID. Every size, offset, stride, format, alignment, and
array count must be validated before touching hardware. Connection close
releases idle resources; busy resources wait for a terminal fence. The GPU
service must have an explicit entitlement policy before exposing selectors
to arbitrary apps.

This protocol is not the ABI that the staged Apple `AGXMetalA11` binary uses.
SpringBoard cannot use it by itself. A Mali-compatible userland implementation
of Metal/IOGPU and the actual iOS ABI remains necessary before iOS system
composition can run on this GPU. An accelerated final pixel copy would be a
separate, narrower milestone.
