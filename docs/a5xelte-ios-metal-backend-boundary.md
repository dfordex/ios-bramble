# iOS Metal backend boundary on Mali T720

This note records local inspection of the staged iOS 16.7.16 root and the
private XNU GPU work through patch 0149. It does not include Apple
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

Metal exports `MTLCreateSystemDefaultDevice` and `_MTLAddDevice`, and contains
a bundle discovery path under `/System/Library/Extensions`. Local binary
inspection indicates that candidate registration checks `MTLDevice` and
private `MTLDeviceSPI` conformance. This is a candidate insertion path; it
does not establish that an unsigned third-party bundle will load on the
phone. QuartzCore imports
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
Patch 0143 adds an exact-frame mapping lease for the 1080 by 1920 BGRA source
at 4352 bytes per row and the panel at 4320 bytes per row. Patches 0144 and
0146 add a private full-panel Mali copy for exact single-layer swaps and reset
the reused descriptor fixture before each live job. The 0146 device log
completed five full-frame tiler/fragment pairs without a recorded GPU fault;
unsupported frames can still use the CPU copy path. The current transfer-byte
counter includes both paths, so it does not establish their exact ratio. There
is no iOS Metal command-buffer parser or general command submission protocol.
Patches 0148–0149 add an opt-in, entitlement-gated private client with
versioned IOSurface import/release and one fixed 16 by 16 sampling operation.
The returned fences cover only that bounded fixture. The client is not an
IOGPU or IOAccelerator service, and it has not been tested on the phone.

This accelerates eligible final framebuffer transfers. SpringBoard's layer
composition, shaders, text and icons are still produced without a Mali Metal
backend. The user observed a normal home screen, with similar speed to the
previous build. The log covers a mostly unclassified 1,042-second interval;
its 12 swaps cannot establish interactive frame rate.

## Minimum route to system composition

1. Complete the full-frame Midgard path with producer-completion fencing,
   synchronized panel ownership, page lifetime, cache maintenance, teardown
   and fault recovery. Compare output pixels and frame time on the phone. The
   current fence covers Mali completion, not completion of the iOS producer.
2. Device-test the 0148–0149 private userclient, including entitlement
   acceptance, IOSurface ownership, pixel result, fault handling and bounded
   wait behavior. Extend it only for GPU operations that can be verified on
   hardware.
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
No IOAccelerator/IOGPU alias is added by these patches.
