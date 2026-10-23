# 0201: bounded UI diagnostics and board-guard audit

## Verdict: CONCERNS — diagnostic implementation built, runtime pending

The long 0200 run completes actual phone compilation and GPU jobs but still
does not reach the home screen. PosterBoard's repeated first-time setup
assertion and the separate assetsd exception need more context. This build
adds observations; it does not claim to repair either failure.

## Confirmed diagnostic omission

The existing `bsd/dev/sweet_sample.c` was guarded only by
`ARM64_BOARD_CONFIG_SWEET`, and its only start call was in Qualcomm UFS startup.
A5XELTE defines the compatibility macro `SWEET`, but does **not** select
`ARM64_BOARD_CONFIG_SWEET`; those conditions are different. Its eMMC path
therefore never started the thread sampler. The syscall/crash machinery had
the sample routine, but no Samsung periodic samples could reach it.

Patch 0195 adds an explicit A5XELTE sampler start after eMMC log startup,
requiring `a5uidiag=1`. The packer's new `--ui-diagnostics` switch requires the
new kernel marker and appends this flag. Diagnostics remain opt-in.

## Captured observations and bounds

- Sample SpringBoard, backboardd, PosterBoard and assetsd after 90 seconds,
  then every 60 seconds, for at most 32 rounds.
- Each task header records PID, main-image address, shared-cache slide and
  total/captured thread counts. At most the first 32 threads are sampled;
  truncation is explicit in the header.
- Each thread records stable thread ID, scheduler state bits, wait-event
  address, wait result, priority, available saved user PC/LR/SP and up to
  twelve frame-pointer return addresses. These can be symbolicated with
  the matching local images/cache. State bits include WAIT=1, SUSP=2,
  RUN=4, UNINT=8; multiple bits can coexist.
- Capture thread references under the task lock, release that lock, then
  copy bounded register scalars under each thread's scheduler lock. Release
  every lock before printing or reading the user stack. Retain the map and
  each selected thread until their reads complete.
- Frame reads must be ascending, 16-byte aligned, within an 8 MiB window
  above saved SP and within the depth/output bound. Faulting reads stop
  that unwind; absent registers and null maps are explicit bounded cases.
- No process is suspended or stopped. Live saved registers/stack can change
  during capture: headers say `approximate=1`. These are best-effort samples,
  not coherent stop-the-world snapshots or proof of the cause of a wait.
- Sampling ends by terminating its own kernel thread. The donor path keeps
  its original schedule and implementation.
- The diagnostic flag gives independent stdout/stderr budgets to backboardd
  (1,024 chunks), SpringBoard (1,024), PosterBoard (512) and assetsd (512).
  Compiler (128) and probe (64) budgets stay separate. Chunks are at most
  256 bytes; counts saturate. This captures writes actually made to /dev/null,
  not all unified `os_log` records.
- Add PosterBoard/assetsd to bounded crash heap-string extraction, each at
  most two scans; preserve the existing four-scan budget for the original
  selected processes. Heap strings may reveal exception text but are not
  guaranteed to contain it or prove a string was executed. Raw output stays
  private; only derived analysis is committed.

The existing 4 MiB SYSTEM log ring and partition bounds remain unchanged.
Logs are bounded, but sufficiently verbose other activity can still wrap it;
recover after several useful samples rather than waiting indefinitely.

## Board/config audit

The active `MASTER.arm64.a5xelte` and `MASTER.arm64.sweet` differ only in the
introductory descriptive comment. Their general scheduler, VM, filesystem,
Mach, networking and debug option lists match. This does not mean either
target implements all Apple hardware or all iOS services.

The board headers correctly differ in GICv2 versus GICv3, absence versus
presence of 16 KiB pages, and PAN unavailable versus available. A5XELTE keeps
the eight-CPU build capacity and two cluster slots while the tested boot
still selects four CPUs. Direct preprocessing confirms GICv3=0, PAN=0 and
no `__ARM_16K_PG__` on A5XELTE; both retain the intended shared `SWEET=1` macro.

After the sampler correction, the scan finds twenty remaining preprocessor
conditions mentioning only `ARM64_BOARD_CONFIG_SWEET`. Their classification:

| Group | Conditions | Disposition |
| --- | --- | --- |
| UFS, USB, touch, keys, SPMI/RPMh and battery | 7 | Qualcomm-specific paths; Samsung has separate eMMC/input code. Battery/USB hardware support is a separate porting gap, not a safe flag-only enable |
| Root startup/glue and writable root | 3 | A5XELTE has its own eMMC, root authentication and explicitly gated initial writable installer mount |
| HFS dirty non-journaled-root exception and hardlink log suppression | 3 | Not needed to enable the currently working journaled writable root; no speculative dirty-root bypass added |
| Serial/persistent log | 2 | Samsung separately invokes `a5xelte_log_append`, already device verified |
| IPv4 address/route telemetry | 2 | Diagnostic prints only; normal networking functionality is not enclosed by these guards |
| `hw.machine`/`hw.model` compatibility branch | 1 | A5 uses the existing macOS-config iOS branch (`hw.machine=iPad8,6` for iOS binaries); not an absent service |
| SWEET board include and timer declaration | 2 | Samsung board include and GICv2 timer path are separate |

The shared pthread provider, built-in AMFI, software crypto, iOS VM compatibility,
IOSurface, platform, watchdog and input/display services already include A5XELTE
or use the intentional shared compatibility macro. The reviewed guards reveal
no additional confirmed launch-critical omission. In particular, the SWEET
PM6150 battery implementation cannot be enabled against Samsung PMIC addresses.
This guard audit is source evidence, not proof that every runtime service works.

## Local checks

- `tools/test-a5xelte-ui-sampler.py KERNEL_ROOT` extracts the actual A5 sampler
  and runs ten ASan/UBSan cases: 64-to-32 thread truncation, reference balance,
  no lock held during faultable reads/printing, missing registers, null map,
  unaligned/below-SP/out-of-window/cyclic stacks, failed reads and depth cap.
  These are host stand-ins for kernel primitives, not a phone scheduler test.
- Patch 0195 applies with fuzz zero and exactly reproduces all four staged
  files. Full XNU compilation, linking, CTF and symbol generation pass.
- Packed BOOT is 30,343,184 bytes, within the 33,554,432-byte p10 limit;
  `a5uidiag=1` is present without boot-argument truncation. The existing 0200
  18-file payload, 28-profile provider, 23 GPU fixtures and tested four-core
  configuration are retained.

Runtime verification must establish `A5XELTE UI diag: sampler enabled`, `SMP`
records for the UI processes, and any new PosterBoard/assetsd output. A next
crash may require a longer capture; initial waiting-thread samples should
already be useful after several minutes.
