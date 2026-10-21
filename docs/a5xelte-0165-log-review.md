# 0165 recovered boot log

Read-only Mac ADB recovery from the reserved SYSTEM console ring, 2026-10-21.
Flush21 contains90,873 raw bytes, with no ring overwrite; CR removal produces
90,628 text bytes and1,076 lines. Every recovered line was reviewed. The final
unflushed interval before recovery cannot be reconstructed from this ring.
Raw capture and decoded log remain private, outside Git.

## Actual translated downsample test

| Evidence | Result |
| --- | --- |
| Lines93–94, existing texture fixture | JS1 fence1 and JS0 fence2 completed;256/256 pixels matched; MMU IRQ0. |
| Line95, genuine downsample pair | The new test started with64x64 source,32x32 destination and49,152 mapped data bytes. |
| Line105, new fence3 | JS1 remained active: status0x8, pending0, job IRQ0, MMU raw IRQ0x1. |
| Lines106–108 | Queue returned fault and retained its backing. The fragment job was never submitted. |

**No translated output pixel result was obtained.** The printed fragment
fence0,0/1024 pixels,0/4096 source and0/3072 guards are initial counters after
an unsubmitted fragment job, not measured bad pixels or memory corruption.
Likewise the subsequent completion-struct MMU0 and header0xffffffff fields
were not populated on the queue's early fault return. The hardware snapshot
on line105 is the relevant MMU evidence.

The private GPU queue remains poisoned/pinned after this fault. Its runtime
submission path was not enabled for this boot. The exact AS0 fault status,
fault address and current job head were not logged, so the saved log cannot
distinguish a vertex fetch from the linked tiler job or name the invalid VA.

### Source findings after recovery

1. The self-test modifies live AS0 L3 entries and issues only
   `AS_COMMAND_UPDATE`. Existing `A5XELTEGPUFrameMap.cpp` and the Linux
   Panfrost path instead use `LOCK` followed by `FLUSH_PT` for live table
   changes. This is a synchronization gap that must be fixed. However, the
   static vertex/tiler data lie in the original first four pages, so it is
   not yet a proven explanation for the observed fault.
2. The new descriptor builder writes identical tiler heap start/end pointers
   at `FB+27*8` and `FB+28*8`, producing a zero-length heap at the polygon
   list. The earlier working texture fixture supplies a nonempty4KiB heap.
   This is another concrete descriptor difference to correct and validate;
   the log does not establish whether execution reached the tiler allocation.

Compiler-info inspection confirms both stages require zero TLS/WLS bytes;
work-register counts are8/7. Vertex output strides16/4/8 match the position,
point-size and texture-coordinate descriptors. All static shader/attribute/
UBO/varying pointers are inside the mapped private region. These checks do
not establish that every dynamic hardware access was valid.

Next GPU test needs both corrections plus AS0 fault status/address and JS1
current-head capture on **every** early failure path, before clearing/resetting
hardware. A longer timeout alone does not address the recorded MMU interrupt.

## Full boot and userland review

- Four CPUs initialized and SGI1 verified. No kernel panic or logged SIGILL
  occurred in the recovered window.
- USERDATA HFS root mounted read-write. Journal replay finished and two
  orphaned files were removed. No eMMC command error appears. This records
  successful mounting, not a complete filesystem integrity check.
- The six-file installer found all existing payload files and completed
  with sync0. It did not require a whole-root transfer.
- Launchd completed early boot. SpringBoard executed twice. Backboardd
  executed four times and all four recorded crashes are SIGABRT with
  namespace13/code2: **Metal failed to load fragment function**. The repeated
  caller, after removing the shared-cache slide, is0x1884862ac, the same
  QuartzCore fragment-function failure seen in0164. These later userland
  aborts are separate from the standalone GPU job fault; this build did not
  add the downsample functions to the iOS provider.
- The stock Metal probe again reported `STOCK DEVICE ACCEPTED` and created
  a bounded command queue. Backboardd initialized the provider's limits and
  feature queries. Device acceptance does not prove hardware submission.
- All44 framebuffer measurement samples report zero swaps and zero shown
  frames; CPU and GPU present counters are also zero.
- HID touch and button providers registered and opened. Contact logging is
  disabled by `a5touchlog=0`; this capture alone cannot verify touch response.
- There are91 `exec xpcproxy` lines and one `exec bluetoothd` line. Exec
  messages alone do not establish crashes; only backboardd has an explicit
  crash record in this capture.

## Additional warnings

The following also occurred in0164 and are not new evidence of the GPU fault:

- Missing separate data-volume information and missing BindFS firmware /
  factorydata paths; boot continues past them. HFS root is present.
- Missing SEP/NVRAM services and unsupported HFS data protection.
- Usermanagerd next-session/foreground setup warnings and initial persona
  lookups. Persona allocations and session save subsequently succeed, though
  foreground setup is not thereby proven correct.
- `/tmp` and `/var/run` cleanup return invalid argument.
- PRNG virtual-random initialization reports failure. The separate corecrypto
  FIPS self-tests all pass; that does not resolve the random-device warning.
- One `Failed to open swap file 2` message; its cause/errno is not supplied.
- One denied logd privilege1002 and60 duplicate Objective-C class warnings
  from game-controller HID plugins. No recovered crash points to those classes.
- Shared-region address-check messages and the configured unsealed-root
  warning; shared-cache loading proceeds and userland executes.

The shorter0165 capture has fewer crashes than0164, but the durations differ;
the count difference does not demonstrate improved stability.

No new image was built or flashed while reading and reviewing this log.
