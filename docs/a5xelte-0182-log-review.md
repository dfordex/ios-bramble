# 0182 full log review and CPU/Metal regression — 2026-10-22

## Verdict: FAIL — incorrect advertised Metal texture limit blocks fullHD targets

The entire recovered SYSTEM window was reviewed: flush 58, 143,957 bytes,
1,776 decoded lines, no ring overwrite. This readout did not write any phone
partition. The six selected UI bundles installed and PosterBoard executed.
The Mali tests and an independent full-panel copy completed, but stock
backboardd never logged a Metal commit. Comparison with the working CPU path
and the exact iOS16 QuartzCore binary identifies a concrete provider defect:
`maxTextureWidth2D` was set to the panel width, 1080. QuartzCore uses that value
as the limit for both surface axes, rejecting the 1920-pixel height before
calling our texture factory or rendering a frame.

## Complete capture results

| Boundary | Evidence | Interpretation |
| --- | --- | --- |
| Platform | Four CPUs initialized, SGI1 verified; normal HFS journal replay | No new CPU-start or root-mount failure. |
| Installer | Lines 234–302: payload preflight 0; live free 2,151,141,376 bytes, required 100,505,770; 13 existing files, 47 app writes; 225 directories; complete files=60 sync=0 | All six complete bundles restored through HFS VFS. No whole-root transfer. |
| PosterBoard | `exec PosterBoard` at line 1390; later AKS calls at 1562–1563 | Missing executable fixed; execution alone does not prove service readiness. No missing PosterBoard error remains. |
| GPU suite | 21 evaluated / 21 passed / immutable=1 | Private shader/resource regressions still pass. |
| GPU fences | 48 terminal records, successful header 1 / complete 1 / MMU 0 | 44 test fences, two live-surface sample fences, two final-panel-copy fences. No stock Metal draw proven. |
| Metal device | Stock device accepted; two backboardd queues and warmup cb1 created; 14 pipeline acceptances across 12 profiles | Device/initial preparation succeeds. No encoder, texture, sampler, buffer or pipeline rejection is logged. |
| Stock submission | No commit, Query17, resource-op or Submit18 receipt | Missing transition precedes a live draw submission. |
| Surface / presentation | Surface23 is 1080×1920 BGRA, row stride 4352; sample45/46 passes 256/256; full-panel copy47/48 succeeds | Final GPU-to-DECON transport works for this surface, independently of stock Metal rendering. |
| Aggregate framebuffer | 114 windows / 609,021 ms; 6 swaps, 5 presentations, 1 superseded; one CPU and one GPU copy of 8,294,400 bytes each | The window is not zero framebuffer activity. Default-console restores are not compositor frames. |
| Processes | One backboardd and one SpringBoard exec; no CRASH, exception termination or kernel panic | Current failure is not an observed backboardd crash loop. |
| Other activity | Later services continue; 192 xpcproxy, 13 bluetoothd and 17 fairplayd.H2 starts | Repeated launches exist, but xpcproxy is also the normal launcher. No causal link to the surface rejection is established. |

Existing boot warnings include absent SEP, unavailable preboot firmware/factory
bind mounts, user-session/persona notifications, unsupported virtual-random
loading and swap-file opening. AKS selector10 repeatedly returns Unsupported
for securityd; profiled31 and SpringBoard32/8 are also unsupported. Sandbox
privilege denials and duplicate HID plugin classes remain. These issues must
not be relabeled as the demonstrated Metal target-size defect. There is no
new missing-library or missing-UI-executable error in this capture.

## Why CPU drawing worked and the Metal path does not

Static evidence below uses the unmodified iOS16 QuartzCore image, UUID
`9e40b2eb-260c-3af1-ae45-a1a551a8c1b9`. Addresses are preferred image VAs,
not a claim that a particular runtime PC was sampled.

