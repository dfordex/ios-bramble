# 0200 recovered device result

## Verdict: CONCERNS

Both new real shader pixel cases pass on the phone, together with all previous
21 cases. Installation and existing live 602/603 rendering also succeed. The
user reports that the correctly oriented Apple logo remains on screen; the
home screen is not reached. There is no captured process crash or kernel
panic, and no live 604/605 request in this trial, so the prior specialization
failure has not been re-exercised.

## Scope and recovery

Read-only TWRP recovery of the reserved SYSTEM log area, with exact model and
SYSTEM mapping checks. Flush 73 contains all 188,430 recorded bytes, without
ring overwrite: 188,185 decoded bytes, 2,388 lines. Raw files remain private
outside Git. No BOOT/root write or reboot was performed during this readout.
The 143 framebuffer windows account for 760,380 ms of recorded operation;
they are interval measurements, not an inferred wall-clock boot duration.

## Evidence

Line numbers below refer to the complete private decoded capture.

| Boundary | Evidence | Result |
| --- | --- | --- |
| CPU | 101 | Tested 4/4 CPUs, SGI verified |
| New shader 604 | 191–192 | All 4,096 output bytes within tolerance 1; vertex/fragment fences 45/46 status 0, immutable input check passes |
| New shader 605 | 195–196 | All 4,096 output bytes exact; fences 47/48 status 0, immutable input check passes |
| Complete suite | 197 | 23 evaluated, 23 passed; GPU pixels, not compositor coverage |
| Installer | 242–271 | Exact new payload, 18 files complete, sync 0; new provider, runner, two recipes and combined backend written |
| Runtime ABI | 850, 899 | Both target process audits: 751 methods, errors 0 |
| Phone cache | 994 | Actual backboardd binds profile 602 from `source=phone-compiled`; this proves consumption of a previous publication, not publication during this boot |
| Live drawing | 1001–1263 | Three command buffers complete status 4/error 0; six native jobs (clear once, 602 three times, 603 twice), all status 0/header 1/MMU 0 |
| Actual 603 pixels | 1030–1033, 1168–1171 | Full 2,073,600-pixel target retains 29,457 RGB-nonzero pixels |
| Presentation | 1039–1269, 1874–1883 | Seven SwapEnd records; six selected, one all-zero record replaced; all 14 logged SwapWait returns succeed |
| Panel copy | 1180–1184 | One GPU full-panel copy; all 4,096 sampled source/panel RGB and alpha values match. One earlier CPU full-panel copy also completes |
| Callback boundary | 1035–1043, 1173–1177, 1259–1263 | All three completion callbacks begin/end; scheduled waits return. A later repeated CB4 wait also returns (1877–1878) |
| Wake/input | 1874–1883, 1933–2011 | Display-on request and surface 1 selection occur; 24 key events are consumed through head/tail 1536. Final two events remain pending at capture end; no full queue is logged |
| Compiler | 1358, 1369–2373 | AIR exits 0 at 96.969 s; combined Midgard backend remains RUNNING through 422.9 s. No current-boot PUBLISHED or compiler failure marker |

## Findings

| Priority | Finding | Smallest next step |
| --- | --- | --- |
| P1 | The home-screen transition stalls after completed logo rendering. Live GPU jobs, callbacks and logged SwapWait calls have returned; no later live Metal commit is recorded. | Capture SpringBoard/backboardd startup progress and waiting thread state at the stalled boundary. Determine which producer/service is waiting before changing GPU queue semantics. |
| P1 | New 604/605 programs are physically pixel-tested, but iOS never asks for their specializations or pipelines in this capture. | Preserve the new coverage and trace the stalled UI producer. Do not claim live pipeline acceptance, invent another shader request, or replace missing state with success. |
| P2 | Phone compilation remains slow and incomplete in this capture. | Add/inspect precise active request, stage and CPU progress if investigating the compiler. The log alone does not establish a deadlock or that compilation blocks the UI. Embedded host-compiled programs already execute independently. |

The `compile request ... result=2` lines mean **already queued**, as defined
by `A5MaliShaderForwardAlreadyQueued`; they are not pipeline rejection codes.
Every logged full pipeline is followed by acceptance. There is no captured
"Metal failed" message, selector exception, GPU/MMU fault or crash report.
backboardd and SpringBoard each execute once; PosterBoard also starts (1566).
Repeated unrelated `exec xpcproxy` lines do not establish a compositor crash.

## Remaining uncertainty

- The final visible logo is the user's screen observation. The log establishes
  actual pixels and sampled panel agreement, but not a full home-screen frame.
- An all-zero swap and display-off request occur before a later display-on.
  `a5fb_keep_on` ignores physical off; this does not prove the UI is awake.
- SpringBoard receives a privilege 1007 denial (1137). Local XNU identifies
  this as `PRIV_DARKBOOT`, protecting writes to the darkboot sysctl. No trace
  connects this denial to the stalled transition, so it is a candidate to
  observe, not a proven cause or justification for blanket sandbox bypass.
- Most key events are demonstrably consumed, and callbacks finish. A complete
  process-wide hang is not established; individual UI threads may still wait.

The next concrete investigation is the SpringBoard/backboardd transition after
CB4, with waiting-thread/startup evidence. The captured two new shader pixel
cases are successful and should remain regression tests.
