# 0181 native copy and submission compatibility

## Verdict: CONCERNS — implemented and built; device replay pending

The0180 capture proves21GPU pixel oracles but no stock command-buffer commit.
Its first encoding error is a texture copy. This change repairs a concrete
same-level-copy guard and two statically verified QuartzCore SPI entry points.
It does not establish that these are the only remaining compositor requirements.

## Evidence and changes

| Severity | Finding / source | Change / verification |
| --- | --- | --- |
| P1 | `A5MaliNativeTextureOps.m`, encode: whole mip byte-window aliasing rejected even disjoint rectangles. QuartzCore warmup copy loop18847f2f8..18847f34c selects same texture in its first combination. | Same-level nonoverlapping rectangles use original→temporary→original GPU jobs; exact self-copy does no work; overlapping rectangles remain explicitly rejected. Different nonoverlapping mip windows keep direct submission. |
| P1 | QuartzCore MetalContext::flush(true),1882e7d18 calls BOOL commitAndWaitUntilSubmitted; method absent. | Real commit and waitUntilScheduled, returning status/error from actual submission. Never fabricate a fence. |
| P1 | QuartzCore texture binding1882cb33c calls setFragmentTexture:atTextureIndex:samplerState:atSamplerIndex:, absent. | Delegate actual texture/sampler setters, preserving validation and nil-unbind semantics. |
| P2 | Full-copy first-error omitted exact guard/descriptor. | Saturating bounded scalar diagnostics record contract/backing/level/bounds/alias/overlap/scratch allocation and public slice/format rejects; no addresses/tokens/contents. |

Apple documents unexpected behavior for overlapping same-texture copies; this
backend explicitly rejects those rather than sending an unsafe sampling/render
alias to Midgard. Distinct rectangles now use real private GPU backing, retained
by queued operations through actual terminal fences. The public command encoder
records any enqueue failure and suppresses submission of that failed buffer.
Reference: [Apple texture blit contract](https://developer.apple.com/documentation/metal/mtlblitcommandencoder/copy(from:sourceslice:sourcelevel:sourceorigin:sourcesize:to:destinationslice:destinationlevel:destinationorigin:)?language=objc).

## Verification

PASS: real Mac RAM-only IOSurfaces plus mocked kernel transport prove two genuine
profile500 descriptor chains with different input/output tokens, full-temporary
copy then partial-original preload, actual returned terminal fence, first/second
job failure stopping and cleanup. Exact no-op and overlapping-region rejection
produce no GPU query. Existing nine-mip mapping/epoch and Memoryless lease tests
also pass. Evidence:/private/tmp/a5mali-0181-texture-ops.log.

PASS: all five native-render suites (render,misc,clear,path,diagnostics), plus
Cortex-A53 iOS16-Werror compilation. New cases call the two exact SPI selectors,
including bad fence returningNO, independent async submission target wait, nil
unbind and invalid sampler slot. Evidence:/private/tmp/a5-native-render-0181-forward-test.log.

PASS: signed502224-byte provider and fresh XNU build including dSYM/symbols.
The first build linked successfully but sandbox denied /dev/fd during dSYM;
rerunning the same build with local build permission completed exit0. Private
BOOTcandidate28749840bytes fits32MiB. All21existing GPU oracles/shaders remain
unchanged. These checks do not prove phone stock rendering.

## Remaining conditional limits

| Source evidence | Limit | Current0180 attribution |
| --- | --- | --- |
| QuartzCore1882cbbb4 / drawPrimitives instanceCount | instanceCount>1 explicitly unsupported | Not recorded as first error |
| QuartzCore1882cbb8c / cached indexed draw IMP | General indexed drawing unimplemented | Not recorded as first error |
| QuartzCore1882e5264,188357668 / texture view | Format/sRGB texture-view selectors missing | Statically reachable, not logged |
| QuartzCore188483ffc / bytes-no-copy factory | Explicitnil return | Statically reachable, not logged |
| Authenticated original path_blit profiles | Ordered multi-attachment/framebuffer-fetch path not executable | No committed invocation observed |

The0180cb1 matches warmup, which never commits. Even an error buffer would log
commit withsubmit0 if commit were invoked; there was no such receipt. Therefore
neither the self-copy error nor the two missing SPI methods are proven to be the
sole reason for absent stock submission. There is no evidence of a submitted
stock GPU job timing out. Waiting on the same serial submission target remains
unsupported (as for existing waitUntilCompleted); no such caller pattern is
established in0180. Next device replay must distinguish warmup encoding from
real commit→Query17→Submit18→terminal fence and the presented compositor frame.
