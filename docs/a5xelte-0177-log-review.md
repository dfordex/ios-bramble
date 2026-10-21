# 0177 recovered log review — 2026-10-22

Read-only SYSTEM recovery yielded flush57,122948 raw bytes and1703 decoded
lines, without ring overwrite. Raw logs remain private.

## Kernel and backboardd remain active

The capture records14 key transitions, with HID delivery to one client. The
user did not see key messages on the panel, but the saved log establishes that
the kernel received these events. It does not prove every physical press was
delivered or that the UI responded.

One backboardd and one SpringBoard execution are recorded. There are no CRASH,
panic, missing-selector or pipeline-rejection records in this window. Stock
backboardd accepts14 pipeline creations across12 distinct profiles, including
the previously incompatible A2 inactive attachment contracts. This is observed
factory acceptance, not proof of successful GPU rendering or indefinite
backboardd stability.

## First fragment job faults before pixel evaluation

The existing control finishes256/256 pixels. The new path rectangle oracle
finishes its vertex/preload/tiler chain as fence3, then fragment fence4 reports
JS_STATUS0x58, DATA_INVALID_FAULT, with MMU IRQ0. The suite reports status4
(Fault), evaluated0 and stops before the other six cases. Its headerffffffff
and immutable0 are unevaluated sentinels, not measured corruption or zero
rendered pixels. The driver's wording `still active` is misleading for this
fault code; it must not be described as an ACTIVE state or timeout.

The failed startup suite prevents the runtime queue from becoming ready.
NativeQuery17 can therefore fail during resource mapping, before NativeSubmit
diagnostics. No native completion is recorded, but absence of that trace alone
does not establish whether iOS attempted a draw.

## Presentation evidence

Across113 framebuffer metric windows, swaps total5 and shown frames total3.
The two printed swap records reference default console surface1. Both GPU and
CPU presentation bytes remain0 in every window. Backboardd creates a1080x1920
BGRA surface and continues framebuffer callbacks late in the capture, but no
iOS frame transfer is proven. Normal network/service activity, including
Skywalk registration, is not a GPU completion indicator.

## Source-proven preload descriptor violation

Released Mesa26.2.4 v4 defines MALI_SAMPLER_ALIGN=32. The shared preload emitter
places the sampler at job offset0x19d0, only16 modulo32; its first test publishes
GPU address0x020019d0. The older working fixture's sampler is correctly aligned.
Other new preload descriptor offsets satisfy their released alignment rules.

Move the sampler to0x19e0, ending at viewport0x1a00, with compile-time layout
guards and a packed-descriptor check. Keep shaders, expected pixels and masks
unchanged for the retry. This is a definite descriptor defect consistent with
the fragment data fault, but device testing must establish whether it explains
this failure completely.
