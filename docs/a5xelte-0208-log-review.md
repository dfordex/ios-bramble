# 0208 device readout: inactive RT1 accepted; zero-texture fetch stage rejected

## Result

**CONCERNS:** The previous profile100 missing-RT1 pipeline rejection is fixed on
the phone. Backboardd then aborts pipeline construction for a successfully compiled
fragment whose reflected resource/IO shape is outside the current textured ABI.
An indexed-draw Unsupported record is an additional independent issue.

## Capture

Read-only TWRP retrieval: SYSTEM flush54, all581,184 recorded bytes recovered,
580,939 decoded bytes /6,089 lines, no overwrite. FB intervals total568,985ms
(about9m29s). CPU4/4/SGI1 verified. New866,704-byte Metal bundle installed with
19-file preflight; no kernel panic is recorded. Raw log and shader files stay
in ignored local research storage. No device writes or reboot during analysis.

## Evidence and remaining work

| Evidence | Meaning / next step |
| --- | --- |
| Log3207 accepts profile100 with `internal BGRA8 color1 writeMask=0`. | Exact prior absent-RT1 factory request passes. No captured profile100 query/submit/fence; allocation and GPU execution of this auxiliary route are still unverified. |
| Log3208: cb6 `drawIndexedPrimitives:indexCount:indexType:indexBuffer:indexBufferOffset:` returns Unsupported (`e00002c7`). | A real indexed draw is rejected. Active pipeline/index arguments are not recorded, so its exact triggering gate cannot be proved. Source inspection confirms indexed calls route only to the misc encoder, excluding blur profiles99..108; the blur emitter itself accepts only nonindexed draws. Add the appropriate validated indexed route, with actual index spans and vertex bounds; do not silently ignore it. |
| Log3272 accepts the2448-byte `fixed_frag_lph_cph` stage;3274–3275 reject its composed pipeline with `compiled stage IO is outside the implemented QC textured runtime ABI`. | Compilation/cache loading succeeds; pipeline admission is the immediate crash blocker. |
| Exact on-device stage receipt and reflection: framebuffer_fetch=true, inputs=[], live_textures=[], texture/sampler counts0/0, one vec4 color0 output, UBO0 extent72 and uniform native index2 extent152. | This is an untextured ordered framebuffer-fetch fragment. It does not require interpolated UVs. `fragmentABI` currently requires at least one live texture and UV location32; the native resource gate independently rejects zero textures. Implement a reflected no-texture/no-varying path across admission, resource binding and native descriptors, preserving ordered color0 fetch and uniform bounds. Merely relaxing the first gate is insufficient. |
| Log3276 and5942, reasons3371/6057: two backboardd SIGABRTs, namespace13/code4, `Metal failed to build render pipeline`. | These are userspace pipeline failures; no kernel panic is recorded. |
| 38 logged miscSubmit18 successes (602:20,603:3,604:1,605:14),18 completed/error0 command buffers, eight4096-sample panel/source checks with zero mismatches. | Existing compositor routes still execute genuine GPU jobs and present matching sampled output. This does not establish home-screen progress or execution of the newly accepted100/65536 pipelines. |
| GPU suite27/31, unchanged four failures. | RAW204 blend and R8 scissor reconstructed fixtures, plus ordered-fetch noise and same-job-noise overlap remain open. Their terminal fences/immutable checks complete; pixel accuracy is not waived. |

The failing fragment constants include framebuffer_fetch=true, blend_function54,
image_function0=36, texture_function18, texcoord_count0=0 and plane_count0=0.
Its successful native cache record proves zero actual textures even though the
high-level constant table retains image-related function fields. Use native
reflection, not constant-name guesses, to construct the runtime shape.

One additional worker UNSUPPORTED receipt appears at5399. No corresponding
published directory exists in the compiled cache; its exact separate reason is
not inferred from that console line. The immediate crash's stage receipt was
successfully extracted and inspected.

## Next implementation

1. Generalize reflected dynamic stages to zero-texture/zero-input ordered-fetch
   shaders, with zero sampler/varying descriptors and real uniform bindings.
2. Resolve the indexed draw rejection; add bounded index support to the blur
   path where required and log the actual rejected profile/arguments.
3. Retest these paths and the four open pixel cases independently. Preserve
   existing exact shader, memory, queue and terminal-fence validation.
