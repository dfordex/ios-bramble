# 0213: native untextured fragment admission

## Exact device failures

0212 reached the visible clock screen and physically passed the new two-image
GPU oracle. Its next two backboardd pipeline aborts concern successfully compiled
stock fragments with no sampled textures, rejected by a textured-only IO gate.
Both exact typed requests were replayed on the Mac; SPIR-V validates, and native
output matches the phone publication byte-for-byte. These native programs remain
private and are not replaced by authored shaders or success stubs.

| Actual fragment | Native interface and resources |
| --- | --- |
|2240bytes/tag8/7registers| One float4 color interpolant at nativeVAR0, ordered color0 attachment read, UBO0minimum72 and logicalFragmentBuffer1/nativeUBO2minimum136; no textures/samplers. |
|176bytes/tag5/2registers| No interpolants, textures, samplers or actual attachment fetch; only UBO0minimum72. Optimized NIR writes transparent zero. |

## Implementation

Add a separate authenticated FragmentColorOnly shape. The emitter maps FSVAR0
to the actual color export: compact602 at varying-data0, full603 at+0x1000, or
dual-UV vertex at+0x2000. Input attributes, export types, native lane/base masks,
render target, side effects and live uniforms remain checked. No UV/texture or
sampler is fabricated for an untextured shader.

FragmentNoInputs now describes the actual empty interpolant interface without
requiring framebuffer fetch. The independently authenticated fetch flag still
requires exactly the real ordered input attachment. No-input/no-fetch draws have
zero texture/sampler/varying pointers and zero FS varying count, while the real
UBO/push table remains. ColorOnly has one float4 varying and no sampled-resource
pointers. Incompatible flags, slots, bounds, aliases, side effects and attachment
contracts continue to fail before native submission.

The existing renderer accepts the resulting actual factory profiles; no new
Metal API method or global error suppression is needed. The live launchd job
still provides AttentionAwareness through backboardd. Its0212 invalid-proxy
exception followed that provider's Metal abort; no attention daemon/job/sandbox
change is introduced. See [0212 crash chain](a5xelte-0212-attention-crash-chain.md).

## Local verification and physical tests

The exact58-constant MTLLibrary/newFunction path, combined pipeline, native
Query17/Submit18 mapping and independent emitter pass for copy/source-over.
The2240-byte case covers compact602/full603/actual dual-UV2592 vertex color
buffers;176covers602/603. Tests check native code, texture/sampler pointers,
export planes, actual uniform bytes, destination read/write alias and completion
fences. Malformed IO/base/bit widths/output, missing or fabricated fetch, sample
liveness, incompatible flags, aliases and short uniform windows reject. Host
transport is mocked and establishes no physical pixel result.

All18 pre-existing native wrapper binaries/final Cortex-A53 API compile pass.
Production provider/probe build, strict signatures and225/17 code hashes pass.
Independent read-only ABI/emitter review finds no blocking mismatch. The compiler
helper is unchanged from the phone-verified0212 build.

Two new physical pixel cases use actual static602 vertex and actual2240/176
fragment bytes. The ordered-color case authors two non-overlapping quads with
alpha1/4 and3/4 and sets the real cubic-luminance bias to one. Starting BGRA is
32/64/96/128; the independent optimized-NIR oracle predicts56/80/104/128 on the
left and104/112/120/128 on the right. The constant case starts nonzero and expects
transparent zero. Both4096-byte oracles are separate from input jobs. Previous42
cases remain, including the four known pixel failures; total44 pending device.

Four complete native publications are embedded through the strict existing
cache installer.31-file payload40,707,850raw/9,854,181packed bytes passes actual
production cache validation and kernel preflight. No whole root image transfer
is used. Actual prior2448-byte zero-input ordered-fetch and2592/1328-byte
pair regressions also pass against final source, including split-color and four
negative cache contracts. Repository validation203patches/41Python/10shell passes.

Full XNU compile/link/dSYM/strip/symsets completes exit0. BOOT31,776,784bytes
fits32MiB; loader/ADT remain identical to0212, and the exact signed provider,
unchanged verified compiler and all four complete publications are embedded.
It retains four tested CPUs and32-sector storage batches. Installation is recorded below;44-case/transition runtime results remain
pending.


## Installed0213

Sourceff396d7 was committed and pushed before installation. Recovery/model/TWRP,
BOOT p10 and32MiB capacity guards pass. Direct offset-zero write acknowledges
31,776,784bytes in2.24seconds, sync completes and reboot is requested. No BOOT
backup, post-write readback/hash or whole USERDATA transfer occurs. Test clock
screen progression, then single Home/Power transitions and read the44-case GPU
and backboardd/Attention connection results from the next recovery log.
