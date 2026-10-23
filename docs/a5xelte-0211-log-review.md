# 0211 phone readout: blur factory fixed; compositor waits for next stage

## Verdict: confirmed repair, incomplete UI progression

Read-only SYSTEM capture: flush79,444,650 recorded bytes,5,322 decoded lines,
no overwrite, kernel panic or backboardd crash record. The exact newly awaited
function request and compiler-workspace metadata/log size were also read from
HFS. No device write or reboot occurs during this analysis.

| Private decoded log evidence | Observation |
| --- | --- |
|263–269 | New actual104 BGRA8 and108 RGBA16 indexed GPU cases pass4096/4096 elements each, terminal fences81..84, MMU0 and immutable guards. Total37/41; same four earlier failures remain. |
|3696 | Previously fatal narrow_blur_19/profile104 descriptor with missing RT1 is accepted: internal inactive color1 writeMask0. No subsequent live104 Query17/Submit18 is captured. |
|3491–3703 | Five dynamic fragment stages are accepted, including2448-byte zero-input fetch with static602 and another912-byte fragment with603. |
|1103,1245,3395 | Three recorded live command buffers complete status4/error0, including602/603/604 native work. |
|3705–5318 | Backboardd awaits a newly forwarded fixed_frag_lph_cph function request. It remains the same PID58 and emits no render-pipeline rejection/abort in this capture. |
|4794–5317 | Compiler parent reports RUNNING metal2vulkan process group,10.0..121.4seconds. No completion, SPIR-V validation, failure or native publication is recorded. |
|4243–4309 | Independent PosterBoard SIGTRAP persists: no home/lock poster paths and !_stateLock_switcherConfiguration assertion. |
|5302–5304 | eMMC179,751 requests /3,778,362,880readbytes /142,126,080writebytes, errors0. Input events still reach the HID queue. |

## Exact awaited request

The request is a typed fragment specialization with58 named constants, two image
inputs (Texture3/4, sampler0/1), texture_function5, blend_function54, LOD bias and
framebuffer_fetch constant enabled. The actual optimized Mac reflection has two
sampled textures and no live input attachment; constants alone do not establish
a tilebuffer read. Request identity and raw data stay in private artifacts.

The sole active .stage-work directory contains only packing0.json,
ordered-color0-profile.json and a zero-byte air.log; no shader SPIR-V, reflection
or native output exists there. The captured RUNNING label is printed by the
parent around a spawned worker, not by the translator. Therefore it establishes
an outstanding process group, not verified compiler progress or an infinite
shader-translation loop. No completed/failed result should be inferred after
the user returned to recovery and stopped the iOS processes.

Replaying the exact58 constants with the matching host translator, profile,
packing and stock library produces vertex/fragment SPIR-V and passes
spirv-val vulkan1.2. This narrows the phone blocker toward worker startup/exec,
loading or scheduling/I/O; it does not identify which one, prove phone compiler
completion, or establish a native Mali program/pipeline/GPU result.

## Next concrete step

Inspect child-worker startup and exec before assuming shader compilation itself
is slow; the current parent progress log lacks PID/exec/child CPU checkpoints.
The captured request can also be compiled and validated on the Mac, then fed
through the authenticated publication/cache path. Preserve real reflected resource
checks for the two-texture stage. Separately investigate PosterBoard state; the
previous RT1 mismatch is no longer the recorded first blocker.
