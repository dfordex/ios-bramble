# Private iOS Mali command bridge

This source connects an iOS process to the opt-in `A5XELTEGPU` user client
introduced in XNU patches 0148–0151. It opens the IOKit service, checks ABI
version and supported commands, imports a BGRA IOSurface with a Mach send
right, maps it into the client's private Mali address space, and submits
typed BGRA8 clear/copy requests through selector 6. The Objective-C
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
verifies that local dylib, and runs a host-side mock transport test covering
the exact input/output structure sizes, selector order, clear/copy fences,
rejected rectangles, failed jobs, and malformed replies. It does **not**
install the dylib or modify an iOS root image.

These classes are deliberately not `MTLDevice` or `MTLCommandBuffer`. Stock
iOS Metal discovers an `IOAcceleratorES` service and loads an `_MTLDevice`
subclass implementing public Metal and private `MTLDeviceSPI`. The staged
iOS 16.7.16 private protocol has 407 instance selectors. This bridge lacks
Metal shader/AIR compilation, render and compute pipelines, buffers,
samplers, texture state, resource hazards, and asynchronous command-buffer
retirement. Making it discoverable as a Metal device now would cause clients
to select a renderer that cannot execute their drawing commands. The BOOT
flash gate remains closed until a real provider, translation path, and
general queue are integrated.
