# Display resource audit and scoped restoration — 0182

## Verdict: CONCERNS — missing UI bundles confirmed; first-frame cause not proven

0181 has 21 passing GPU oracles and no old copy rejection, but still no stock
Metal commit. The reduced-root stager explicitly omitted Applications. Source
inspection and the actual launchd error establish a separate missing UI service,
PosterBoard; restoring it does not establish that the remaining renderer is
complete. The user narrowed the requested repair to display-related components.

## Selected complete bundles

| Bundle | Evidence for selection |
| --- | --- |
|PosterBoard|Actual0181launchd Missing executable; active-wallpaper observer/dataModel service domains.|
|PaperBoard|Retained launchd job targets missing executable; wallpaper-service; includes entire PlugIns/LegacyPoster.appex referenced by AppExtensions cache.|
|PreBoard|Backboardd binary literal file:///Applications/PreBoard.app and com.apple.PreBoard; declares FrontBoard workspace/system services. Runtime absence failure not captured.|
|InputUI|Retained launchd job targets missing executable; keyboard/input-host service domains.|
|MediaRemoteUI|Retained launchd job targets missing executable; mediaremote UI service.|
|ClockAngel|Retained launchd job targets missing executable; clock UI service.|

These six source bundles total 1,494,904 regular-file bytes, 47 files and 224 subtree
directories plus Applications structural parent. No symlinks or extended
attributes are present. Complete bundles, signatures, localized directories and
embedded extensions are retained; Apple code is not re-signed or committed.
Future staging now selects exactly this set, not every stock application.

## Backboardd and omitted data folders

Backboardd has 46 direct Mach-O load dependencies: 45 strong and one weak
AppleInternal liblinkguard. None names a path beneath any of the seven omitted
System/Library directories. The six app binaries' direct dependencies likewise
remain outside these omissions. Targeted app/framework resource/plist scans
found no absolute references to the omitted subtrees. This is bounded static
negative evidence, not proof that transitive dyld-cached frameworks never query
them dynamically. Runtime backboardd already loads the Metal provider, opens
resources and creates pipelines; no Library not loaded failure is captured.

The actual wallpaper locations were retained: Library/Wallpaper has 234 files and
20,350,558 bytes; System/Library/ProceduralWallpaper has 18 files and 4,356,418 bytes.
Source and original prepared-root view match for these locations. The prepared
view is historical, not a fresh full-device snapshot.

| Still omitted | Observed source content / reason not restored wholesale |
| --- | --- |
|LinguisticData|Language data; no demonstrated first-frame missing-file request.|
|PreinstalledAssetsV2|RequiredByOs lists context/location/game-controller/Bluetooth/sharing/voice/language assets; no wallpaper subtree found. Folder name alone does not establish that all payloads are needed for a frame.|
|Health|Health resources; not a demonstrated first-frame dependency.|
|NanoTimeKit|ComplicationBundles, FaceBundles, LinkBundles; cached frameworks may use them, but no first-frame missing-file evidence.|
|Assistant|Siri/assistant payloads; not a demonstrated first-frame dependency.|
|OnBoardingBundles|Per-feature onboarding; no missing-file display request captured.|
|Audio|MIDI Drivers,Plug-Ins,Tunings,UISounds; may matter for audio/haptics, but not proven as current graphics blocker.|

All may contain required data for their respective features. They are not
classified universally optional. They are excluded from this repair because
there is no specific evidence that bulk restoration will unlock first display.

## Capacity and installation boundary

A read-only 512-byte HFSX USERDATA volume-header read reports 2,271,830,016 free bytes
(~2.116 GiB). All eight omitted trees would require 2,545,402,390 logical bytes
(~2.371 GiB), exceeding this by 260.9 MiB before filesystem overhead. The six-bundle
subset is only ~1.426 MiB. Source compression does not reduce its HFS allocation
requirement. Next writable HFS mount replays the journal normally; installer
must check its live free space as well.

TWRP lacks HFS+ support. Restore through the already-used native HFS VFS
installer before launchd, from private compressed BOOT payload, preserving exact
numeric owners/modes, rather than changing raw HFS metadata or retransmitting
USERDATA. The generated combined payload has 60 files (13 existing + 47 apps), 225 directories,
29,710,506 raw / 8,412,239 packed bytes. Independent extraction/decompression verifies
all 60 source byte sequences. Kernel allowlist is exact six subtrees, with an
explicit a5apps_install=1 gate plus existing USERDATA/write/HFS requirements.
The fresh kernel build completed with exit 0, including symbol generation. The BOOT candidate is 29,280,272 bytes, below the 32 MiB BOOT partition capacity. Five builder tests, the actual kernel preflight harness (including corrupt streams and app-gate-off coverage), all 183 patch-format checks, and Python/shell syntax checks pass. The BOOT image was streamed to the explicitly checked lab A5 BOOT p10: dd acknowledged all 29,280,272 bytes, sync completed and reboot was requested. The HFS installer receipt and first-frame consequences remain pending runtime log recovery.

## Next evidence

Recover the installer receipt and test whether PosterBoard's missing-executable
message disappears, its service starts, and a non-warmup Metal buffer reaches
commit → Query17 → Submit18→real terminal fences. A successful copy of the bundles
alone is not proof of displayed iOS GPU frames.
