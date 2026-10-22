# 0181 recovered log review — 2026-10-22

## Verdict: CONCERNS — copy rejection cleared; stock frame submission absent

Read-only SYSTEM recovery yielded flush39,112733raw bytes and1398decoded lines,
without ring overwrite. Entire capture reviewed; raw logs remain private.
No device partitions were written during this readout.

## Results against0180

| Evidence |0181 result | Meaning / limitation |
| --- | --- | --- |
| GPU oracle suite |21evaluated/21passed/21cases, immutable1 | Actual T720 oracle pixels preserved; no compositor claim. |
| Terminal fences |44logged, every complete1/header1/MMU0 | All test jobs finish; no post-suite presentation/native jobs recorded. |
| Installer |502224-byte provider written,13files complete/sync0 | New0181 provider installed. |
| Backboardd cb1 | Created, no encoding/copy/texture reject | Previous e00002c2copy error absent. |
| Scratch surfaces | Two8x8BGRA plus two8x8BGR5A1 allocations | Same-texture two-job workaround is reached during encoding; no GPU execution claimed without commit. |
| Pipeline factories |14accepted calls/twelveprofiles | Same warmup/preparation profiles; not submitted draws. |
| Probe | STOCK DEVICE ACCEPTED | Device discovery works; not proof of a frame. |
| Commit/Query17/Submit18/resource-op receipts | None | No observed stock submission attempt, successful or failed. |
| Backboardd/SpringBoard execution | One each;noCRASH/kernelpanic | Not an observed crash loop. Three key records include initial GPIO plus two keydowns/HIDdelivery. |

All previous typed1D allocations still appear, including3072R16Uint,4096R16Float,
1024/4096R32Float and1024RG32Float. Green compiler verification/DONE repeats.
The two added SPI forwards have no device entry receipt, so this replay does not
prove QuartzCore called either forward.

## Frame path does not reach GPU presentation

Backboardd allocates full-panel IOSurface23, but no live-surface probe, full-frame
GPU copy or fences45+ follow. The one logged full-panel swap names console
surface1. Its performance window has gpu_source1, zero GPU/CPU bytes and zero
fallbacks. Source code in SweetFramebuffer::present counts gpu_source when the
lookup is absent or equals the framebuffer's own console surface; it is not a
GPU execution error. Later windows report only ineligible/rectangle skips.
Across78windows (416340ms summed intervals), swaps total4/shown3, while all
presentation byte counters remain0. Do not interpret shown3 as three drawn
compositor frames. The capture is different from0180, whose independent
surface19→panel copy did execute.

## Why there is no stock drawing request yet

The current evidence places the missing transition before stock commit, not
inside a submitted GPU job. Only the known warmup cb1 is created. Warmup itself
does not commit. QuartzCore MetalContext::flush(bool) at1882e7ccc checks its
active buffer atcontext+0xb38 before stopping encoders and invoking either
commitAndWaitUntilSubmitted at1882e7d18 orcommit at1882e7d78. No entry receipt
exists for either path in this capture. It remains unknown whether flush was
never reached, its active buffer was nil, or upstream display/render scheduling
is waiting on another dependency. Static gates are not runtime proof.

Prioritize tracing the first non-warmup render/frame scheduling transition and
its display target, rather than treating private passing GPU jobs or an AGX
lookup0 as evidence that the UI command queue is running. Existing conditional
unsupported geometry/views/ordered-path interfaces remain possible later gaps,
but none appears as an encoding error here.

## Additional concrete system issue

At launchd uptime approximately6m19s, com.apple.PosterBoard fails because
/Applications/PosterBoard.app/PosterBoard is missing. This is a real missing
userland executable in the reduced root, not a shader compilation failure.
Whether it blocks this compositor's first frame is not established; inspect its
root manifest/dependency before treating it as the primary cause. Later
securityd AKS selector10 still returns Unsupported;fairplayd.H2 starts12times and
xpcproxy162times. The log does not establish a causal link from these service
issues to absent Metal commits. Later services and key events keep progressing.

## Next observation

Instrument the first real display/render request, source IOSurface selection,
and non-warmup buffer/flush entry, preserving exact return/error contracts. Check
the missing PosterBoard component against the reduced root manifest. A true
submission must produce commit→Query17→Submit18 and actual terminal fences;
current logs do not provide it.
