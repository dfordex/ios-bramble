# 0187: fragment accepted, live vertex specialization blocks submission

Read-only recovery of the SYSTEM log ring produced flush31,156,093 recorded
bytes and all1,650 decoded lines /155,848 decoded bytes. No ring overwrite.
No phone partition was written and no reboot was requested during this review.

## Direct answers

- **Fragment accepted:** two explicit receipts say
  `accepted profile=601 function=fixed_frag_lph_cph constants=58`.
- **Stock iOS draw submitted:** no recorded commit, NativeQuery17, native
  submission phase or Submit18. Acceptance alone is not a draw.
- **Current blocker:** `fixed_vert_lph_spc` with four named constants is
  unsupported. All11 recorded backboardd crashes have namespace13/code6,
  `Metal failed to specialize vertex function`. The previous fragment failure
  is absent from the captured crash reasons.

## Live sequence

At decoded line962, backboardd creates full-panel IOSurface23:1080x1920,
BGRA, row4352, backing8,355,840bytes. At966 it creates command buffer2;
zero protection succeeds at967. Line969 accepts the actual fragment601.
Lines970–983 then reject and completely capture two identical requests for
the real specialized vertex name. The first crash header is at984 and its
full reason at1011. The second process repeats fragment acceptance at1120
and the same complete vertex request at1121 onward.

The actual vertex identity is therefore now observed. The earlier
`std_vert0_lph` program remains a host-compiled candidate, **not** the observed
stock vertex. Do not alias `fixed_vert_lph_spc` to it. Translate the requested
stock function with its real constants, inspect the surviving resource/layout
contract, and bind that genuine result before claiming live pipeline coverage.

| Constant | Metal type | Bytes | Raw value |
| --- | --- | ---: | --- |
| `fc_generic` | Bool53 | 1 | `00` |
| `fc_texcoord_count0` | UChar49 | 1 | `00` |
| `fc_texcoord_count1` | UChar49 | 1 | `00` |
| `fc_vertex_layout` | UChar49 | 1 | `00` |

All four captured request sets agree; each has named_count4, indexed_count0
and truncated0. `constants=1` means a supplied constants object, not one entry.
The exact machine-readable capture was retained privately outside Git.

Every crash shares the same ten-entry backtrace. Subtracting shared-cache
slide0x24b8c000 gives the first relevant QuartzCore PCs0x188486690,
0x18838125c and0x1882cbf64. The captured explicit vertex-specialization reason
is sufficient to identify the present failure boundary; this review does not
infer a successful pipeline, target/blend match or subsequent resource use.

## Other evidence and limits

| Boundary | Recovered result |
| --- | --- |
| Embedded provider |521,888-byte executable written; installer complete13files/sync0; provider loaded|
| Private GPU pixel tests |21/21 evaluated/pass, immutable1;44 completed fence receipts, all header1/MMU0|
| Pipeline receipts |37 accepted warmup receipts; these are not stock live commits|
| Kernel panic |None captured|
| backboardd crash family |11 signal6 headers,11 identical namespace13/code6 reasons|
| Full-panel presentation |63 metric windows; zero swaps/shown/copied bytes and zero CPU/GPU presentation bytes|
| Metric duration |335,657 summed ms, about5.59minutes|
| Native compiler helper |Cache verification, GREEN LINE and DONE; not compositor completion|

The independent GPU tests still prove their bounded pixel cases. They do not
show that backboardd reached a GPU draw in this boot. UI resources and the
2048x2048 limit permit the live path to reach specialization; the new vertex
failure occurs before the first recorded live commit.
