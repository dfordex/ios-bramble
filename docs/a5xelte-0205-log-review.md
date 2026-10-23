# 0205 device review: A8 passes; next fragment blocks backboardd

## Result: incomplete UI, next rejection identified

The user reports the screen remains at the spinner. A read-only TWRP capture
recovers all902,632 recorded ring bytes at flush86,902,387 decoded bytes and
8,776 lines. There is no overwrite. Framebuffer metric windows total890,901ms
(about14m51s); summed windows are not an exact boot duration. No write, flash
or reboot was performed during this review. Raw logs and complete extracted
typed captures remain private, outside Git.

## Evidence

Line numbers below refer to that private decoded capture.

| Evidence | Result |
| --- | --- |
| Lines199–205 | Both new606 full4096-byte A8/clamped-UV copy and source-over oracles pass; immutable regions and terminal fences pass. Suite25/25 passes. |
| Line280 | Embedded installer completes19 files, sync0. |
| Lines3315–3318 | Actual576x301/row576/offset64 A8 texture accepted; actual606 specialization and pipeline accepted; next763x79 A8 texture accepted. |
| Lines3319–3442 | Next `fixed_frag_lph_cph` request is forwarded then rejected. Two complete58-constant, no-indexed-constant captures are identical. |
| Lines3443–3518 | First backboardd SIGABRT, namespace13/code7, `Metal failed to specialize fragment function`. |
| Lines6537,8250 | Two later backboardd aborts have the same reason; their exact constant sets are not fully logged. |
| Lines4909–4974,8746 onward | Two PosterBoard SIGTRAP records at preferred0x1c1778268; first heap scan includes `!_stateLock_switcherConfiguration`. Last scan ends at capture boundary. |
| Line8706 | Storage191,813 requests,4,242,136,576 read bytes,103,454,720 write bytes,0 errors. No kernel panic or nonzero logged GPU MMU fault. |

## Findings

### P1: another exact alpha fragment is missing

Comparison against the0204 capture used for606 proves only one of58 typed
constants differs: `fc_coord_function0` UChar changes05 to00.
`fc_image_function0` remains11 hex (17 decimal); every other typed value and
width is identical. The new request is thus coord0/image17, whereas606 is
coord5/image17. It must be independently translated, reflected, compiled and
bound; it cannot be admitted by substituting606 code with its live UV-clamp B1.

The first compositor command buffer containing the accepted606 pipeline is
not observed reaching native submission before the next specialization abort.
Later cb5 records belong to the restarted process and submit602/605. There is
no logged live606 submission in this capture. Its private GPU pixels and live
pipeline acceptance are verified separately; full compositor consumption is
still pending.

### P1: automatic compilation does not yet handle this new function request

`A5MaliMetalLibrary.m:263` forwards rejected single-function specialization
requests, but `ios/a5shader_requests.inc.m:80` admits only exact known complete
pipeline pairs. The known recipes stop at606. Therefore an arbitrary new
standalone fragment cannot become usable simply by waiting for the current
service. The service is not a general shader compiler/admission path yet.

The current run logs AIR translation still RUNNING at332.7s, with no new
PUBLISHED record. The log does not identify that active compiler request, so
it must not be described as compilation of this new fragment. Earlier
phone-compiled602/603/604/605 caches bind; those are existing publications.

### P1: PosterBoard has a separate unresolved state assertion

The preferred crash address and first assertion string match the previous
first-time switcher-configuration failure. This is independent of the captured
backboardd shader rejection. Fixing the new shader is necessary for the first
observed backboardd abort, but is not proof that PosterBoard or the complete
home-screen sequence will then work.

## Working paths and next action

Bounded logs contain27 completed/error0 command-buffer receipts and48
successful misc-submit18 receipts:602x25,603x2,604x1,605x20. These are logged
records, not exhaustive job counts. Source23/panel4096-sample checks match.
The physical GPU and scanout path are active; a global GPU hang is not shown.

Implement the exact coord0/image17 fragment with its actual resource contract
and extend compilation/admission to handle the rejected function stage without
inventing a vertex pairing or returning success for missing code. Keep the
passing606/A8/storage regressions. Investigate PosterBoard's state assertion
separately. No new BOOT image is prepared or installed by this analysis.
