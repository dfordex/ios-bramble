# A5XELTE iOS graphics discovery probe

`./build.sh /tmp/a5xelte-metal-probe` builds an arm64 iOS 16 command-line
executable from local source. It uses the installed iPhoneOS SDK, not IPSW
binaries. Run it on the phone only after staging it outside the Git tree. It
prints matching counts for the private `A5XELTEGPU`, `IOAcceleratorES`, and
`IOGPU` services, the private userclient query result when permitted, and
whether Metal creates a real default device and command queue.
When the private client is available, it creates and fills a 16 by 16 BGRA
IOSurface, imports its Mach port through the version 1 resource protocol,
requests the fixed tile sample, prints completion fences and matching pixels,
then releases the handle. The only submitted work is the bounded kernel
fixture; the probe does not encode an iOS Metal draw command.

The private query matches patches 0148–0149. That userclient requires the
`com.orhunnx.a5xelte.gpu-resource-client` entitlement, embedded in the ad hoc
signature by `build.sh`, and its version 1 reports `gpuCommandsSupported=1`
only for the fixed sample. It cannot accept arbitrary draw commands.
Whether the development AMFI bridge accepts that entitlement must be checked
on the phone. A service match or non-null `MTLDevice` alone cannot prove a Mali
command executed; rendering requires a functional Metal backend and verified
GPU job completion on a frame produced by iOS.

The probe does not advertise a Metal GPU, modify partitions, or contain
proprietary Apple code. Standard output should be captured explicitly when
running it on device.
