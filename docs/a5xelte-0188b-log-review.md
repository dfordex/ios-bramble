# 0188b: live pipeline accepted; indexed draw selector and compiler CLI block progress

The complete read-only SYSTEM capture is flush57:204,586 recorded bytes,
2,367 decoded lines /204,341 decoded bytes, without overwrite.

## Successful boundaries

| Boundary | Actual evidence |
| --- | --- |
| Installer |Line265: complete files15/sync0; provider612,400bytes, runner127,664bytes and both new generic tool/recipe destinations installed. The0188 preflight defect is cleared.|
| Fragment |Lines1007/1195: `fixed_frag_lph_cph`, profile601,58 typed constants accepted.|
| Vertex |Lines1008/1196: `fixed_vert_lph_spc`, profile602,4 typed constants accepted.|
| Actual live pipeline |Lines1010/1198: profile602 accepted with actual packing0, one BGRA8 RT0/writeMaskAll, no blending, sample1, no depth/stencil. The prior candidate target/blend assumptions now match the observed request.|
| Automatic request delivery |30 receipts:15 newly queued and15 deduplicated, representing15 unique request IDs. The actual602 pipeline is one of them.|
| Independent GPU tests |21/21 evaluated/pass,44 terminal fences, all header1/MMU0.|

Actual live602 request identity is
`7cbc02484873153d7538a300110e680fc9460c8a790ee2d1bac573fc92b244b5`.
It is first queued at1009 and deduplicated at1197. These are request receipts,
not successful compilation or GPU submissions.

## Blocker1: missing indexed drawing entry point

Immediately after the first accepted live pipeline, backboardd calls:

```
drawIndexedPrimitives:indexCount:indexType:indexBuffer:indexBufferOffset:
```

Lines1012–1015 explicitly report an unrecognized selector on
`A5MaliMetalRenderEncoder`, followed by an uncaught NSInvalidArgumentException.
The second process repeats the same exact selector failure at1200–1203.
Heap evidence also recovers the same text in subsequent crashes.

There are21 backboardd signal6 crashes, all namespace2/code6 with the same
ten-entry backtrace. The runtime throw stack contains QuartzCore0x18889fb90;
subtracting shared-cache slide0x5d4000 gives preferred0x1882cbb90. The source
only implements drawPrimitives and its one-instance overload; it has no
drawIndexedPrimitives method. The earlier vertex-specialization error is gone.

There is no recorded commit, native phase, Query17 or Submit18. The113 frame
windows sum600,973ms with zero swaps, shown frames or CPU/GPU presentation bytes.
The next rendering implementation must perform genuine indexed geometry
submission, including index-buffer ownership/offset/type/range handling. A stub
that swallows the selector or pretends to complete drawing would not fix it.

## Blocker2: installed translator does not accept the runner's CLI

The new root service starts and request spooling works. It then fails in its
legacy selftest stage before reaching the automatic request scan:

```
metal2vulkan: FALLBACK (unrecognized option `--no-timeout` ...)
```

This is printed at1443 and2130. The associated command status512 is exit2;
the parent reports compiler/validator failure at1442/2129. KeepAlive restarts
the service, producing three service-start receipts in the capture. There is
no PUBLISHED, cache-bound or automatic UNSUPPORTED-result marker.

Both legacy compilePair and the new602 worker pass `--no-timeout`, but the
packaged optimized iOS translator rejects it. Thus on-host translation and
signing success did not validate this installed CLI compatibility. The runner
and iOS translator must agree on that interface while preserving the user's
unlimited compile duration, and the same request must reach publication before
claiming on-device automatic compilation/binding.

No kernel panic is captured. The independent passing GPU cases do not establish
that iOS sent a compositor draw in this boot. No new image was built or written
during this readout.
