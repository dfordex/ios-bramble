# iOS Metal backend boundary on Mali T720

This note records local inspection of the staged iOS 16.7.16 root and the
private XNU GPU work through patches 0142 and 0143. It does not include Apple
binaries, command streams, or IPSW content. A private GPU fixture and an iOS
Metal rendering path are separate milestones.

## Verified userland entry points

The dyld shared cache contains Metal, QuartzCore, IOGPU,
IOSurfaceAccelerator, and `AGXMetalA11`. The AGX bundle's `Info.plist` names
`AGXPrincipalDevice` as its principal class. Inspection of the extracted
binary in a local temporary directory finds
`-[AGXPrincipalDevice initWithAcceleratorPort:]` and
`-[AGXA11FamilyDevice initWithAcceleratorPort:simultaneousInstances:]`.
`AGXMetalA11` links to IOGPU, IOKit, IOSurface, and Metal. These are Apple
AGX-specific objects and are not a Midgard job encoder.

Metal exports `MTLCreateSystemDefaultDevice` and contains a bundle discovery
path under `/System/Library/Extensions`. It checks that a candidate device
conforms to the `MTLDevice` protocol. QuartzCore imports
`MTLCreateSystemDefaultDevice` and `IOSurfaceAcceleratorCreate`, and contains
references to `AGXAccelerator` and `IOAcceleratorES`. This gives a concrete
insertion point for a **new Mali Metal implementation**: an extension bundle
whose principal class implements the Metal device, command queue, resources,
pipelines and synchronization interfaces, backed by a matching kernel
userclient. Merely publishing an `IOAcceleratorES` registry name would select
an interface that the port cannot yet serve.

The inspected `IOSurfaceAcceleratorCreate` implementation looks for
`AppleM2ScalerCSCDriver` or `AppleSRSDriver`. It is a separate IOSurface
conversion path, not a replacement for a Metal rendering backend.

IOGPU exports device creation, command queue creation and submission, and
IOSurface resource creation routines. Its device-create path calls several
connection methods with nontrivial structures. Export names or selector
numbers alone do not establish the required request layouts, task lifetime,
memory mapping, completion or fault semantics. The existing AGX userland
binary cannot be pointed at a Mali service and expected to emit Midgard jobs.

## Current kernel capability

Patch 0142 adds a private bounded 16 by 16 BGRA tile transfer: kernel code
copies a retained IOSurface tile to queue-owned backing, submits known
Midgard tiler and fragment jobs, waits for fences, and compares 256 pixels.
Patch 0143 adds a private exact-frame mapping lease for the 1080 by 1920
BGRA source at 4352 bytes per row and the panel at 4320 bytes per row. It maps source and panel destination into Mali's
address space under a composite queue lock. There is no verified full-frame
job descriptor, user mapping protocol, or per-client resource/fence contract
yet. Neither patch accepts iOS Metal command buffers.

The current framebuffer path still uses CPU presentation. A GPU tile test,
GPU-written diagnostic square, or even a future GPU framebuffer copy does
not move SpringBoard's layer composition, shaders, text and icons to Mali.

## Minimum route to system composition

1. Prove a complete full-frame Midgard job from a retained IOSurface to the
   scanout buffer, including page lifetime, cache maintenance, fence status,
   teardown and error recovery. Compare output pixels and frame time on the
   phone. This is accelerated presentation only.
2. Define a versioned, bounded private userclient for **that tested set of
   operations**, with per-task ownership, validated IOSurface Mach rights,
   opaque resource handles, finite waits, and queue poisoning on ambiguous
   completion. Do not publish it while 0143 only provides a map lease.
3. Implement a Mali-compatible Metal userland backend that Metal can discover.
   Its `MTLDevice` must create functional queues, buffers, textures, samplers,
   render/compute pipelines and command buffers. Shader translation to
   Midgard, resource hazards, fences and error propagation need real support.
4. Observe QuartzCore/BackBoard/SpringBoard selecting that device, capture a
   frame produced by iOS rather than a kernel fixture, verify its pixels and
   scanout, then compare sustained frame rate and CPU time with the existing
   path. Keep CPU presentation as the fallback until this is repeatable.

The opt-in `a5metalprobe=1` and `sweetiolog=backboardd,SpringBoard` traces
from patches 0137 and 0141 can identify service matches and opens during this
work. They do not reveal the complete private method ABI or prove rendering.
No IOAccelerator/IOGPU alias or userclient is added by this note.
