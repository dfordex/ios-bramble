# iOS graphics to Mali: runtime contract

This records the iPhone 8 Plus iOS 16.7.16 userland inspected locally on
2026-10-21. It is a static ABI investigation, except where the 0146 phone log
is explicitly cited. It does not claim an iOS draw call has run on Mali.

## Observed entry points

- The 0146 device log contains repeated `backboardd` matches for
  `IOProviderClass=IOAcceleratorES`, each finding zero services. This proves
  discovery attempts on the phone, not the format of a later user-client call.
- The staged `AGXMetalA11.bundle/Info.plist` names `AGXPrincipalDevice` as
  `NSPrincipalClass`. The extracted Mach-O has
  `-[AGXPrincipalDevice initWithAcceleratorPort:]`, links `IOGPU`, and contains
  A11-specific device and command implementation. It is not a Mali encoder.
- Static disassembly of the staged Metal binary at `_MTLAddDevice`
  (`0x181a1b368`) shows two `conformsToProtocol:` checks: `MTLDevice` and
  private `MTLDeviceSPI`. It then invokes `initLimits` and
  `initFeatureQueries`. The binary exports `MTLCreateSystemDefaultDevice`.
  Its strings include `/System/Library/Extensions`, `principalClass`, and
  `IOAcceleratorES`. These strings alone do not prove that an unsigned custom
  bundle will load on this booted image.
- The staged IOGPU binary exports device creation, IOSurface resource import,
  queue creation and command-buffer submission functions. Those interfaces
  do not translate AGX commands to Midgard jobs.

## Required path to system composition

An iOS-facing Mali implementation needs a loadable Metal provider that passes
the `MTLDevice` and `MTLDeviceSPI` checks and can produce valid Mali resources,
render and blit commands, pipelines, completion signals and failures. Its
kernel partner must validate per-task resources and submit bounded Midgard
jobs with correct IOSurface lifetime, cache ownership and GPU fault handling.
Patch 0148's private resource protocol is disabled by default; patch 0149
adds only a fixed 16 by 16 GPU sampling selector. Stock QuartzCore, Metal
and AGXMetalA11 cannot use that selector as a draw-command queue.
The current kernel fixture uses one shared GPU address space and a pinned
64 KiB backing region containing its descriptors and job data. Its queue
waits synchronously and halts after an ambiguous fault. Exposing arbitrary
user job descriptors here would permit DMA into other mapped pages; a general
queue needs per-client address spaces, mapped and pinned buffers, validated
submission, asynchronous completion, and fault containment first.

Before advertising acceleration, verify on the phone that a custom provider
loads, `MTLCreateSystemDefaultDevice` selects it, an actual iOS draw command
submits a translated Mali job, and its completed IOSurface pixels reach DECON.
Then compare sustained frame production and CPU use. A successful full-frame
GPU copy from an already-rendered IOSurface proves only the final presentation
step, not GPU rendering of SpringBoard layers or icons.

Static checks used `plutil -p`, `nm -m`, `otool -L`, `otool -tvV` and `strings`
against locally extracted Mach-O files. No Apple binary, IPSW content or
device log is included here.
