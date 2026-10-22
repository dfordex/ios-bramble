# 0184 full log review — 2026-10-22

## Verdict: protection options now pass; live fragment specialization fails

The complete recovered capture contains 1,517 lines and 152,176 decoded bytes
(flush 29, no ring overwrite). The raw SYSTEM readout is 4,194,816 bytes,
including its header and bounded log window. This review used the entire
capture, not only its final crash message.

The 0183 missing-selector exception is gone. Stock backboardd creates its next
command buffer and requests protection options **0**; the provider returns
success. Execution then reaches a different failure in QuartzCore:

```text
Metal failed to specialize fragment function
```

There are six backboardd SIGABRT events, all with the same backtrace and exit
reason namespace 13/code 7. No stock commit or GPU submission receipt appears.
The result advances the demonstrated API boundary but does not establish a
live frame rendered by Mali.

## Full capture census

| Boundary | Evidence | Interpretation |
| --- | --- | --- |
| Platform | Line 96: four CPUs initialized, SGI1 verified | No new CPU-start failure. |
| GPU suite | Line 189: 21 passed / 21 evaluated / 21 cases | The private shader/resource cases still pass; compositor coverage remains separate. |
| GPU completions | 44 fence-completion receipts, successful headers and zero MMU status | These correspond to the private suite, not demonstrated stock draw submissions. |
| Installer | Line 254: complete files=13, sync=0 | Updated bundle installation completed; this capture does not reinstall the six previously restored apps. |
| Limits | Lines 895, 904, 1075 and 1226 show `max2D=2048/2048` | The fullHD surface cap fix remains active. |
| Device | Line 906: stock Metal device accepted | Device discovery/acceptance remains successful. |
| Warmup pipelines | 42 acceptance receipts across 12 profile IDs; no rejection receipt | These are repeated preparations, not 42 unique shaders or live draw proof. |
| Live command buffer | Lines 1001, 1134 and 1284: `commandBuffer cb=2 created=1` | All three captured protection receipts occur after the new live command buffer is created. |
| Protection setter | Lines 1002, 1136 and 1285: `requested=0 supported=0 committed=0 result=0` | The unprotected state is accepted before commit. This does not claim protected-resource isolation. |
| Crash events | Six backboardd SIGABRT headers at 1006, 1137, 1286, 1409, 1474 and 1507 | One repeated fragment-specialization failure family. |
| Stock submission | Zero commit, Query17, resource-op or native-phase receipts | No stock GPU rendering or successful submitted frame is established. |
| Framebuffer metrics | 59 windows; 0 swaps, 0 presentations, 0 copied bytes; summed metric time 314,562 ms | Approximately 5.24 minutes of metrics show no presentation in this capture. |
| Allocation warnings | No `vm_page_find_contiguous` failure receipt | The earlier long-run allocation issue is not observed here; the shorter capture cannot prove it fixed. |
| Other executions | 125 xpcproxy, six backboardd, six ACCHWComponentAuthService, five fairplayd.H2, three SpringBoard starts | Execution counts, not independently diagnosed crash counts. |

The accepted profile IDs are 99–108, 206 and 207. Profiles 99 and 100 each
appear six times; the other ten appear three times. Neither a warmup function
name nor the last accepted profile identifies the later failing live fragment.

## The protection repair is observed at the actual live call

Immediately before the first failure, backboardd creates surface 23 as
1080×1920 BGRA, row stride 4352 and allocation size 8,355,840 bytes
(line 997). It then creates command buffer 2 and receives successful handling of
`setProtectionOptions:0` at line 1002. There is no unrecognized-selector message
anywhere in the capture.

In 0183 the same command-buffer transition aborted inside this setter. In 0184
the log records the requested value and success, then reaches a later
QuartzCore fragment-creation failure. This is direct evidence that the observed
unprotected call crossed the previous missing-method boundary. It does not
prove that arbitrary nonzero protection options or every later command-buffer
method is implemented.

## Exact new failure boundary

All six crashes have the same runtime PC/LR and ten-entry backtrace. Their exit
reason is explicitly namespace 13/code 7 with the fragment-specialization text.
The first crash uses shared-cache slide `0x22b54000`:

| Runtime return address | Preferred image VA | Symbol |
| --- | --- | --- |
| `0x1aafda2ac` | `0x1884862ac` | `CA::OGL::MetalContext::create_fragment_shader(FragmentShader::Spec const&, bool) + 3136` |
| `0x1aaed4d88` | `0x188380d88` | `CA::OGL::MetalContext::create_pipeline_state(Pipeline::Spec const&, unsigned int*, std::atomic<bool>*) + 500` |

The exact unmodified iOS16 QuartzCore disassembly shows a
`load_shader_function(...)` call at `0x188486084`, a nil-result branch after it,
and error formatting through `0x18848608c–0x1884860dc`. The terminal path sets
exit namespace 13 at `0x188486298` and calls the reasoned-exit routine at
`0x1884862a8`; `0x1884862ac` is the captured return address immediately afterward.
Thus this is a function-creation/specialization failure before a completed live
pipeline and draw submission, not a sampled Mali shader execution fault.

The exact error-code selection at QuartzCore 0x188486044–0x188486050
identifies the generic function-constant branch (code 7), rather than a direct
fast shader without constants (code 2). The caller stack continues through
MetalContext::draw, so this is synchronous live drawing, not the asynchronous
warmup. The current library factory unconditionally rejects a nonnull constants
object; none of the generic fixed_frag variants has an authenticated compiled
profile. This is a concrete missing specialization implementation.

The recovered log does **not** contain the failing fragment function name,
requested specialization constants, library/profile identity or provider NSError.
The kernel exit string alone cannot distinguish an unknown function name,
a rejected constant set, an unauthenticated library/profile, or another
function-factory contract failure. Naming an arbitrary shader or bypassing
specialization would exceed this evidence. The warmup's accepted fragment list
must not be substituted for the missing live request.

## Other errors and comparison limits

No PosterBoard crash, assetsd crash, kernel panic, SIGILL, GPU fault or GPU timeout
is captured. PosterBoard does not execute during this shorter window, so the
0183 PosterBoard state assertion was not retested. The assetsd exception family
and later contiguous-page failures from the nine-hour 0183 capture are likewise
not disproved by their absence here.

The same initial preboot/factorydata mount, persona/notification, missing SEP,
virtual-random and swap-file warnings remain. Cached backboardd heap strings
mention a missing `kCMPhotoCompressionOption_RestrictedEncoding` symbol; this is
not a replacement for the explicit live namespace-13 specialization failure.
Button down/up events are logged at lines 824–830; these do not establish
compositor or touch-response success.

## Next concrete observation

Capture the bounded live function-factory request before it returns nil:
function name, exact specialization index/name and type metadata, authenticated
library/profile identity and concrete NSError. Match that request to the actual
source AIR and supported native resource/pipeline contract. Only then select the
missing implementation or correct a proven ABI rejection.

The next successful boundary must include specialization success, pipeline
acceptance, encoder creation and an actual stock commit/native submission.
A terminal fence and a changed live frame are still required before claiming
that iOS drawing runs on Mali. This review makes no such claim.

No code edit, build, commit or phone write was performed for this review.
