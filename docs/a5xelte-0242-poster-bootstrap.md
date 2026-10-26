# 0242 PosterBoard bootstrap repair and packaging correction

## Verdict: CONCERNS — implementation tested, final device result pending

The user requested installation after investigating PosterBoard. The captured
trap is a concrete configuration/startup-state conflict, not a captured GPU
fault. A guarded compatibility shim, the active-AS0 admission correction and the
new genuine fragment publication were packaged. The first0242 BOOT was written,
but a later resource-seal closure check found a packaging defect. It is not a
completed validated device release; the corrected package requires the phone to
return to TWRP.

## Root cause evidence

Bounded read-only inspection of the phone's matching iOS16 dyld code and metadata
confirms `PBFPosterExtensionDataStore` fields and paths:

| Evidence | Meaning |
| --- | --- |
| First-time setup at preferred0x1c1777a70; load/check at+0x40/+0x44 | A nonnil configuration at self+0x98 enters the fatal assertion |
| `_stateLock_initialExtensionsLoaded` is BOOL at+0xe9 | The extension update caller uses this separate flag to select first-time setup |
| Lazy getter at0x1c1778c10 | If configuration is nil, build with nil context/outMutated, store at+0x98 and return, without setting the initial-load flag |
| Update caller at0x1c177e2c4..0x1c177e308 | When initial extensions are not loaded, invoke first-time setup, then mark loaded after return |
| Captured trap/heap | Existing configuration, first-time update path and no home/lock poster paths; assertion `!_stateLock_switcherConfiguration` |

This establishes the conflicting reachable state and a stock writer that can
produce it. The capture does not include a timestamped write proving which
particular early client invoked the lazy getter. It does not establish the
cause of every PosterBoard failure or all UI slowness.

## Guarded repair

The shim intercepts only the first-time setup method on the exact lab
PosterBoard bundle. Method signature, concrete configuration class, ivar
names/types/offsets and the observed state-load instructions must match.
Before initial extension loading it clears only a configuration with no
configurations, active/selected object or held associations, and no selected
data-store object. It uses the Objective-C strong ivar API. The original setup
then runs; the original caller retains responsibility for setting the initial
extension-loaded flag and delivering normal notifications/default setup.

Diverse or populated states are preserved and still run the original method.
No assertion is blanket-disabled, no preference file is reset and no poster is
fabricated. Host tests execute the actual shim with mock stock objects and
original-method receipts under ASan/UBSan. The Apple setup itself is not run in
that test; successful phone initialization needs fresh runtime receipts.

One mandatory dylib load is added in the local PosterBoard executable's existing
header padding. The executable text and original entitlement dictionary are
verified exact; the local code signature changes. This makes loading independent
of whether PosterBoard discovers Metal early. The shim only has Foundation/ObjC
dependencies and is built/signed for iOS16 arm64/Cortex-A53 with4096-byte pages.
Patch0222 permits its one exact installer path; the app uses the existing scoped
app gate. Diagnostic capture adds PosterBoard only.

## Shader and queue work included

The exact fragment that waited in0241b was compiled through the actual worker
and released backend: native4048B, genuine reflection/hashes, SPIR-V validation
and production cache-loader ASan/UBSan acceptance pass. It remains a compiler
result until phone consumption and GPU completion are recorded.
Patch0221 handles both CPU-staging and active-AS0 GPU contention before this
caller's START. Poison/deadline/real-fence behavior remains. Host tests and old
helper negative regression pass; this is not a measured FPS improvement.

## First0242 package and installation

Full XNU build completes after rerunning the dsymutil step outside the sandbox;
its first attempt hit `/dev/fd` permission failure. Final linked kernel25220976B,
BOOT25888784B,392payload files/37compiled publications. Linked segments, payload
CRCs, the270original selected-app files/metadata, exact loader/DTBH/identity and
all startup flags were checked. No raw Apple program or shader output is in git.

Guarded recovery/model/TWRP/p10/capacity checks pass. Offset-zero BOOT write
acknowledges25888784bytes, sync succeeds and reboot is requested. No BOOT backup,
post-write readback/hash or whole USERDATA transfer. This is installation proof,
not successful PosterBoard runtime behavior.

## Resource-seal defect caught after installation

The first signing helper put its temporary entitlement plist inside the sparse
staged app. Codesign sealed that file, but the installer did not contain it.
Executable signature-page and stream checks had passed; they did not check this
closure. A report file was also created after signing inside the host app; it
was not deployed. Do not treat the first0242 signing check as full phone bundle
verification.

The tool now keeps temporary signing input and receipts outside the app,
requires the original Info.plist/identity, verifies the complete app after
signing and checks that every sealed resource exists with the expected hash.
A real-codesign packaging regression using an additional resource fixture passes
and confirms no temporary metadata remains in the signed app. The fixture is
not a phone payload. The final corrected app must be signed against the actual
complete existing PosterBoard resource tree, using bounded read-only recovery
access, then repackaged, checked and written. TWRP return has been requested;
no corrected0242b image/write is claimed yet.

## Follow-up: 0242b installed

The subsequent TWRP return supplied the complete seven-file PosterBoard app and
the0242 log. The corrected resource seal, full XNU/linked payload checks and
guarded BOOT write/reboot are complete. See the [0242 runtime and0242b report](a5xelte-0242-runtime-and-resource-seal.md).
The log confirms hook installation but has no stock-setup completion receipt;
do not infer a completed state repair from the lack of a crash alone.
