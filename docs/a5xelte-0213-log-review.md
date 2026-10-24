# 0213 full device log review

## Capture and scope

TWRP read-only SYSTEM ring recovery: flush77, 744,917 bytes, no wrap or overwritten bytes. The complete decoded log has 7,948 content lines. No BOOT readback, device mutation, or whole USERDATA transfer was performed. Raw captures remain private.

## GPU regressions and input

Both new actual phone-stage tests pass all4,096 pixels: the2,240-byte color-only ordered-fetch fragment and the176-byte constant/no-input fragment. Total40/44; the four earlier RAW/R8/fetch-noise failures remain and are not relabeled as successful. Terminal test fences report status0, header1 and MMU0. Dynamic compiled stages are accepted and several live command buffers complete successfully.

Home, Power and volume events enter the HID queue. Recorded queue heads advance and full stays0. Thus the captured failure is downstream of input enqueue/consumption; it does not prove that every rapid press independently triggers a crash.

## First drawing blocker: exhausted imported resources

At line4,613 a128x64 BGRA8 private render-target allocation fails with e00002be (kIOReturnNoResources), following successful IOSurface creation.100x64 targets repeat the same failure. The bridge combines selector1 import and selector4 map, so this log cannot distinguish import quota from GPU mapping failure. The kernel selector1 path returns this status when its32 logical import slots are occupied; mapping can independently return the same status. These logical handles are distinct from the four physical GPU mapping windows.

Command buffer8 records an indexed resource-contract rejection, then commits with submitted0/status5/error e00002c7. Further command buffers repeat without reaching native submission. Source audit finds completed or pre-submit-failed command buffers can retain operation closures and their auxiliary textures until outer command-buffer destruction. This provides a concrete resource lifetime defect; device slot occupancy needs explicit new instrumentation to prove its runtime extent.

## Spinner/crash blocker: profile602 blend state

Two backboardd SIGABRT records occur, at lines5,066 and7,702. Both report namespace13/code4: Metal failed to build render pipeline. Recovered strings report profile602 attachment0.blendEnabled actual1 expected0. Other source/destination blend factors for this failed request are not fully captured, so only the enabled-state mismatch is directly established.

The next candidate admits the precise premultiplied source-over equation ADD/ONE/ONE_MINUS_SOURCE_ALPHA with destination load, alongside the existing copy contract. Other equations still reject with a recorded reason. The shader bytes themselves remain unchanged. A new physical pixel oracle must check the destination contribution and preserved scissor border.

## Limits

No kernel panic or SpringBoard crash record is present in this capture. GPU drawing has occurred, but interactive lock-screen transitions and complete general Metal coverage are not established. The unchanged four failing physical tests remain open.0214 must separately verify slot retirement, the actual602 request and stable UI/button progress on the phone.
