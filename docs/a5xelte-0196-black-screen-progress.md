# 0195 wake trial and 0196 pixel/HID/completion measurements

## Wake trial evidence

The user repeatedly pressed Home and power with no visible change. SYSTEM
flush51 contains148,994 bytes; all were recovered without overwrite
(decoded148,749 bytes /1,968lines). No process crash or kernel panic appears.
Both runtime audits still pass14 class/protocol mappings /751methods.

The kernel records Home usage0x40 and power usage0x30 down/up events with one
HID client after the provider starts. Volume events also arrive. This proves
GPIO/key-service activity and dispatch toward an attached client; it does not
prove that backboardd drains its shared event queue or acts on those events.

Backboardd again completes two command buffers and five native GPU jobs
(clear0 and two602/603 pairs), status0/header1/MMU0. Shared purge transitions
succeed. This run has two GPU full-panel copies and one CPU full-panel copy
according to the framebuffer windows, despite the user's black-screen result.
There is one display-off request, and key events continue after it without
another recorded display-on. Sleep alone is not an adequate explanation of
the observed failure; the event-consumption and compositor state are unknown.

The photo's failed AGXAccelerator/IOGPU matches do not establish a Mali
registration failure: actual audit/device/command evidence must be used.
The kernel continues recording events/services, so the unchanged visible
console text does not by itself demonstrate a complete kernel hang.

## Measurements added for 0196

These changes identify the failing boundary; they do not claim a repaired UI.

- Kernel native completion samples up to4096 BGRA pixels on each of the first
  16 output surfaces, **after** terminal completion and output cache flush.
  Logs contain counts of nonblack RGB and nonzero alpha, not actual pixels.
- After each of the first eight successful full-panel GPU copies, compare the
  same bounded grid in the retained source and physical panel mapping, using
  their separate4352/4320-byte strides. The panel's existing CPU mapping is
  write-combined. No reference image is written and no failed/uncertain GPU
  job is sampled. A sampled match is not proof of every panel pixel or DECON
  scanout; it tests whether source and destination differ at those points.
- Keyboard enqueue records bounded success/full, head/tail and notification
  counters. Head movement across events distinguishes a draining shared queue
  from a producer that merely has an attached client.
- Metal logs submission/completion queue configuration, command waits and
  callback queued/begin/end with counts. No callback ordering or queue
  behavior is changed. A same-serial-queue wait remains a hypothesis pending
  runtime evidence, not a proven device deadlock or an implemented fix.
- The backboardd stderr tee budget increases from256 to1024chunks, still
  saturating and bounded. This preserves later callback/rejection messages
  beyond startup chatter. Probe/compiler budgets are unchanged.

## Verification

`tools/test-a5xelte-frame-pixels.py` reconstructs the actual helper from patch
0191 and compares it with the staged kernel. ASan/UBSan tests cover black,
opaque and colored frames; differing panel/source strides; RGB/alpha mismatch;
short/null/zero/overflowing input geometry; and a1x1 surface. It passes.
The complete patch applies without fuzz to the saved prior source and exactly
matches the staged files.

The full native host suite and Cortex-A53 provider cross-compile pass after
the logging changes. These transport tests do not establish GPU pixel output.
The actual installer preflight accepts16 files,39,515,550 raw bytes and
9,445,979 compressed bytes. Initial and final XNU make results and the BOOT
installation receipt are recorded below when available.

## Local build/package

Initial and final complete XNU make both exit zero. The final BOOT image is
30,308,368 bytes, within p10's33,554,432-byte capacity. Provider/probe signature
page checks pass. Device pixel/HID/callback results remain pending.

## Installation

From source `3f9bd3e`, Mac ADB confirmed the authorized lab a5xelte in TWRP
and BOOT p10's32MiB capacity, streamed30,308,368 bytes with matching dd receipt,
synced and requested reboot. No BOOT backup or post-write hash/readback was
taken, following the user's instruction. Recovery/EFS/radio/GPT were not
written; no raw USERDATA transfer. Runtime measurement results are pending.
