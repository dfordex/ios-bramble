# 0226 compact vertex layout correction

## Source correction

The first explicit 0225 compositor rejection is a missing UV attribute in a
compact position/color vertex. Its native vertex and fragment have already
compiled successfully (1,808 and 992 bytes). Dynamic pipeline construction was
incorrectly imposing the full four-field Metal descriptor after recognizing the
two-input native ABI.

Dynamic profiles now retain the actual sparse Metal indices:

| Native vertex ABI | Required Metal indices | Optional unused indices |
| --- | --- | --- |
| Position/color | 0, 3 | 1, 2 |
| Position/UV/color | 0, 1, 3 | 2 |
| Position/two UVs/color | 0, 1, 2, 3 | none |

Every used field remains mandatory. Present unused fields still require the
canonical format, byte offset and buffer binding. Position supports the already
implemented Float2/Float4 rule; color remains Half4 at byte32/buffer1. Stride48,
step/rate, other descriptor state and shader authentication remain checked.

The independent native emitter gate validates the required mask, increasing
indices without duplicates, formats, offsets and binding. It already maps
compact native color location1 to Metal color index3/byte32. That mapping is
preserved rather than moving color into an absent UV slot. Legacy full four-field
descriptors remain valid. Static compiled registry selection is unchanged.

## Verification

The genuine captured vertex/fragment publications load through the production
cache and Metal pipeline factory, then the production native descriptor emitter.
Across all 16 field masks, Float2/Float4 positions, target80/43 and copy/source-over:

- Compact real vertex: 32 accepted / 96 rejected combinations.
- Authenticated single-UV static vertex with dynamic fragment: 16 / 112.
- Real dual-UV dynamic vertex with dynamic fragment: 8 / 120.

All 56 valid combinations encode the original shader bytes. Released v4
descriptor decoding verifies native color/UV slots, formats and offsets. Missing
live fields, changed offsets/formats/bindings, extra fields and stride changes
reject. Removing live fields directly from a profile also fails the independent
emitter gate. Existing dynamic and static602–606 format80/43 factory, blend,
preload and bounds regressions pass. These are host checks, not physical pixels.

The provider builds for iOS with verified 4 KiB signature pages. Actual kernel
installer preflight validates all 364 payload files. Relative to 0225, only the
signed provider executable changes; all 29 shader publications, compiler files,
launchd configuration and 270 app files with their metadata remain identical.

## Build

Full XNU make exits 0. BOOT is 25,669,648 bytes, kernel 25,002,448 bytes, provider
962,944 bytes. Every linked segment and every embedded file is verified in the
image. Loader, ADT, DTBH and boot arguments are byte-identical to 0225. The full
selected FDT remains below the unchanged S-Boot relocation boundary.

This candidate repairs the first confirmed descriptor mismatch. The five later
0225 pipeline aborts and the separate AttentionAwareness exception are not proven
fixed. Device acceptance, continued compositor lifetime, input responsiveness
and residency turnover require the next run.

## Installation

Recovery/model/BOOT p10/capacity checks passed. A fresh file opened at offset
zero supplied all 25,669,648 bytes; `dd` acknowledged that count, `sync` exited 0
and reboot was requested. No BOOT backup, post-write readback or whole USERDATA
transfer was performed. Physical boot and the corrected pipeline remain pending
the user's observation and the next SYSTEM capture.
