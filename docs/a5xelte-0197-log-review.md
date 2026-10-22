# 0197: colored input, black render target, and overwritten swaps

## Recovered phone evidence

The read-only SYSTEM capture has flush31 and all124,631 recorded bytes,
without ring overwrite: 124,386 decoded bytes /1,533 lines. Raw device data
stays outside git. There is no kernel panic or process crash in this capture.
The private GPU suite passes21/21; both Metal ABI audits pass14class mappings,
751methods and zero errors. These do not establish compositor pixel correctness.

The actual backboardd command buffers2/3/4 complete six native jobs with
status0, terminal header1 and MMU0. Scheduled waits return; all three completion
callbacks enter and leave. The HID queue temporarily accumulates events, then
its consumer head catches up and advances with later Home/power events.

| Actual operation | Input evidence | Complete output image |
| --- | --- | --- |
| Clear target23 | Transparent black clear | 2,073,600pixels, RGB0 /alpha0 |
| Profile602 in CB2/3 | Four black RGB Half4 vertices, nonzero alpha | 2,073,600pixels, RGB0 /alpha2,073,600 |
| Profile603 in CB2/3 | Texture194×237: 29,457/45,978pixels have nonzero RGB and alpha; four colored vertices; input UV0..1 | 2,073,600pixels, RGB0 /alpha2,073,600 |

Lines1049–1057 and1249–1257 establish the colored texture and the wholly
black603 result. This is a full-image count, not the earlier sparse grid.
602's black input explains its black output; the colored603 draw still needs
repair. A terminal fence alone did not establish a correct image.

## Presentation ordering

SwapEnd records are real client requests, not inferred targets:

| Ingress order | First pending request | Replacement before vsync | Selected |
| --- | --- | --- | --- |
| Lines1064–1075 | ID1, mask0x80000007, surface23 | ID2, mask1, surface1 | ID2/surface1 |
| Lines1262–1269 | ID3, mask1, surface23 | ID4, mask1, surface1 | ID4/surface1 |
| Lines1485–1491 | ID5, mask1, no surface | ID6, mask0x80000007, no surface | ID6/no surface |

Surface1 aliases the physical panel; surface23 is the distinct4352-byte-stride
render target. No GPU or CPU full-panel copy runs in this capture. The first
two colored-target presentation records are definitely superseded. The second
record is not proven to be a completion-only message, so discarding surface1
or substituting the most recent GPU target would be unjustified.

The framebuffer bridge currently returns success from selector6/SwapWait
without waiting. Its actual ABI and ordering need implementation/verification
alongside the shader fix; the log does not yet prove SwapWait caused these
particular replacements.

## Concrete shader mismatch found after readout

The stock translator's sampler state bit0 denotes **pixel coordinates**;
S address mode occupies bits5–7. The603 reflection's SpecId0 mask0x80000007
covers coordinate/min/mag bits, not S addressing. The old recipe incorrectly
documented SpecId0=1 as ClampToEdge and compiled a pixel-coordinate fragment.
The Metal provider accepts603 only with normalized coordinates and emits a
normalized Mali sampler. The compiled fragment and accepted sampler therefore
have incompatible coordinate contracts.

The old native fragment computes floor(UV)+0.5 and divides by texture dimensions.
The vertex stage first applies VB3.xy×inputUV+VB3.zw. 0197 did not record VB3,
so the exact sampled coordinates and whether this mismatch alone explains
every black pixel remain unmeasured. A new normalized specialization and bounded
actual VB3/sampler logging will verify this boundary in the next device trial.

The local release-Mesa recompilation of normalized SpecId0 values0/2/4/6
produces identical880-byte fragments. This covers the admitted nearest/linear
min/mag combinations; pixel-coordinate samplers remain rejected. The existing
phone cache must not restore the old976-byte fragment after this repair.

No new BOOT write was performed while recovering or reviewing0197.
