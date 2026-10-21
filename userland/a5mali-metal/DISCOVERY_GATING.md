# Stock Metal discovery gate

`A5MaliDiscoveryAudit` is a read-only preflight for the iOS 16.7.16 provider
ABI. It does not register an accelerator or add `MTLDevice`/`MTLDeviceSPI`
protocol declarations.
The result mask reports missing runtime superclass, initializer, protocol and
minimum selector requirements. A zero mask would prove only those Objective-C
declarations exist, **not** that a draw can execute.

The staged Metal image follows this path:

1. `_MTLRegisterDevices` looks for a real `IOAcceleratorES` IOKit class.
   `A5XELTEGPU` does not inherit from that class. A property or service name
   cannot satisfy the kernel's `metaCast` class match. Patch 0156 supplies a
   separate proxy metaclass. Patch 0157 enables its compilation, while
   registration still requires the explicit boot opt-in.
2. It reads `MetalPluginName` and optional `MetalPluginClassName` from the
   matched service and loads a bundle in `/System/Library/Extensions`.
3. The principal class must descend from `_MTLDevice`, accept
   `initWithAcceleratorPort:`, conform to `MTLDevice` and private
   `MTLDeviceSPI`, and implement `initLimits`/`initFeatureQueries` plus real
   resource, pipeline, queue and encoder behavior.

Patch 0156 supplies a real `IOAcceleratorES` IOKit metaclass and a separate
`A5XELTEGPUAccelerator` proxy. The ordinary `A5XELTEGPU` service stays an
`IOService`, so a private queue does not become Metal-discoverable. The proxy
and its `MetalPluginName=A5MaliMetal` and
`MetalPluginClassName=A5MaliMetalDevice` properties compile only with
`A5_MALI_STOCK_METAL_DISCOVERY=1` after patch 0157. It registers only if
`a5gpu=8`, `a5gpuclient=1`, and `a5metal=1` are all present. The compile-time default is now one, as requested for the discovery
BOOT candidate; `a5metal` still defaults off when omitted. This class is an iOS discovery wrapper, not an
Apple AGX or IOGPU implementation; loading another provider that defines the
same `IOAcceleratorES` class would also need collision analysis.

`StockMetalPlugin` contains source and an `Info.plist` for a local bundle. The
principal `A5MaliMetalDevice` checks the proxy metaclass, resolves its parent
private service, and passes that to the existing entitlement-gated bridge.
`build_local.sh` creates and ad-hoc signs an iOS arm64 bundle in a local output
directory. It does not install the bundle on the phone or change kernel boot arguments.
The class intentionally declares neither Metal protocol and is rejected by
Metal's device-add gate.

The audit checks part of step 3 without changing the registration gate. It
deliberately does not supply placeholder protocol declarations. The
private `A5MaliRestrictedDevice` bridge has a bounded IOSurface copy and an
authenticated, exact-library `read_surf` pipeline candidate. The candidate
still lacks the full `MTLRenderPipelineState` and general draw semantics.
The discovery proxy does not make this class a working Metal device.

The user requested discovery be enabled and a BOOT image prepared. This
allows the proxy to register, but does not waive the existing flash gate for
an integrated Metal provider, draw translation and general resource queue.
A complete provider still needs public/private device behavior, broader shader
translation, render encoding, ordered resource hazards and completion, and
phone verification of a stock QuartzCore draw.

Run `sh test_discovery_audit.sh` for the host rejection checks and an iOS arm64
object compile, and `sh StockMetalPlugin/build_local.sh` for the local bundle.
Use `tools/a5xelte-pack-metal-boot.py REFERENCE_BOOT LINKED_KERNEL OUTPUT_BOOT`
to retain the working Samsung loader/ADT and select `a5gpu=8 a5gpuclient=1
a5metal=1`. The companion bundle must be installed separately under
`/System/Library/Extensions`; it is not embedded in BOOT. Preparation does
not flash the device or establish stock Metal acceptance.

## 0158–0159 provider integration

The stock plugin now attaches the OS's real MTLDevice and MTLDeviceSPI protocols
only after checking required instance-selector presence and the iOS16 limits
layout. Its initializer returns nil if that check failed. It initializes the
inline limits and installs the stock conservative feature-query base object,
with no Apple GPU family advertised. This implements the static device-add
contract; it does not establish general shader or pipeline coverage.

Patch0158 permits the existing QuartzCore displayable-context entitlement to
open the bounded private client only under a5metal=1. The custom private
entitlement remains supported. Patch0159 embeds our signed bundle/probe/job
locally and installs five fixed paths through the normally mounted HFS VFS
before launchd. It requires a5metal_install=1 rootrw=1 emmcroot=USERDATA
emmcwrite=1, and reuses the normal HFS journal replay rather than editing raw
filesystem metadata in TWRP. The source generator contains no proprietary
binary. Build outputs and generated includes remain private.

The acceptance probe calls the unmodified MTLCreateSystemDefaultDevice and
checks the returned Mali object's protocols and completed init methods.
`STOCK DEVICE ACCEPTED` in the phone log is the acceptance criterion. Compiler,
selector-presence and host mock tests are not that runtime result. Unsupported
shader families, compute, heaps, GPU-address reservations and other unimplemented
features explicitly fail; full SpringBoard rendering remains separate.
