# 0212: two-image native stage and compiler exec evidence

## Captured blocker and native compilation

0211 accepted the previously failing inactive RT1 profile104, then backboardd
waited for a new two-image fixed_frag_lph_cph specialization. The phone compiler
parent reported RUNNING, but the sole child workspace had an empty air.log and
no SPIR-V/native output. This did not establish translator progress.

The exact typed58-constant fragment request now passes host AIR translation,
SPIR-V vulkan1.2 validation and released-Mesa Mali-T720 native compilation:
1328bytes, tag5, six work registers, TLS/WLS0. Its optimized native interface
reads Texture3/4 through independent sampler0/1, two UV interpolants and color.
The framebuffer_fetch function constant is enabled, but the actual optimized
program has no live input attachment. Constant values do not replace native
liveness evidence.

The corresponding four-constant fixed_vert_lph_spc request sets both coordinate
counts to one. It produces an authenticated2592-byte, tag5, seven-register native
vertex program with four input attributes and position/point/UV0/UV1/color
exports. It is published under its own exact request identity; the old single-UV
603 vertex identity and machine code are not relabeled. Raw stock inputs,
request bodies, shader captures and native publications remain private.

## Integration

The runtime needs a real second UV path, rather than reusing UV0 for both
textures. Native factory and emitter changes preserve the separate attribute,
varying, texture, sampler, push and UBO contracts. The captured fragment's
synthetic ConstantBlob is optimized dead: accepted native backend output rejects
surviving global/SSBO operations, and live UBO0 reads stay inside its actual
76-byte push range. Unknown descriptor sources remain rejected.

Precompiled stages are installed through the existing bounded HFS incremental
installer and read through the same authenticated publication/cache contract.
No complete USERDATA/root image is transferred. Cache publication integrity is
an offline input check, not a device BOOT hash/readback operation.

The compiler runner now records spawn, worker main entry, limits, exec attempt,
exec errno, observed child executable, scoped child/group CPU and memory, log
bytes and exit/signal result. It still has no wall-time cutoff. Real copied OS
executable and real ENOEXEC tests pass; the signed Cortex-A53 runner builds with
4KiB CodeDirectory pages. Fast children may exit before the executable polling
checkpoint, so exit0 plus output validation remains separate evidence.

## Verification and installation

All18 existing native wrapper binaries and the final Cortex-A53 API compile
pass. The production provider/probe build and strict ad hoc signatures pass,
with225/17 verified4KiB code hashes. The updated compiler helper separately
passes52 code hashes. The focused actual two-image cache/factory/emitter test
accepts both copy and source-over states using real distinct IOSurfaces and
independent sampler0/1. Kernel Query17/Submit18 are mocked in host tests; this
does not prove physical pixels or backboardd progression.

The new42nd physical pixel fixture executes the actual2592/1328-byte pair,
with separate patterned source images, distinct UV coordinates, nearest sampler0
and linear sampler1. The4096-byte independent oracle follows optimized NIR:
sample0RGBA * vertexRGBA * sample1Alpha. Expected pixels stay outside job inputs.
The previous41 cases are retained, including the four known failing cases.

The two production publications pass the real cache reader and native ABI
validation. Patch0203 limits incremental cache installation to a fixed root,
canonical64-hex identity children and exactly receipt/reflection/native triples.
Files install as root:wheel0444, directories0755; no-follow, same-filesystem,
regular-file, single-link and ownership checks also precede unchanged-file
comparison. The actual kernel preflight tests reject bad identities, traversal,
missing parents, modes/UID/GID, altered requests, byte corruption and unknown
publication content. Cache records are independent of the optional app gate.
Clean patch replay matches staged source exactly. Final25-file payload is
40,685,870raw /9,847,146packed bytes and passes real preflight. Repository
validation203patches/41Python/10shell and diff whitespace checks pass.

The final focused test also preserves single-UV split-color.xy/zw and admits
scalar-split UV1 with split color. Four rehashed metadata negatives reject unknown
synthetic sources, invalid blob bytes, fabricated live blob and out-of-push reads.
Independent read-only review finds no blocking resource/ABI/range mismatch in
the actual pair. Separate native location numbers are pipeline-local: the actual
AIR user keys/types match, so buffers are linked by their authenticated roles.

Full XNU compile/link/dSYM/strip/symsets completes exit0. Final BOOT31,741,968
bytes fits32MiB, retains0211 loader/ADT exactly, and contains the exact signed
provider, updated compiler and both complete native publications. It retains
four tested CPUs,32-sector eMMC batches and all42 GPU cases. These are offline
checks; no physical pixel/backboardd/home-screen result is claimed yet. The previous four pixel failures and independent PosterBoard
state assertion remain open.
