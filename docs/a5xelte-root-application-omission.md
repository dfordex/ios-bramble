# Reduced-root application omission — 2026-10-22

## Verdict: FAIL for the old selection; staging rule corrected

The original IPSW OS image includes PosterBoard.app/PosterBoard (119520bytes).
The missing executable in0181 is not evidence of an interrupted IPSW transfer:
`tools/a5xelte-stage-ios-root.sh` explicitly excluded `/Applications/***`.
The initial assumption that all of that directory was optional was wrong.
The prepared HFS root view also lacks an Applications directory, and the device
launchd log explicitly reports missing PosterBoard. No claim is made that this
is the only cause of absent compositor commits.

## Scope and evidence

The source OS Applications contains140top-level.appbundles,3689regularfiles,
226076224logicalbytes (~215.6MiB). Symlinks excluded from the byte sum. Source
APFS allocated size is smaller (~126.8MiB); use logical size for HFS planning.
The original staging report had2.6GiBfree, so excluding the whole directory was
unnecessary under that historical capacity snapshot; current device free space
has not been remeasured.

Ten cached launchd jobs directly name executables in the excluded directory:

| App | Cached job label |
| --- | --- |
|ClockAngel|com.apple.ClockAngel|
|InputUI|com.apple.InputUI|
|MediaRemoteUI|com.apple.MediaRemoteUI|
|PaperBoard|com.apple.PaperBoard|
|PassbookUISceneService|com.apple.PassbookUISceneService|
|PosterBoard|com.apple.PosterBoard|
|ShortcutsUI|com.apple.ShortcutsUI|
|ReplayKitAngel|com.apple.replaykitangel|
|AirDropUI|com.apple.sharing.airdropui|
|CheckerBoard|com.apple.checkerboard|

Source Info.plists additionally declare actual system service domains:
PosterBoard posterboardservices(active-wallpaper-observer,dataModel),PaperBoard
paperboard.wallpaper-service,InputUI keyboardui/input-ui-host/teletype,
MediaRemoteUI mediaremoteui-service,PreBoard frontboard workspace/system-service.
These are concrete service contracts, not proof every service must run for the
first UI frame. PreBoard is not one of the ten cached jobs above.

## Correction

Staging now preserves the entire Applications directory. Preflight and postcopy
checks require PosterBoard,PaperBoard,InputUI,MediaRemoteUI andPreBoard executables
as regression sentinels; preservation is not limited to those five. The script
still refuses to overlay an existing root and preserves numeric UID/GID and
extended attributes. A shell syntax check passes; targeted rsync dry-run confirms
PosterBoard and other system UI executable paths are selected. This changes
future staging, not the currently installed phone root.

Other existing omission families remain explicit: LinguisticData,
PreinstalledAssetsV2,Health,NanoTimeKit,Assistant,OnBoardingBundles,Audio. None has
been proven universally optional for all features. This audit inventories the
application omission and cached launchd references, not a complete dynamic iOS
file dependency closure. Restore the system UI applications incrementally and
trace the first non-warmup frame/flush transition. Do not retransmit or reformat
allUSERDATA merely to restore these files. Apple payloads remain private and
outsideGit.
