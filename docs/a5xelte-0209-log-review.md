# 0209 device readout: pixel paths pass, real pipeline/resources still reject

Read-only A5 TWRP capture: SYSTEM flush90, all1,023,694 recorded bytes recovered;
1,023,449 decoded bytes /9,608 lines. No overwrite or kernel panic recorded.
CPU4/4 and the new19-file payload (40,578,576 raw /9,815,469 packed) are present.
No device write, reboot, BOOT backup or BOOT readback occurred during review.

## New hardware evidence

All four new cases pass4096/4096 bytes, with both fences complete, MMU IRQ0 and
immutable guards intact (lines231–244): reordered u16/u32 indexed blur and the
actual2448-byte no-texture fetch full-target / same-job overlap. Suite result is
31/35 (line245); the same four older cases remain failing. This verifies the new
low-level emitters on Mali, not all live compositor bindings.

## Remaining live blockers

1. Line3635: actual profile100 indexed draw rejects before submission:
   primitive3 / u16 /54 indices /offset4848 /buffer262144 /ready1,
   reason=pipeline-or-resource-contract. The new JM index tests pass, but the
   real sampler/texture/attachment/binding contract is still outside the wrapper.
   This combined reason does not identify which individual field failed.
   Source currently admits only BGRA8 sources and nearest/clamp sampler state;
   report these separately before declaring a particular resource the cause.
2. Line3700 accepts the actual2448-byte dynamic fragment;3701–3702 reject the
   combined pipeline with compiled stage IO outside the implemented QC ABI.
   The fresh published receipt is identical to0208: no inputs/textures/samplers,
   ordered fetch and UBO0/2. Thus the shader is compiled, but pipeline admission
   still fails. The host/physical tests paired it with vertex603. Real startup
   creates both602 and603 vertices; the factory permits only603..606 on its
   static vertex side. That is a concrete untested pairing gap, not yet proof
   of the vertex attached to the rejected descriptor. Capture actual stage
   identity and the individual ABI predicate before choosing the repair.

Backboardd aborts twice with namespace13/code4, Metal failed to build render
pipeline (lines3782 and6875). Other processes and GPU/presentation jobs continue.
The new low-level paths are verified, while these two live integration gaps
remain unresolved. No next image has been installed from this analysis.
