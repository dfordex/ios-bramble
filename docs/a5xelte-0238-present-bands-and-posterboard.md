# 0237 readout and 0238 presentation changes

## Fresh phone evidence

The complete decoded 0237 ring contains 5623 lines (501518 UTF-8 bytes).
All four identity sysctls return success: hw.machine/hw.product are iPhone10,5;
hw.model/hw.target are D211AP. The three stock application proxies are already
valid, although the startup helper registers them again.

All 29 captured command-buffer result records are Completed/error0. No new
large-draw rejection is recorded. Of 100 framebuffer intervals, 82 have no
swaps; the maximum interval is 2.9fps. These intervals include startup and idle
and do not measure a steady interactive rate. A previously requested fragment
remains waiting; this does not establish a compiler crash. Storage records
2.45GB read, 86MB written and zero errors. Its parallel lock-wait aggregate is
not wall-clock duration.

PosterBoard loads this Metal provider, reports GPU client initialization failed,
then throws NSInvalidArgumentException while inserting a nil dictionary object.
A bounded read of its actual installed executable confirms its signed identity
is com.apple.PosterBoard and it carries QuartzCore.global-capture, but lacks
QuartzCore.displayable-context. The existing resource client accepts the latter
capability; this is a concrete missing authorization path. The new path still
needs a runtime acceptance receipt. The earlier PosterBoard switcher-state
assertion is a different fault.

There are also 21 driverkitd deaths with SIGKILL and reason namespace1/code7.
The corresponding kernel enums identify a per-process memory-limit termination.
This is not proof of general RAM exhaustion. Its launch job runs at load and
listens for application registration events. Avoiding redundant registration
removes those three unnecessary events; it does not fix or disable its memory
limit. The driverkitd restart cause remains open.

## Exact row bands for scanout

Patch0215 adds opt-in a5fb_damage=1. After the existing mapper validates and
pins an exact 1080x1920 BGRA surface, its CPU alias is reconciled before
comparison with the last successfully presented image. Full active rows are
compared byte-for-byte, including alpha; row padding is ignored. Identical
content skips both presentation jobs. Otherwise the smallest enclosing row
band expands to 16-row tile boundaries. The viewport and fragment tile bounds
clip the existing genuine texture copy to that band. Texture geometry, UVs,
framebuffer dimensions and scanout address remain the established full-size
values. A change on distant rows may still require a full-height transfer.

The shadow changes only after real tiler and fragment completion. Power fades,
CPU/layer fallback and uncertain GPU results invalidate it; the next eligible
frame is full height. Unsupported geometry keeps the old fallback. The final
output pixels remain GPU-produced and DECON scans the existing buffer.
This is not direct display buffer flipping or a claim of zero-copy rendering.

The comparison uses an additional 8294400-byte kernel allocation and scans the
active source rows on each eligible presentation. It can therefore increase
CPU/cache work even while reducing GPU output traffic. Allocation/coherency
failure falls back to the existing full GPU copy. On-device counters and FPS
must establish whether this tradeoff helps. GPU presentation byte accounting
now counts the actual band area; bounded logs report compared/partial/unchanged
frames, bytes and row bounds. A skipped frame does not count as a new GPU copy.

## Yield during long GPU waits

The AS0 and AS1 main job polls retain their short 10us spin for the first200us,
then sleep1ms when the remaining nominal delay budget permits it. This yields
the CPU while waiting instead of spinning for the entire operation. Register
checks, terminal header checks, slot-idle checks, fault receipts and resource
ownership rules remain required. A timeout is not turned into success.

This remains synchronous kernel submission with cooperative waiting; it is
not a fully asynchronous GPU backend. Overscheduling can extend the nominal
poll budget, and long-job completion observation gains millisecond granularity.
The preflight/MMU handshake polls are unchanged.

## PosterBoard and application registration

Patch0216 accepts PosterBoard only inside the existing a5metal=1 stock-client
opt-in, with exact signed code identity, exact executable vnode path and its
existing global-capture capability. Compiler-only connections retain their
separate checks. No process-name-only allowlist or fake device is introduced.
The positive path records a specific PosterBoard authorization receipt.

The signed startup helper validates app bytes/metadata/entitlements as before,
then skips MCM/registration if the proxy already has the correct path and state.
Missing or stale registrations still use the existing bounded retries.
No global application database/cache is deleted.

## Checks and installed artifact

- The actual band planner passes ASan/UBSan tests over80 frame transitions,
  exact full-panel equality in a host copy model, padding, alpha, invalidation,
  size/bounds rejection and a nonaligned final tile. Released Mesa26.2.4 v4
  unpackers verify emitted pixel scissors and fragment tile bounds. This is
  descriptor/model proof, not physical partial-render proof.
- The actual AS1 job function passes mocked-MMIO short/long completion,
  timeout, terminal fault, preflight busy and bad-header tests. Long waits yield;
  uncertain resources stay owned. The exact PosterBoard helper passes positive
  identity/path/capability and negative cases with retained object release.
- Eight real-input application-registration tests pass under ASan/UBSan,
  including zero registration/container calls for valid existing proxies.
  The iOS/A53 build and signed helper's4KiB code hashes pass.
- Both kernel patches round-trip exactly against the0237 baseline. Full XNU
  make exits0. The actual374-file installer preflight passes under ASan/UBSan.
- BOOT is25802768B; kernel25135544B. Every linked segment and all374 embedded
  payload CRCs match the final image; all270 stock app files and original
  ownership/modes match. Loader/DTBH remain exact0230; ADT is exact0237, and
  the sole boot-argument change is a5fb_damage=1. Four CPUs,736MiB and existing
  native GPU/touch/storage settings remain selected.
- Guarded recovery/model/TWRP/p10/capacity checks pass. The offset-zero BOOT
  write acknowledges all25802768B, sync exits0 and reboot is requested.
  No BOOT backup/readback or whole-USERDATA transfer is performed.

Physical partial-frame correctness, actual PosterBoard acceptance and an
interactive FPS improvement await the0238 phone run. The driverkitd deaths
and waiting fragment remain unresolved.
