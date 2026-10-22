# 0194: Metal method surface and resource contracts

## Purpose and scope

0193 reached genuine backboardd native clear/draw submissions, then failed on
`-[A5MaliSharedReadBuffer setPurgeableState:]`. This change closes the known
method surface in one pass rather than waiting for each missing-selector
exception on the phone. It does **not** implement every Metal GPU feature.

The private local iOS 16 protocol extraction gives 607 required method entries
across 12 class/protocol mappings and another 202 entries across nine SPI
mappings. These totals include inherited/repeated methods, not 809 new
implementations. All have zero source-missing selectors and zero coarse
return/argument ABI gaps. In particular, 341 device selectors are inherited
from stock `_MTLDevice`; availability is not Mali execution support.

The extraction lacks Queue, Render and Blit protocol definitions. A separate
iPhoneOS 27.1 SDK surrogate, filtering methods marked iOS 17 or newer, checks
7 Queue, 122 Render and 23 Blit declarations with zero source gaps. This is
explicitly separate from the pinned iOS 16 metadata gate.

## Implemented behavior

- Shared and private buffers implement purge state transitions and return the
  previous state. Owned Empty storage is released and NonVolatile storage is
  recreated; allocation failure preserves the previous state. No-copy storage
  retains caller ownership and invokes its deallocator exactly once.
- Resource aliases compare real overlapping backing spans or private handle
  identity. Bounded same-format mip views retain the parent resource. Debug
  markers and non-heap metadata have actual lifetime/range behavior.
- IOSurface purge is refused with actual NonVolatile state; VM ownership
  transfer and resource-wide GPU completion are explicitly unsupported. Stable
  GPU addresses/resource IDs are not invented.
- Library async creation snapshots name/constants/descriptor before dispatch,
  invokes its completion once, and preserves result/error behavior. Metadata,
  function options, specialization metadata and unsupported reflection/archive
  operations have typed implementations. The private reflection callback takes
  one object argument, matching the inspected stock implementation.
- Sixteen CommandBuffer and eleven pipeline metadata gaps are closed. Of 92
  additional Render SDK selectors, three delegate to existing supported paths
  (single viewport, single scissor, zero-base-instance draw); 89 return typed,
  sticky unsupported command errors. Compute, mesh/tile/tessellation, indirect
  execution, events/fences and drawable scheduling are not silently accepted.
- Queue capture boundaries are advisory markers; no capture/GPU work is claimed.
  There is no generic selector forwarding or success-only fallback.

The async/function contracts follow the public Apple
[MTLLibrary](https://developer.apple.com/documentation/metal/mtllibrary?language=objc)
and [functionConstantsDictionary](https://developer.apple.com/documentation/metal/mtlfunction/functionconstantsdictionary)
descriptions. Private signatures also use the local runtime extraction.

## Registration gate

The provider now checks 14 actual class/protocol mappings in the target process
before registering its device. The recursive runtime audit verifies selectors
and coarse return/argument category, size and alignment. It emits one summary
and specific failure lines, avoiding routine per-method log spam. A failure
prevents device registration. Host compilation cannot prove this gate passes
on iOS; the next device log must establish that result.

The gate does not prove callback signatures, every struct layout, shader
correctness, complete feature semantics or correct compositor pixels.

## Verification and build

- Full native mock-transport suite passed, including original clear/render,
  generic 600–603, indexed/textured paths, source-over and no-copy alias tests.
- Resource purge/rollback/lifetime and library async snapshot/callback tests
  passed; unsupported SPI tests passed. These are not GPU pixel tests.
- Actual metadata gate and negative synthetic-selector regression passed;
  separate SDK surrogate zero-gap gate passed.
- Cortex-A53 iOS 16 Werror compilation, final provider build and 4 KiB code
  signature verification passed. Complete XNU make exited zero.
- Installer preflight accepted all 16 payload files: 39,515,470 raw bytes,
  9,445,341 compressed bytes. Provider binary: 739,936 bytes. Existing 0192
  shader registry, 0191 compiler package and 0193 OOL input preparation are kept.
- BOOT candidate: 30,289,936 bytes, within p10's 33,554,432-byte capacity.
  Local artifact: `/private/tmp/a5xelte-0194-artifacts/a5xelte-metal-0194.boot.img`.

No phone success is asserted by these checks. The next run must establish
runtime audit acceptance, absence of the purge selector exception, and what
backboardd requests next. Later shader specialization failures, the 84-page
contiguous allocation pressure, and slow on-phone compiler publication remain
separate unresolved issues from 0193. A zero missing-method count does not
establish that the black screen is fixed.

## Installation receipt

Mac ADB identified the previously authorized lab a5xelte in TWRP 3.3.0-0,
verified BOOT resolves to p10 and its 32 MiB capacity, then streamed exactly
30,289,936 bytes to p10. The dd receipt acknowledged that count; sync and
reboot completed. Source commit: `6d39b3a`. No BOOT backup, post-write hash
or readback was taken, following the user's instruction. No raw USERDATA
transfer or recovery/EFS/radio/GPT write was performed. The embedded provider
and compiler installer will update their files during XNU boot. Runtime
selector audit and screen result are pending.
