# 0207 — ordered framebuffer fetch and startup service repair

**Verdict: CONCERNS — implementation and local tests; physical result pending.**

## Scope and confirmed failure

The complete0206 capture shows a real QuartzCore fragment requesting ordered
color attachment0 reads. AIR stopped at `FramebufferFetch`; backboardd then
aborted specialization. The device launchd cache confirms that backboardd owns
`com.apple.AttentionAwareness`. SpringBoard's4099 invalid-proxy exception follows
that server's abort. Adding a replacement AttentionAwareness daemon or swallowing
its exception would not repair the failed rendering operation.

## Rendering changes

- The worker derives a private translation profile with only the implemented
  ordered color-attachment capability. Its normal602–606 translation profile is
  unchanged. Actual SubpassData image reads lower to native color0 loads; released
  Mesa26.2.4 emits the Midgard tilebuffer wait/load instructions.
- Actual previously rejected code now translates, validates and compiles to
  4,672 native bytes, first tag8,14 work registers, two sampled textures, six UBO
  slots and no TLS/WLS. The eight-KiB reserved code regions bound this route;
  the shader entry uses its actual first instruction tag.
- Input attachment0 remains a tilebuffer resource. The runtime enables destination
  loads, preserves the real pipeline blend state and orders the existing released
  preload tiler job before the application tiler. It does not sample an aliased
  target texture or copy a CPU-rendered replacement into the target.
- Up to four live combined texture/sampler bindings use reflected Metal slots and
  independent native descriptors. The verified one-Texture3/Sampler0 layout is
  retained. The actual new request additionally samples Texture9 through a
  translator-decoded immutable nearest/repeat sampler; RGBA16F inputs retain
  their real format. Unsupported immutable states still reject.
- Fragment position occupies native input2 through the hardware FragCoord special
  buffer. UV stays input0 and optional color stays input1; positions are not
  substituted with UV or the snapped vertex output array.
- A logical two-byte uniform is copied as exactly two client bytes into a zeroed,
  aligned private snapshot for its four-byte native word read. The cache records
  logical and physical extents separately. Private GPU bindings are read through
  the already locked submission transport before padding; unchecked overreads
  or direct short GPU UBOs are rejected.
- Root publications validate code, typed reflection, immutable states, resource
  bounds and ownership. Compiler support generation2 permits one retry of an old,
  authenticated failed framebuffer-fetch request; completed stages and failures
  produced by this generation are retained.

## Startup services

Patch0202 supplies real bounded TCC generic extension issue/consume/release
operations, matching the device's iOS16 wrapper ABI and actual tccd flags0 call.
It checks the stock platform issuer identity/path, maintains opaque token and
positive handle ownership, populates output buffers and handles copy faults,
quotas, expiry, process exit and replay. It supplies transport after tccd requests
an extension; it does not override TCC's authorization decision. See
[startup service evidence](a5xelte-0207-startup-services.md).

The separate PosterBoard first-time-switcher assertion is not patched without
an established state/initialization cause. Removing backboardd's rendering abort
must be observed before classifying any remaining startup failures.

## Verification and artifact recovery

| Gate | Evidence | Limit |
| --- | --- | --- |
| Actual missing shader | Real worker AIR→validated SPIR-V→Midgard→root publication; loader accepts4,672-byte stage | Host run, not compositor completion |
| Dynamic cache | Ownership/integrity/resource tests plus ordered-fetch positive/negative metadata cases; iOS compilation | No physical GPU |
| Runtime descriptors | Independent textures, immutable state, sparse slots, half4 input, FragCoord, short-uniform padding, actual entry tags and rejection cases | Structural checks |
| Compiler lowering | Authored SubpassData stages and invalid binding/offset/type/ordering cases | Native generation, not device pixels |
| TCC extension source |1,623 ASan/UBSan checks against the actual applied source | Real TCC/runtime acceptance pending |
| Physical GPU suite | Prior27 cases reconstructed, plus four independent fetch/overlap/noise cases prepared | Device pixels pending |

Old temporary build artifacts had disappeared. The installed29-profile registry
was recovered from the bundle and matched its recorded original include exactly.
Adding explicit empty immutable-sampler fields changes only its C representation.
Prior27 fixture payloads were regenerated from the source recipes and their
independent oracles; unavailable old payload hashes are not claimed as matched.
No whole USERDATA image or current BOOT backup was read for recovery. Required
stock files were recovered by bounded read-only HFS ranges.

A successful build or BOOT installation will not alone establish a repaired
home screen. The next capture must show this stage's live submission, ordered
pixel results, backboardd staying alive and TCC extension consumption.

## Final local image

Full XNU make exits0 with the real19-file provider/compiler payload and31-case
suite. The actual installer preflight accepts40,577,664 raw /9,811,090 packed
bytes. The prepared BOOT is31,432,720 bytes, below the33,554,432-byte BOOT
capacity. Production Cortex-A53 builds, all five compiler-tool4-KiB signatures,
the15 existing native API/transport regressions, runtime ASan/UBSan and the real
fetch factory/emitter tests pass. Optional CTF debugging metadata was disabled
using the build's supported `DO_CTFMERGE=0`; native code and symbols are real.
Device installation and physical results are recorded separately.