| Exact code | Contract / consequence |
| --- | --- |
| `EAGLServer::renderer`, `0x1882eaf9c–0x1882eb038` | Creates a Metal context, constructs and warms its renderer, then stores it on the display. A nonnil Metal renderer takes this path instead of the fallback at `0x1882eb040`. |
| `_MTLDevice maxTextureWidth2D`, `0x181a1a0e8–0x181a1a0fc` | Returns the provider's actual limits field at offset 0x84. |
| `new_metal_context`, `0x188488724–0x188488734` | Calls maxTextureWidth2D twice and stores the same value at context+0xa28 and +0xa20. Height is not used for this cap. |
| `0x18848875c–0x18848876c` | Clamps context+0xa20 to min(widthLimit,8192). The old value remains 1080. |
| `MetalContext::get_surface`, `0x188346cf4–0x188346d14` | Reads the actual WindowServer surface width/height and rejects either dimension above context+0xa20. Thus 1080×1920 fails the height check. |
| Oversized return, `0x188346e74–0x188346f0c` | Takes the too-large diagnostic branch and returns nil before viability/import/texture creation. Its CoreAnimation logging is not guaranteed to appear in stderr. |
| `make_buffer_current`, `0x1882e1908–0x1882e1958` | Calls get_surface, propagates nil as false, and never establishes the render destination. |
| `Display::render_display`, `0x1882e1cc0–0x1882e1d6c` | Calls the make-buffer-current virtual slot; false at 0x1882e1cc4 skips Renderer::render at 0x1882e1d38. No new draw command buffer or commit is required on this branch. |
| `create_surface_from_iosurface`, `0x188366e44–0x188367068` | A separate entry has the same two-axis cap and nil return; it is not asserted to be a direct callee of get_surface. |

Warmup's 776×24 resources fit 1080, explaining successful preparation despite
this first-frame blocker. The former software compositor does not create its
target through MetalContext::get_surface, so this provider limit cannot reject
its fullHD target. Once Metal initialization succeeds, absence of a frame is
not enough to make QuartzCore automatically select the former software path.

This is a source-proven deterministic rejection for a fullHD target. The saved
log contains no get_surface runtime entry/return trace; confirmation that it
caused this exact boot's stall requires the isolated corrected-device trial.
It is not proof that every later shader/API contract is complete.

## Framebuffer ABI comparison rules out a different proposed cause

All 21 unique captured backboardd framebuffer selector/input/output/status
shapes match the functioning CPU capture0122. Exact iOS16 IOMobileFramebuffer
code confirms selector6 is SwapWait (three scalars), selector55 is SetMatrix
(one scalar plus 72 bytes), and SwapEnd5 takes 0x46c/1132 bytes. Both logs match.
VSync callback registration is selector72/type5; neither capture registers it.
The absent callback receipt alone is therefore not a Metal-only regression.
SwapWait and SetMatrix retain incomplete implementation semantics, but this
comparison does not justify changing them as the current root-cause repair.

The AGXAccelerator lookup returning none is likewise not proof of failed Mali
discovery. The inspected AGX lookup at 0x18853d900 belongs to optional AGX timing
hints; its missing-device branch returns without suppressing normal rendering.
Do not register a fake AGX service to mask the texture-limit defect.

## Correction and verification

P1: advertise supported logical texture capacity, not panel dimensions.
The provider now reports 2048×2048, matching the existing 2D allocator's
per-axis bounds, and logs `max2D=2048/2048` at initialization. No panel geometry,
framebuffer selector, shader, queue or resource-limit bypass is changed.

The actual updated initLimits method was compiled in a private host fixture;
the independently recovered QuartzCore two-axis predicate reproduces rejection
of portrait and landscape fullHD with the prior1080 cap, accepts both and
2048-square with the corrected cap, and still rejects2049. Existing real-Mac
IOSurface resource tests and iOS compilation with warnings as errors pass.
The complete provider builds for plain ARM64 iOS16/Cortex-A53 and passes4KiB
signature-page verification. These are local checks, not a phone frame result.

Next device evidence must connect a non-warmup command buffer to encoding,
commit → Query17 → Submit18 → terminal fences and the resulting display surface.
Any newly reached unsupported shader/resource operation is a separate concrete
next defect, rather than a reason to claim general rendering already works.
