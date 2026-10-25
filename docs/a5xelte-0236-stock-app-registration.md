# 0236 selected stock application registration

## Correction

The already-restored Settings, Clock and Safari bundles are present, but their
icons are absent. The signed startup helper now creates a separate fresh child
process for their LaunchServices registration. This work does not block Metal
discovery or change the graphics provider, worker or compiler backend.

The child has an exact three-app path/bundle-ID/executable allowlist. Manifest
and executable hashes are pinned to the independently verified 20H392 originals.
It extracts XML entitlements from the actual bounded ARM64 code-signature
superblob, including the app's own container and shared/system-group contracts.
Altered input cannot add new privilege-bearing group metadata. No invented
signature identity or replacement entitlements are assigned to applications.

MobileContainerManager supplies the actual data/group container URLs. The
helper registers a System application dictionary containing the original
identity, path, entitlements, container and environment information. It checks
the exact identifier's resulting proxy state and bundle URL. API acceptance
alone is not success. Rejected calls, unavailable containers and invalid/mismatched
proxies are explicitly logged; startup retries are bounded. Only the three
selected applications are queried or registered. There is no whole-database
rebuild, unregister, cache deletion or forced SpringBoard restart.

The helper's existing fixed signed platform identity is retained. Its
entitlements add the LaunchServices registration and container SPI required
for the operation, based on the public upstream [uicache API/entitlement reference](https://github.com/ProcursusTeam/uikittools-ng/blob/main/uicache.m).
No jailbreak runtime package is installed.

## Verification and deployment boundary

Seven ASan/UBSan host modes use the real installed Apple manifests/binaries with
fake SPI objects: success, delayed/rejected-first registration retry, unavailable
API, denied container, rejected registration, invalid proxy and wrong proxy
path. Real signature parsing and tamper/hash rejection are checked. No host
LaunchServices database or containers are written. Native iOS/A53 compilation,
strict code signing and 4 KiB signature-page checks pass.

The 374-file payload retains all 270 original application files and 32 cached
shader publications. Only the startup helper changes relative to 0235. The
actual kernel installer passes its compressed-stream/policy preflight under
ASan/UBSan. Build and physical registration results are recorded below when
available. Successful host tests do not establish on-device registration or
visible icons; those require the new runtime `A5XELTE Apps:` receipts and the
user's screen report.

## Packaged and installed

Full XNU make exits zero. The final 25,800,720-byte BOOT matches every linked
kernel segment and all 374 embedded file CRCs. The loader, ADT, DTBH and boot
arguments retain the verified 0230 chain. Comparison with the 0235 payload
confirms that only `/usr/libexec/a5mali-metal-probe` differs. Existing graphics,
compiler and app contents/metadata remain exact. The final helper has verified
4 KiB signature pages. Its parent waits after Metal discovery to retain the
registration child's lifetime until its actual exit.

Guarded model/recovery/BOOT p10/capacity checks pass; the write acknowledges all
25,800,720 bytes, sync completes and reboot is requested. No BOOT backup or
readback, whole-root transfer, recovery/EFS/radio/GPT write is performed. The
artifact and private receipts are saved under workspace research/builds/0236.
On-device registration receipts and visible application icons remain pending.
