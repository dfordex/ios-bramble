# 0202: bounded stack records and XPC server samples

## Change

Patch 0196 follows the [0201 device findings](a5xelte-0201-log-review.md).
The opt-in A5XELTE sampler now prints a compact `SMP` register/wait record,
then up to two `SBT` lines containing six stack addresses each. Each line has
a newline and remains below 224 bytes, avoiding the observed 255-byte console
clipping. Thread IDs join stack lines to their register records.

The four UI targets retain their 32-thread cap. `usermanagerd`, `deleted`
and `misagent` are added with a 16-thread cap each. Their independent stderr
tee budgets are 256 chunks each; existing process budgets remain unchanged.
The initial 90-second delay, 60-second interval, 32-round limit, 12-frame
unwind depth, aligned ascending 8 MiB stack window and approximate unsuspended
sampling remain. References protect objects; user reads and output do not
hold task/thread locks. The original donor implementation is unchanged.

The packer's `--ui-diagnostics` flag requires the new split-stack and server
markers, preventing an old clipped kernel from being packed as this trial.
No service configuration, XPC behavior, shader or rendering path is changed.

## Local verification

- Actual sampler function extracted from staged XNU: 14 ASan/UBSan cases
  pass, including reference/lock balance, invalid registers, read failures,
  bounded/cyclic frames, 16-thread server cap, worst-width values and the
  per-call length/newline contract.
- Patch applies with zero fuzz and reproduces all three staged source files
  exactly.
- Complete DEVELOPMENT ARM64 A5XELTE build, including symbols, exits 0.
- BOOT candidate is 30,343,184 bytes, within the 33,554,432-byte partition.
  It retains the existing 18-file installer payload, 23 GPU test cases and
  tested four-core configuration.

## Device verification pending

This is an observation repair, not a claimed fix for the stalled logo.
The next capture should confirm intact `SMP`/`SBT` lines and show both sides
of SpringBoard's startup RPCs across several rounds. A responsive server,
changing RPC, or later process crash must be distinguished from a persistent
wait before changing the service itself.

## Installation receipt

Source `f5937fa` is pushed. Exact ADB recovery/model/TWRP, BOOT p10 mapping
and partition capacity checks pass. The direct write acknowledges 30,343,184
bytes, followed by sync and reboot request. No backup, post-write hash/readback,
formatting or whole root transfer was performed. Runtime result is pending.
