# iOS GPU ABI boundary on a5xelte

Observed against the staged iPhone 8 Plus iOS 16.7.16 root and the local
0134 XNU source on 2026-10-20. This is a source and binary inventory; it is
not a claim that an iOS Metal command ran on Mali.

## Userland contract

- `System/Library/Extensions/AGXMetalA11.bundle/Info.plist` names
  `AGXPrincipalDevice` and executable `AGXMetalA11`. This is the iPhone's
  AGX implementation, not a Mali-T720 backend.
- The dyld shared cache contains `IOGPUDeviceCreate`,
  `IOGPUCommandQueueCreate`, `IOGPUCommandQueueSubmitCommandBuffers`,
  `IOGPUResourceCreateIOSurface`, and `IOGPUResourceGetGPUVirtualAddress` in
  IOGPU, plus Metal command-buffer classes. A provider must support resource
  import, command creation/submission, memory ownership, completion, and
  faults before advertising an accelerated device.
- `AppleCLCD::present()` still obtains IOSurface bytes and copies rectangles
  through the CPU to DECON. The Mali self-test has a bounded private queue,
  but it has no iOS user client and does not consume these command buffers.

## Bounded discovery instrumentation

Patch `0137-a5xelte-metal-service-discovery-probe.patch` adds boot argument
`a5metalprobe=1`. It prints at most 64 IOKit matching results for service
names containing `IOGPU`, `IOAccelerator`, or `AGX`. The default is off. It
does not publish a service, alter a match result, accept a command buffer, or
report a GPU device to userland. This is useful for learning which discovery
path the running iOS components actually take before selecting an ABI.

Sample output format:

```
A5XELTE METAL: matching IOAcceleratorES result=0
```

`result=0` means no matching service was present at that instant. It does not
prove the process attempted Metal rendering: IOKit notifications and other
callers can also initiate matching. The probe intentionally omits process
attribution and request payloads.

## Remaining interface work

The smallest *functional* iOS-facing accelerated path still requires a real
Mali-compatible userland backend. Naming an `IOGPU` service is insufficient:
the staged `AGXMetalA11` executable emits/handles Apple AGX-specific commands,
while the Exynos7580 GPU consumes Midgard jobs. There is no AGX-to-Midgard
translator or `IOGPU`/`IOAccelerator` user client in this XNU source. The
next implementation must first demonstrate one imported IOSurface, a
translated draw or blit, fence completion, and matching pixels on the phone.
Only then should a GPU capability be advertised to SpringBoard.

No IPSW content, extracted binary, or device dump is included in this patch.
