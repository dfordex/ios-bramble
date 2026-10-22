# 0198: actual colored GPU output reaches the panel

Read-only SYSTEM recovery has flush82 and all324,896 recorded bytes, without
overwrite:324,651decoded bytes/3,524lines. Raw logs and full captured shader
requests stay outside git. The phone was in TWRP before this readout.

## Repaired boundaries verified on the device

| Boundary | Recovered evidence |
| --- | --- |
| Actual UV contract | Lines1039/1168:VB3=(1,1,0,0), transformedUV0..1, normalized sampler, nearest min/mag, no mip filter |
| Actual603 GPU output | Lines1045/1174:29,457nonzeroRGB pixels in the complete2,073,600-pixel target23; opaque alpha throughout |
| Source texture |194×237texture had29,457nonzeroRGB/alpha pixels; unlike0197, its colored draw now yields colored output |
| Presentation ordering |7incoming/7selected SwapEnd records, zero replacements; surface23 records1/3 both reach presentation |
| Wait completion |22logged SwapWait calls all return stateShown/result0, including the real nonzero IDs |
| Panel transfer |Record1 copies8,294,400bytes on CPU; record3 uses GPU fences47/48 and a full-panel copy |
| Panel comparison |Line1189:4,096samples,60nonblack; RGB/alpha source-versus-panel mismatches0 |

The first mask0x80000007 uses CPU fallback; the later single-layer mask1
qualifies for the GPU copy. Subsequent surface1 records alias the panel and
need no copy. Records5/6 carry no surface IDs; record7 selects the panel alias.

This proves actual nonblack compositor GPU output and a completed GPU-to-panel
transfer with a matching sampled grid. It is not a comparison of every panel
pixel, complete UI support or a measured sustained UI render rate. The user's
photograph independently shows a visible, vertically inverted Apple logo.
The negative-Y viewport correction is prepared in0199.

No kernel panic, GPU fault, uncertain DMA or failed SwapWait appears. All21
private GPU cases pass. Five runtime ABI audit summaries report zero errors.
The worker retires the exact old pixel-coordinate603 publication at line1032;
new603uses its embedded normalized program. No new publication is recorded:
AIR exits0 after73.923s, then Midgard remainsRUNNING at the last522.7s stage
heartbeat. This run therefore does not claim completed phone603 recompilation.

## Later backboardd crashes: new fragment specializations

There are nine backboardd SIGABRT records. Every recorded reason is namespace13,
code7: `Metal failed to specialize fragment function`. The captured function
requests have eight complete log blocks, representing two distinct variants
of `fixed_frag_lph_cph`, each with58named constants,0indexed constants and no
truncation. Rejected-request and repeated diagnostic blocks are not nine
independent shader identities.

| Distinct variant | Difference from accepted603 | Complete blocks |
| --- | --- | --- |
| First |UChar `fc_texture_function`:01→03 |2 |
| Second |UChar `fc_image_function0`:00→1d(29) |6 |

All other57typed constants match the known603 specialization in each variant.
The failure occurs during fragment function creation, before a new complete
pipeline contract is available. The provider explicitly rejects these unknown
variants, and QuartzCore aborts. The remaining crash reasons are retained even
after bounded userland tee output stops giving complete function details.

The next shader work is to translate these actual variants, inspect their
live resource/reflection/native contracts, add exact specializations and tests,
then observe actual vertex, render-target, blend and sampler state. Reusing603
machine code for the changed constants would not establish their semantics.
0199contains only the viewport correction; it does not admit these new shaders.
