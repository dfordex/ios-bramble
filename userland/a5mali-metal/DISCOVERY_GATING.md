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
   separate proxy metaclass only in an explicitly provider-ready build.
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
`A5_MALI_FULL_METAL_PROVIDER_READY=1`. Even then, it registers only if
`a5gpu=8`, `a5gpuclient=1`, and `a5metal=1` are all present. The default
compile-time value is zero. This class is an iOS discovery wrapper, not an
Apple AGX or IOGPU implementation; loading another provider that defines the
same `IOAcceleratorES` class would also need collision analysis.

`StockMetalPlugin` contains source and an `Info.plist` for a local bundle. The
principal `A5MaliMetalDevice` checks the proxy metaclass, resolves its parent
private service, and passes that to the existing entitlement-gated bridge.
`build_local.sh` creates and ad-hoc signs an iOS arm64 bundle in a local output
directory. It does not install the bundle on the phone or turn on patch 0156.
The class intentionally declares neither Metal protocol and is rejected by
Metal's device-add gate.

The audit checks part of step 3 without changing the registration gate. It
deliberately does not supply placeholder protocol declarations. The
private `A5MaliRestrictedDevice` bridge has a bounded IOSurface copy and an
authenticated, exact-library `read_surf` pipeline candidate. The candidate
still lacks the full `MTLRenderPipelineState` and general draw semantics.
That is a hard stop for advertising this device.

Before enabling registration, the implementation needs a genuine kernel
provider with bounded per-client resource mapping and fault isolation; an
iOS loadable and signed Metal plugin; complete public and required private
device methods; shader/library translation; real render and blit command
encoding; ordered resource hazards and completion; and a successful stock
QuartzCore draw observed on this phone. The current opt-in private userclient
and host tests do not establish any of these stock discovery or draw results.

Run `sh test_discovery_audit.sh` for the host rejection checks and an iOS arm64
object compile, and `sh StockMetalPlugin/build_local.sh` for the local bundle.
On-device registration must remain off until the drawing path and all protocol
behavior have been verified end to end.
