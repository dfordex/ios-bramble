# 0236 readout and 0237 corrections

## Fresh device evidence

The complete unwrapped 0236 diagnostic ring contains 10,301 lines. All three
selected apps register on attempt one with valid matching proxies; the helper
exits zero. The user independently confirms that their icons now appear.

Performance is still poor: 217 of 260 presentation intervals have zero swaps
(startup and idle included); the maximum interval is 5.1fps. This does not
contradict the user's much longer pauses. Of 64 captured command-buffer
results, 41 complete, 16 fail Unsupported, five fail NotReady and two fail
NoResources. Actual rejected line counts are 1204, 1230 and 1536, beyond the
previous 1024-vertex limit. An encoding failure cancels that command buffer;
increasing the presentation cap cannot repair the missing frames.

A real 1664-byte fragment publishes after 111.327s AIR translation and 13.451s
backend work. A later fragment remains waiting at the end of the ring; its
request is present and its private terminal status is absent. This does not
prove a compiler crash. Compiler output is bounded and stops before the end
of the run. Storage records 4.63GB read, zero errors and 917s cumulative active
time; parallel lock-wait totals must not be treated as wall time. The exact
source of all disk traffic is not identified.

There is no recorded kernel panic. PosterBoard twice hits
`!_stateLock_switcherConfiguration`; assetsd twice aborts with
`assetsd requires TCCPhotosService access`. Those faults, the later shader wait
and storage contention are separate unresolved findings.

## Consistent product identity

At the user's clarified request, A5XELTE now selects `iPhone10,5`, `D211AP`
and target `D211`. The board pairing is corroborated by the upstream
[libirecovery device table](https://github.com/libimobiledevice/libirecovery/blob/master/src/libirecovery.c).
One source supplies both newly generated trees and repacked BOOT trees.
The inherited `iPhone10,3`/D22 fields are replaced. Samsung compatible strings,
MMIO, CPUs, memory, display geometry and input nodes continue to describe the
real Exynos hardware. New A5 trees do not import optional D22 /product data.

Patch 0214 excludes A5XELTE from macOS's process-dependent iPad8,6/arm64
compatibility branch. `hw.machine` and `hw.product` now derive from the same
ADT model; `hw.model` and `hw.target` derive from the first compatible board.
Other macOS boards retain their original branch. The startup helper records
these four values once. This changes the port's configuration, not universal
application bundle device-family metadata or the historical SWEET donor.
Actual iOS/UI identity after reboot still needs the new runtime receipt.

## 1600-vertex native layout

Generic and reflected misc paths admit up to 1600 vertices. Counts up to256
retain the original output offsets. Larger output planes use aligned actual
invocation sizes. Above1280, the position plane starts at0x2c000 instead of
0x30000, borrowing16KiB from the CPU snapshot arena. Even position, point size,
two UVs and full colour for1600 vertices fit below0x40000. The job allocation
and kernel ABI stay256KiB.

The input and index writers use the reduced arena boundary. Oversized actual
vertex snapshots use the existing bounded GPU-buffer upload planner and remain
retained through terminal fences. No output pixels are produced on the CPU,
no draws are dropped, and overlapping planes are not allowed. Older separate
path/blur/home layouts retain their256-vertex bound; the separate index-count
bound remains1536.

Selector18's NotReady, NotFound and NoResources resource/epoch preflight errors
cannot start a job in this kernel ABI. They no longer quarantine every captured
resource as if DMA were uncertain. Unexpected transport errors, malformed
replies, IO errors, GPU faults and timeouts still retain uncertain resources.
This corrects a real ownership classification defect; it does not yet prove
the cause of every NotReady result or a higher device frame rate.

## Verification

Fresh/repacked ADT identity, unchanged hardware children, rejection of foreign
or duplicate identity, and actual kernel preprocessor selection pass. Genuine
shader descriptor tests cover all six static/dynamic pairs, lines/strips and
triangles through1600, disjoint output planes, external input and the1601
rejection boundary. Metal wrapper tests additionally verify real vertex bytes
in uploaded BOs. Resource-retirement tests cover preflight rejection versus
uncertain timeout/IO/malformed-reply ownership. These use mocked kernel
transport and are not physical GPU pixel or FPS results.

## BOOT artifact

The final signed provider is999,968bytes; the worker/backend and all original
stock application contents remain exact. The374-file compressed payload passes
the actual kernel installer preflight under ASan/UBSan. Full XNU make exits0.
The25,800,720-byte BOOT matches every linked kernel segment and all374 embedded
file CRCs. The actual ADT differs from0236 in exactly four root identity fields;
all hardware children remain exact. Loader, DTBH and boot arguments preserve
the verified chain, including4CPUs,736MiB,32-sector storage, quiet functional
touch and native GPU. These are build checks; runtime results remain pending.
