# 0214 resource lifetime and blend candidate

## Changes

Completed native command buffers release operation closures after terminal fence confirmation, outside the transport lock. Pre-submit encoding cancellation and safe terminal rejection also retire captures while the public command buffer remains retained. Timeout or ambiguous post-submit failure preserves owners because the GPU might still access them.

Patch0204 separates128 bounded imported-surface handles from the unchanged four physical GPU mapping windows. A four-element protected-index set replaces32-bit logical-index shifts; generation-token validation and mapping epochs remain enforced. Import/live/peak/quota diagnostics and separate selector1-import versus selector4-map failures distinguish the previously combined NoResources path. A compile-time guard bounds the shutdown snapshot to4KiB (actual3,072bytes of surfaces).

The602 change admits exact premultiplied source-over, with real destination preload and a new independent physical pixel fixture. See[602 details](a5xelte-0213-profile602-blend.md).

## Verified locally

- Actual allocator/protection helper:128 entries, exhaustion, slot32/127 reuse, protected indices0/31/32/63/64/127, no bit-shift alias.
- Real bridge code: distinct import/map failure diagnostics and partial-import release.
- Actual command-buffer/clear-emitter/Submit18 integration:40 retained completed public buffers release40 captured owners. Cancellation and safe rejection release captures; timeout and malformed post-submit replies preserve them.
- All18 native wrapper cases and final Cortex-A53/iOS API compile pass. Actual602 copy/source-over factories, decoded Mesa fields and six negative blend contracts pass.
- Production provider/probe build and4KiB signatures pass. Released Mesa26.2.4 produces the same15 reference preload/resource shader binaries.

Repeat resource tests: `A5_MALI_MESA_BUILD=/path/to/released-mesa/buildtools tools/test-a5mali-resource-capacity.sh /path/to/patched-xnu/iokit/Kernel/arm /private/tmp/resource-tests`.

## Build/device status

All45 physical cases are embedded: the prior44 payload, expected and mask SHA256 pins are unchanged, and the actual602 source-over case is appended. The incremental31-file payload passes the real kernel installer preflight (40,707,850 raw /9,854,676 packed bytes).

After space became available, pinned libdispatch1415.140.2 was rebuilt for Cortex-A53 with the donor XNU exported headers first in its search path. The archive disassembly has no LSE operations. Availability121 and actual Xcode MIG tools are staged locally. Full XNU make exits0; the missing debugger `python` executable was supplied by a local wrapper invoking the existing Python3. No kernel checks were bypassed.

The final BOOT is31,789,072bytes, below the33,554,432-byte partition capacity. Its real freshly linked31,120,904-byte unstripped kernel contains the exact signed new provider, the verified existing compiler and45 GPU cases. Working0207d loader, ADT and DTBH bytes are unchanged. Four CPUs and32-sector storage batches remain selected.

Build and offline packaging pass. Phone installation and physical602 pixel/button-transition results are separate checkpoints.

The guarded direct BOOTp10 write acknowledged all31,789,072bytes; sync completed and reboot was requested. No BOOT backup, post-write hash/readback or full USERDATA transfer occurred. Physical45-case pixels and stable lock-screen/button transitions remain pending the next capture.
