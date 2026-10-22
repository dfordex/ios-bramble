# 0196: input is drained, callbacks return, sampled native output is black

## Capture and observed boundaries

SYSTEM flush28 contains119,824 bytes, all recovered without ring overwrite.
Decoded text is119,579 bytes /1,487lines. No process crash or kernel panic.
Both target audits still pass14 mappings /751methods. Raw logs remain private.

| Lines | Evidence |
| --- | --- |
| 1006–1044 | Keyboard enqueue succeeds, shared head advances0→64→128→192; notifications increase, no full queue. |
| 1106–1163 | A temporary backlog holds head256 while tail advances. |
| 1167–1241,1449 | Head catches up1024 and continues to4096. Thus userland drains the queue; an attached-client count alone is no longer our only input evidence. |
| 1054–1089 | CB2 scheduled wait finishes at Completed; its one completion callback begins and ends. |
| 1275–1298 | CB3 likewise finishes wait and callback. |
| 1308–1321 | CB4 finishes wait and callback. There is no saved permanently blocked command wait/callback. |
| 1059 | Clear0 target surface23 has0 RGB/nonzero-alpha samples. |
| 1067,1075,1281,1289,1314 | All five following602/603 outputs have RGB0/4096 and nonzero alpha4096/4096. These are a64×64 sample grid, not a proof that every pixel is black. |
| 1090,1299 | The records actually selected for presentation reference default surface1. |
| 1119–1120,1301–1302 | Each two-swap burst shows one superseded record, zero copied bytes and gpu_source1; GPU/CPU presentation counts remain zero. |

Six real native jobs complete with status0/header1/MMU0. These fences do not
prove image correctness. The captured waits/callbacks and consuming HID queue
argue against the specific permanent scheduling/input stalls we tested, while
not proving every higher-level iOS service is responsive.

## Presentation source selection

`AppleCLCD::swap` keeps one pending record. A subsequent SwapEnd replaces it;
the vsync callback processes only the newest. `present` deliberately skips
copying default surface1 because it is already the physical panel mapping.
Surface23 is a separate4352-byte-stride render target. In0196 no completed
surface23-to-panel copy, live source probe or panel comparison occurs at all.

It is **not yet proven** that the superseded records select23: logging inside
present cannot reveal a record overwritten before present. Automatically
routing the latest render target would invent presentation semantics and can
overwrite legitimately updated panel content. No such workaround is applied.

## Shader/source audit

The602 color-varying and603 UV/Texture3/Sampler0/UBO bindings were compared
with the staged final native disassembly. No concrete index/offset defect was
established. For T720, released Mesa's **non-hierarchical** pan_flat_size path
applies:0x1c7 encodes1024×1024 bins and the1080×1920 header/full sizes are
0x200/0xa00, matching this emitter. Hierarchical formulas are inapplicable;
no speculative tiler-layout change is included.

## 0197 observations added

- First32 incoming SwapEnd records and first32 selected records include their
  swap IDs, masks and all four surface IDs. An overwrite also records the
  replaced pending record. Presentation behavior is unchanged.
- The first six successful native BGRA output surfaces (at most2048² each)
  get a full pixel count after terminal completion/cache reconciliation. This
  distinguishes a tiny missed image from a completely black target.
- Actual commit-time CPU vertex snapshots for602/603 report Half4 RGB/alpha
  bit-presence counts, position finiteness/zero-W and UV bounds. Buffer-backed
  Texture3 snapshots report all source RGB/alpha counts with their geometry.
  No source values are substituted and no actual screen image is logged.

The exact patch applies without fuzz and matches staged sources. The full
native mock transport suite and Cortex-A53 cross-compile pass. The pixel
ASan/UBSan regression now includes a single colored pixel missed by the grid
but found by the full count. These checks validate measurement behavior, not
an iOS graphics fix. Device results remain pending.

0197 local build: both complete XNU make runs exit zero; installer preflight
accepts16 files (39,515,630 raw /9,446,848 compressed bytes). Final BOOT is
30,308,368 bytes. No on-device success is claimed by packaging.
