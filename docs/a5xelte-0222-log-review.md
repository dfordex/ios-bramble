# 0222: automatic dispatch and startup/storage bottlenecks

## Device evidence

SYSTEM flush 75 recovers 627,378 logical bytes and 8,257 decoded lines. No CRASH, kernel panic, MMU fault or indexed rejection is recorded. Twelve recorded command-buffer results complete through CB13. Touch initializes and 359 HID contact records appear. The TWRP reply did not include a physical interaction result; kernel events alone do not establish responsive UI.

The scanner is exercised: its first 44-candidate scan handles three new terminal pipeline requests and one maintenance entry. Later scans defer old bodies and handle one maintenance entry. A later real fragment receives `arriving-function`, `dispatch`, workspace/profile preparation and a successful child spawn. No archive is recorded. Automatic dispatch has progressed on the phone, but no new stage publication is captured before shutdown.

The child runs for 179.9 seconds of wall time with approximately 6.14 milliseconds of accounted CPU, no observed tool exec and an empty compiler log. It is still named a5shader-compile in three samples and has one thread. The first worker checkpoint precedes the autorelease pool in main but is absent from the redirected log. This points to intermediary startup before main rather than 180 seconds of active AIR translation. Shared-cache PCs have not been precisely symbolicated; no particular dyld initializer is established as the root function.

## Direct tool startup

The runner previously spawned itself as a Foundation/IOKit-linked `--worker`, which then execed the real tool. The actual AIR and native tools link only libSystem. Version 0223 removes the extra executable startup: `posix_spawn` receives the exact installed tool directly. Process groups, child/descendant accounting, the 500 MiB group limit, 8 MiB file limit and unlimited compilation time remain. The file limit is established in the dedicated compiler daemon before spawn, not in the compositor. Existing daemon writes are bounded below that per-file limit.

Eight actual OS exec/resource tests pass: direct child/observed image, invalid image/no shell, inherited file limit, oversized output, oversized group termination, child signal, descendant cleanup and untrusted path rejection. Actual automatic AIR/SPIR-V/native compilation remains byte-identical in the genuine worker regression. This is a general startup correction, not a shader whitelist entry. Device execution of the new path remains to be checked.

## Storage and memory

Observed eMMC intervals exceed 98 percent controller-lock active time, near 5 MiB/s with zero errors. Active time includes preemption while holding the lock; this does not prove the card is busy for that whole interval. Aggregate mutex wait grows heavily. The SYSTEM logger accounts for under one second and is not the primary recorded I/O load. All strategy operations serialize through the existing mutex.

The advertised ioctl limits still say one logical block and one segment despite the implemented 32-sector transfer loop. Actual HFS journal code consumes those limits and fragments I/O. Patch 0208 reports bounded 16 KiB byte/segment limits, a logical-block-size-adjusted block count and page-adjusted segment count. Read-only write limits remain zero. PIO commands, 32-sector chunks, locks, clocks and flush/order behavior are preserved. Actual ioctl plus actual HFS limit calculation passes 16 sanitizer combinations; 91 existing MMIO/PIO strategy cases pass. Device improvement is unverified.

XNU's original isolated memory window is 512 MiB at `0x80000000..0xa0000000`, while recovery reports 1,872,760 KiB usable memory. Device-tree banks and named reservations, together with recovered downstream CP/EL3 reservations, support an opt-in contiguous extension to `0xae000000` (736 MiB). It stops 12 MiB before video_ext at `0xaec00000`. This does not establish that all 2 GiB can be exposed contiguously. The default 512 MiB loader rebuild matches the installed loader byte-for-byte; the opt-in variant updates the loader bound, payload header and existing ADT dram-size together. Runtime page counts and stability remain required. The reservation audit is not claimed complete for hidden firmware uses. See [the RAM evidence and limits](a5xelte-736mib-lab-window.md).

The captured fragment compiles through the unchanged translator/backend: 1,152 native bytes, five registers, no TLS/WLS, one live texture and reflected inputs. Actual cache/factory/emitter replay accepts it. It is staged to avoid repeating the known wait, while direct startup addresses subsequent uncached requests. Neither host replay nor preloading proves automatic publication on the phone.
