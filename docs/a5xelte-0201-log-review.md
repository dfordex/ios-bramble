# 0201: SpringBoard startup RPC waits; GPU work completes

## Device result

The user confirms that the correctly oriented Apple logo remains on screen.
The home screen is not reached. Read-only SYSTEM recovery obtains flush 35,
all 138,484 recorded bytes (138,239 decoded bytes, 1,504 lines), without ring
overwrite. Framebuffer interval totals cover about 378 seconds. Raw logs and
symbolication artifacts remain private outside Git.

| Boundary | Evidence | Result |
| --- | --- | --- |
| Private GPU suite | line 197 | 23/23 cases pass, including 604/605 pixel oracles |
| Incremental installer | line 271 | 18 files complete, sync 0 |
| Phone-compiled cache use | lines 1014, 1020 | Both 602 and 603 bind as phone-compiled programs |
| Live stock commands | results at 1056, 1279, 1330 | CB2/3/4 complete six native jobs: one clear, three 602, two 603; status 0, header 1, MMU 0 |
| Completion | three callback pairs and scheduled waits return | No outstanding GPU completion demonstrated |
| Panel copy | one CPU and one GPU full-panel copy | 8,294,400 bytes each; 4,096 sampled source/panel pixels have zero differences |
| Process failures | complete capture census | No crash header, kernel panic, Metal build failure or native job error |
| New shader variants | no live 604/605 specialization | Their private tests pass; this run does not exercise compositor use |

PosterBoard and assetsd do not execute within this capture. Their absence of
crash records does not retest or repair the later failures from the long 0200
run. Final key events alone do not establish a persistent input deadlock.

## Main-thread samples

Five rounds (0 through 4) contain 63 thread records. No process reaches the
32-thread capture cap. Samples are approximate: processes are not suspended
and register/stack reads are not a coherent task-wide snapshot.

Backboardd's main thread in rounds 3 and 4 is in `mach_msg` through
`__CFRunLoopServiceMachPort` / `__CFRunLoopRun` / `CFRunLoopRunSpecific`.
This is an ordinary message-loop wait, not a captured GPU fence wait.

SpringBoard's main thread waits synchronously for XPC replies, but the call
changes between rounds:

- **Round 3:** `xpc_connection_send_message_with_reply_sync`, NSXPC invocation,
  then UserManagement. Preferred VA `0x1920f7bac` follows a selector stub for
  `getUserSessionAttributes:reply:`. The selector pointer and exact preceding
  call instruction were resolved from the local stock shared cache.
- **Round 4:** the same NSXPC wait machinery leads to
  `____CacheDeleteRegister_block_invoke.210` at preferred VA `0x1a270781c`.
  Its preceding call is `clientCheckin:endpoint:info:reply:`. The service is
  `deleted` (`com.apple.cache_delete`), which executes just before this sample.

Other workers include provisioning-profile enumeration awaiting `misagent`,
Powerlog and DND XPC work, and a keyboard worker synchronizing with the main
queue. These are observed waiting contexts, not independently proven defects.

The changing main-thread RPC shows startup work changing over the sampling
interval. It does not prove one permanent deadlock, a broken XPC transport,
or that either service is the final reason for the missing home screen.
The opposite sides of these RPCs were not sampled in 0201.

## Actual logging defect

Long `SMP` records are clipped at 255 bytes on the phone, losing stack tails
and sometimes the newline. Adjacent records consequently join together.
Only intact address tokens were used for symbolication; clipped tails cannot
be recovered. This is a concrete diagnostic defect, independent of the UI
stall. The [0202 change](a5xelte-0202-ui-server-diagnostics.md) fixes it and
captures the relevant servers before selecting a service repair.
