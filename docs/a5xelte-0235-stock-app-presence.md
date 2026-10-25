# 0235 selected stock applications: presence confirmed, visibility unresolved

The user reports that Settings, Clock and Safari do not appear. The supplied
screen shows no App Library search result for Settings. This is a physical
visibility failure, despite successful file installation.

A bounded read-only HFS catalog traversal of the connected recovery device
retrieves exactly the three selected application bundles, without mounting or
copying the whole root volume. All 270 files (3,536,989 bytes) match the embedded
payload CRC, size, mode, UID and GID. No files are missing or different:

| Bundle | Files | Result |
| --- | ---: | --- |
| Preferences.app | 12 | All match |
| MobileTimer.app | 39 | All match |
| MobileSafari.app | 219 | All match |

The catalog/data read totals 3,831,296 physical bytes. The fresh SYSTEM ring
contains 595,852 bytes without wrap and confirms existing executables and
Info.plists with error zero, 282 successful directory operations and final
374-file installation/sync zero. App Info.plists retain their original bundle
identifiers, iPhone/iPad device families and arm64 capability. No hiding key was
found in these original manifests.

The kernel installer copies files and metadata. It does not invoke a userland
LaunchServices application registration or icon/database refresh. `lsd` starts
in the runtime log, but the log contains no registration result for these three
applications. File presence therefore does not establish that SpringBoard has
valid application records. Registration/indexing is the next hypothesis to test;
this read-only check does not claim the exact runtime cause has been proven.

A correction should query only these three known bundle identifiers through
LaunchServices, register missing/stale records with their real bundle metadata
and required containers, then verify resulting application proxies and icons.
Do not indiscriminately delete application databases or private user caches.
The public API usage reference is the upstream [uicache implementation](https://github.com/ProcursusTeam/uikittools-ng/blob/main/uicache.m).

No new BOOT or device mutation is performed by this verification. Private log,
read receipt and comparison proof remain in the workspace build0235/app-check
artifact directory; Apple files and raw device logs are not committed.
