# 0235 complete runtime review

The unwrapped SYSTEM ring contains 595,852 raw bytes, decoded into 6,471 lines
(595,607 UTF-8 bytes after CR normalization). The physical screen report shows
a rendered App Library search/keyboard with no Settings search result.

## Crash and graphics status

- No kernel panic, explicit process-crash record, uncaught exception or recorded
  SpringBoard/backboardd abort is present. `exec OTACrashCopier` is a service
  launch, not evidence of a crash.
- All 360 captured fence receipts report completion and zero MMU status.
  All 32 bounded native-job receipts have status zero and MMU zero. Profiles
  0, 602, 603, 604, 606, 65536, 100 and 104 appear in these receipts.
- There are 64 complete backboardd command-buffer result records (IDs 2..65).
  Every one is Completed/status4, error0, submitted1. ID1 has no complete result
  receipt in this capture; do not turn its absence into a success or a failure.
  The largest captured command list has 82 draws and 92 draws-plus-clears,
  exceeding the old 64-operation cap without recorded rejection.
- No draw rejection, unsupported draw or rejected dynamic-stage link is recorded.
  A genuinely new 1072-byte fragment compiles and publishes on the phone, then
  backboardd accepts it. This does not prove every possible shader is supported.
- Across 122 measured framebuffer intervals, 93 contain no displayed frame;
  many are startup or idle periods. Eight active intervals measure 5..7fps;
  the maximum interval is 6.5fps. This remains slow and is not a sustained
  benchmark. Summed presentation records contain 178 GPU presents, two CPU
  presents and zero GPU fallback events. The two explicit CPU presentations
  must not be described as zero CPU rendering for the entire run.
- 69 touch and 10 key HID records are captured. Selected key queue records show
  head/tail consumption and no full queue.

No GPU fault or compositor crash is evident in this run. That is narrower than
proving pixel correctness for every UI operation. Optional pixel suites are
off; the new line/large-geometry/variable-blur paths have no individually
identified physical pixel oracle in this capture. No new variable-blur request
is logged here, so its specific hardware execution remains unproven.

## Other warnings

SpringBoard cannot soft-link CarKit and cannot find the en_US Lexicon base
unigram data. The latter may affect predictive text. There are also existing
usermanagerd persona/foreground initialization warnings, a failed swap-file2
open, firmware/factorydata BindFS lookups and NVRAM/virtual-random setup warnings.
They are unresolved port gaps, not demonstrated causes of the absent app icons
or a recorded GPU crash. Do not patch them by ignoring assertions or fabricating
frameworks/data. The three application's file installation is independently
verified in [the app presence report](a5xelte-0235-stock-app-presence.md).

The subsequent 0236 change is scoped to selected app registration. Graphics
provider, compiler backend, worker and previous shader publications remain exact
0235 bytes. Raw logs and request identities stay private.
