# 0233: pipeline-dependent shader blending and compiler process isolation

Verdict: source integration and host checks pass. No new BOOT image or device
installation is claimed. The phone's earlier near-idle translator wait is not
reproduced or attributed by these host tests.

## Real shader fallback

The factory keeps the shared fixed-function pass for equations representable
by Midgard v4. Other supported color0 states create an immutable fragment
function request containing the original typed AIR constants plus `blend_state`.
The canonical identity includes pixel format, write mask, independent RGB/alpha
operations and factors. A different state cannot load an existing variant under
the same key. Existing function requests/publications retain their old identity.

The root worker translates the original AIR function, then passes the actual
attachment state to released Mesa's `nir_lower_blend`. This is part of the
production dynamic-stage backend, followed by the existing resource analysis,
register/TLS/code bounds and authenticated atomic publication. It does not
replace the requested fragment with a generic color program or return dummy
success while code is unavailable.

Supported fallback state is single-source BGRA8Unorm or BGR5A1Unorm, with
independent ADD/SUBTRACT/REVERSE_SUBTRACT/MIN/MAX, factors Zero through
OneMinusBlendAlpha (including SourceAlphaSaturated and constant color/alpha),
and channel masks. A zero write mask uses the existing no-write hardware state.
Dual-source factors require a second color-output ABI and remain explicitly
unsupported. Other target formats, depth/stencil and multisampling are not
established by this change.

A root receipt binds the complete blend state, native code, reflection and an
explicit `blend_lowered` native ABI marker. The pipeline retains the replacement
stage owner, validates reflected IO/resources as before, and preserves the
original API attachment in its descriptor contract. Normal source framebuffer
fetch remains a separate reflected input-attachment contract.

The native emitter enables destination preload but uses a copy equation with
full hardware write mask: the generated fragment already applied the API
blend equation and preserved masked channels. Applying API blending again
would corrupt results. `setBlendColorRed:green:blue:alpha:` is snapshotted per
draw and carried through the local misc request into FS UBO0 bytes480..495.
These bytes do not overlap push0..79, storage descriptors96..351, four sampler
records352..479 or viewport512+. Constants are dynamic data, not extra cache
variants. Nonfinite values fail before native submission. Kernel ABI is unchanged.

## Compiler child environment

Previously the daemon's cache `.lock` descriptor lacked close-on-exec. Direct
spawn also inherited signal masks, ignored dispositions and unrelated file
descriptors. The new spawn contract closes unrelated descriptors, supplies
`/dev/null` stdin, resets the signal mask/dispositions and retains only the
explicit stdout/stderr log redirections. The cache lock itself now has
O_CLOEXEC. The daemon no longer demotes the synchronous compiler tree to nice10;
it requests ordinary nice0.

A real OS probe reproduces polluted-parent inheritance and verifies clean child
signals, closed unrelated descriptor and EOF stdin after the correction. Actual
OS exec, resource bounds, signals, surviving descendant rejection and untrusted
path rejection still pass. The service continues to admit one compiler group,
enforce500MiB group accounting and8MiB output limits, and impose no elapsed time
limit. No speculative watchdog/retry, concurrent500MiB child, placeholder
publication or forced-success path was added.

These are confirmed process-inheritance corrections, not proof of the precise
0230 phone stall cause. A future device run must show the formerly waiting
function actually executes and publishes before that issue can be called fixed.

## Verification

| Check | Result |
| --- | --- |
| Real stock AIR -> SPIR-V validation -> new Midgard variant -> atomic root publication | Four cases pass: MIN/MAX, masked constant-color/alpha, packed BGR5A1/saturate, independent nonfactorable subtract equations |
| Real scanner under64 old receipt entries plus function lane | Each new variant compiles before old maintenance; malformed leaf preserved; one retirement/scan; second scan does not recompile |
| Production Metal cache/factory and native encoder | Four real publications pass; altered-state cache identity rejects; actual new fragment bytes emitted; copy RSD, destination load and dynamic constants decoded; invalid flag combination rejects |
| Existing captured complete pipelines | All52 pass actual factory and exact descriptor roundtrip, no missing stage |
| Existing native wrapper suite | All18 executables pass with real host IOSurface access; kernel transport remains mocked |
| Shared fixed blend scalar oracle |264 fixed states/3,346 shader routes/8,448 numeric comparisons/all16 masks pass ASan/UBSan |
| Request validation | Variant identity differs from original; vertex variants, dual-source, negative/fractional/boolean/null factors reject; previous quota/atomic/symlink guards pass |
| Process runner | Nine real OS exec/inheritance/resource/path cases pass; no phone execution proof |
| iOS16/A53 build | Signed provider, root worker and released-Mesa backend pass4KiB signature verification |

Native descriptors and compiled programs are tested on the Mac. Their new blend
pixels and interactive iOS behavior still need a physical test. The architecture
also retains the previously documented broader varying/input and persistent
resource residency limits. This commit does not claim universal Metal support.
