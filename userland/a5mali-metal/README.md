# Private iOS Mali command bridge

This source connects an iOS process to the opt-in `A5XELTEGPU` user client
introduced in XNU patches 0148–0154. It opens the IOKit service, checks ABI
version and supported commands, imports a BGRA IOSurface with a Mach send
right, maps it into the client's private Mali address space, and submits
typed BGRA8 clear/copy/scaled textured-quad requests through selector 6. When
the kernel advertises selector 7, the Objective-C command queue submits up to
eight of those same typed operations in one synchronous ordered batch. Each
item has its own terminal status and fence; submission stops at the first
failure. This batch is not a general Metal render command queue. The
quad operation is sent only when the kernel query advertises its capability.
It is one bounded, nearest-sampled rectangle operation, not general raster
drawing. The Objective-C
`A5MaliCommandBuffer` records up to 64 commands and submits them in order;
`commitAndWait:` returns only after each kernel job's completion. It reports
failures rather than silently falling back to CPU drawing.

The opening **process** needs the true entitlement
`com.orhunnx.a5xelte.gpu-resource-client`; signing this dylib does not grant
that entitlement to a process. The kernel service also requires the opt-in
`a5gpu=8 a5gpuclient=1` boot arguments. No user process or phone has run this
bridge yet. The standalone local build is:

```sh
./build.sh
```

The script cross-links an arm64 iOS 16-targeted dylib, ad-hoc signs and
verifies that local dylib, and runs C and Objective-C host-side mock tests
covering the exact input/output structure sizes, selector order, clear/copy/quad
fences, eight-command batch submission, rejected rectangles and unsupported
quad capability, failed jobs, and malformed replies. It does **not**
install the dylib or modify an iOS root image.

`A5MaliRestrictedDevice` proves that the staged `_MTLDevice` superclass can
be linked and that an exact `A5XELTEGPU` service can be passed into the private
bridge. It has no bundle manifest, no `MTLDevice` or `MTLDeviceSPI` conformance,
and exposes only the private bounded commands. It cannot enter stock Metal
discovery. `A5MaliCommandBuffer` does not claim `MTLCommandBuffer` conformance.

The local `A5MaliMetalAPI` adapter exercises a real public-selector copy
sequence: a queue creates a command buffer, a blit encoder records one or more
2D BGRA8 texture copies, and `commit` sends those copies through the 0153
kernel batch interface and waits for terminal fences. The completion status,
error and callbacks reflect that submission. An IOSurface texture import
accepts only one BGRA8 plane, one mip level, shared storage, and matching
dimensions. A host smoke program invokes the public Metal call sequence with
an injected device and synthetic resource fixture; unsupported slice/level
geometry becomes a command-buffer error without submitting a GPU job.
The adapter does not conform to `MTLCommandQueue`, `MTLCommandBuffer`,
`MTLBlitCommandEncoder`, or `MTLTexture`: their remaining required selectors
and semantics are absent. In particular it has no stock render pipeline,
shader library, general allocation, asynchronous queue, or presentation path.
`read_surf` pipeline descriptor validation recognizes one candidate shape but
still returns an unsupported error, because a function name alone does not
prove the compiled shader identity or a working render submission path.
The private candidate can be bound to a narrow render encoder for local ABI
tests. It accepts one BGRA8 1080×1920 source and target at stride 4320, a
full viewport, one triangle draw, no blend/depth, and only when Query
advertises operation 4 via capability bit 4. It records operation 4 through
the existing selector 6/7 layout. The public pipeline factory remains
unsupported, so stock iOS cannot enter this encoder. The host test injects
bit 4; it is not a Mali hardware result. Patch 0154 exposes that bit only
when a local Midgard shader fixture is present at kernel build time. Its
absence leaves this render encoder unavailable.

Stock iOS Metal matches a genuine `IOAcceleratorES` service, reads
`MetalPluginName` and optional `MetalPluginClassName`, loads its bundle from
`/System/Library/Extensions`, and requires an `_MTLDevice` subclass. Its
`_MTLAddDevice` path checks both `MTLDevice` and private `MTLDeviceSPI`, then
calls `initLimits` and `initFeatureQueries`. The staged iOS 16.7.16 private
protocol declares 407 instance selectors; `_MTLDevice` does not itself provide
all required resource allocation and capability methods. This bridge lacks
Metal shader/AIR compilation, render and compute pipelines, buffers,
samplers, texture state, resource hazards, and asynchronous command-buffer
retirement. Making it discoverable as a Metal device now would cause clients
to select a renderer that cannot execute their drawing commands. The BOOT
flash gate remains closed until a real provider, translation path, and
general queue are integrated.

The staged QuartzCore `read_surf_vert`/`read_surf_frag` pair translates to a
fragment Texture0 read and a BGRA color attachment, but its out-of-bounds
alpha specialization and sRGB variants still require semantic validation.
Neither the translation metadata nor the typed quad operation proves that a
stock iOS render command has reached Mali.
