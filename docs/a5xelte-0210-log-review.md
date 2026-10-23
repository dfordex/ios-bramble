# 0210 phone readout: next inactive-attachment contract abort

## Verdict: FAIL for home-screen progression; new low-level paths pass

The full read-only SYSTEM capture has flush152,1,221,706 recorded bytes,
1,221,461 decoded bytes and11,851 lines; no ring overwrite or kernel panic is
recorded. The new19-file payload installs. All four added0210 pixel cases pass,
and the previously rejected actual602/2448 stage pairing is now accepted.
Backboardd nevertheless aborts three times while constructing a different blur
pipeline. The device user reports no visible progression.

## Evidence

Line references below refer to the private0210 decoded log; raw dumps, requests,
status files and downloaded binaries remain outside git. Only the single failed
pipeline request and its compiler status were read from HFS, besides SYSTEM.
No device write, reboot, BOOT backup or BOOT readback/hash occurs in this review.

| Evidence | Observation |
| --- | --- |
|247–260 | Actual602 color-only VS with the2448-byte ordered-fetch fragment passes full-target and same-job overlap; u16/u32 fractional-UV linear blur also passes. All four4096/4096, both fences complete, MMU0, immutable guards intact. |
|261 | Suite35/39. Same four old failures: RAW204 source-over, R8 partial scissor source-over, ordered-fetch noise full-target and overlap. |
|3247–3452 | Actual dynamic fragment programs864/3072/4672/2448 bytes are accepted. At3451 the2448-byte fragment links with static602, position-color ABI, no FS inputs and fetch enabled; combined pipeline accepted. No live submission for this pair is captured before the next abort. |
|3454–3458;3543 | `narrow_blur_19_frag_lph` pipeline rejects: `profile104: attachment1.pixelFormat actual=0 expected=80`. Backboardd[58] SIGABRT, namespace13/code4, Metal failed to build render pipeline. |
|6051–6155;7740–7832 | Two further backboardd SIGABRTs with the same backtrace and pipeline failure; heap records repeat the profile104 rejection, but the bounded live decision log is exhausted. |
|7834; exact HFS request/status | Automatic worker marks the blur render-pair request unsupported. Request confirms `downsample_blur_vert_lph` / `narrow_blur_19_frag_lph`, BGRA8 RT0 and absent RT1, with default no-blend state. Status says only the known fixed-function pairs compile through this worker branch. |
|1133–4198 |19 logged backboardd command buffers complete with status4/error0.41 logged native Submit18 phases succeed:19 profile602,15 profile605,3 profile603,4 clear/profile0. Logging is bounded; these are not whole-run totals. |
|1307;3733–3964 | Eight sampled4096-pixel source/panel checks match. GPU presentation continues through line10037, later FB intervals are zero. This is not proof of a full UI image. |
|10471–10490 | PosterBoard separately SIGTRAPs with `_stateLock_switcherConfiguration` assertion and no home/lock poster paths in heap strings; independent remaining blocker. |
|11822 | eMMC330,795 requests /7,301,397,504 read bytes /210,558,464 write bytes, errors0. Kernel/userspace activity continues; waiting longer does not repair the fatal pipeline descriptor mismatch. |

## Findings

| Priority | Finding and source evidence | Smallest next repair |
| --- | --- | --- |
|P1 | The inactive-RT1 adaptation is hardcoded to `downsample_8_frag_lph`/profile100 in `A5MaliMetalAPI.m:396–419`. Authenticated profile104 already has a5744-byte FS, logicalTarget0, secondary format80 and RT1 writeMask0. iOS omits RT1. This is a known program rejected by its descriptor contract, not a missing shader binary. | Generalize absent inactive-attachment normalization by authenticated profile/pass/write-mask metadata. Revalidate all other descriptor fields and extend auxiliary allocation/mapping/emitter gates, which currently also restrict this route to100. Test the exact captured104 descriptor and all qualifying profiles, including active-target/format/alias negatives and independent GPU pixel results. |
|P2 | `a5shader_requests.inc.m:945–961` accepts general dynamic **function** requests but does not compile arbitrary blur **pipeline** requests; this actual render pair receives unsupported. | Do not expect retries to fix the ABI. Connect already compiled blur programs to the normalized descriptor; independently broaden worker pair handling only with validated stage/resource contracts. |
|P1, separate | PosterBoard configuration assertion remains. dasd also has a SIGSEGV at8130; neither is the first confirmed Metal abort. | After the deterministic Metal admission blocker, inspect real poster configuration/state and the separate dasd stack; do not suppress assertions as a rendering fix. |

## Limits

Hardware pixel tests and the actual602 dynamic factory acceptance are new verified
milestones. Linear blur in a private GPU fixture does not prove a live blur100
submission: none is captured. Dependency tracking has no logged quarantine/error
in this run, but the bounded trace cannot establish every cross-queue wait.
After the three crashes the final backboardd process remains sampled in waits;
no new explicit reason for that final idle state is proven by this capture.
No new repair or image is installed in this log-analysis step.
