# 0185: exact generic fragment request and FP16 capability

The recovered request is `fixed_frag_lpf_cpf`, with 58 named constants and no
indexed constants. Only `fc_attachment_count=1`, `fc_blend_function=54` and
`fc_framebuffer_fetch=true` are nonzero. Constants retain their actual Metal
types: UChar (49), UChar3 (51, three bytes), and Bool (53).

The operator-supplied QuartzCore metallib has 141 entries. A real translator
lookup rejects `fixed_frag_lpf_cpf` as absent. It contains both
`fixed_frag_lph_cph` and `fixed_frag_lph_cpf`. Substituting one name for another
would change precision semantics; no such alias is implemented.

## Exact stock capability path

This analysis is bound to QuartzCore UUID
`9e40b2eb-260c-3af1-ae45-a1a551a8c1b9`.

1. `new_metal_context` calls `supportsNativeHardwareFP16` at `0x1884889ec`.
   It ORs that result with Apple-family-1 support and sets capability bit 20
   (`0x100000`) at `0x1884889f8`, storing the result at context `+0xa3c`.
2. `get_pipeline_spec` at `0x188483908–924` moves capability bit 20 to bit 4
   of the fragment specification at `+0xd`.
3. `create_fragment_shader` at `0x188485714–72c` selects a row using the inverse
   of that bit, and a column using fragment bit 12. The exact table at
   `0x1d5b48030` is:

   | Native-half row | CP half (bit12=0) | CP float (bit12=1) |
   | --- | --- | --- |
   | Native FP16 enabled | `fixed_frag_lph_cph` | `fixed_frag_lph_cpf` |
   | Native FP16 disabled | NULL | `fixed_frag_lpf_cpf` |

The observed `lpf_cpf` proves the CP-float bit is one. Enabling native FP16
therefore predicts **`fixed_frag_lph_cpf`**, preserving CP precision. This is
a capability correction, not a function-name substitution.

## Hardware/compiler evidence and scope

Released Mesa 26.2.4 `src/gallium/drivers/panfrost/pan_screen.c:582` explicitly
enables FP16 for Midgard, while separately withholding FP16 derivatives on that
architecture. The Midgard compiler supports native float16 operations and
half conversion/storage. Earlier phone shader suites successfully executed the
actual translated `lph` families, including RGBA16Float output with exact
half-element oracle comparisons. These establish an existing half-capable
compiler/hardware path; they do not establish execution of the newly requested
generic fragment or general derivative support.

The provider now explicitly returns YES for `supportsNativeHardwareFP16`.
Apple GPU families, feature sets, tile shaders and unrelated capabilities stay
unadvertised. Function specialization still requires authentic typed constants
and a real compiled variant; the capability fix does not bypass that boundary.

## What the request does not prove

`BlendFunction_codes[54]` is `non`, a sentinel for no fragment blend function.
It does not by itself identify fixed-function pipeline blending or a clear.
With framebuffer fetch enabled, `needs_attachment()` returns false immediately
at `0x1882d738c–3a4`; therefore false `fc_has_attachment_0` does not mean an
absent or disabled color target. The render-target pixel format and pipeline
blend/write-mask fields are outside this captured constant set.

Fragment creation precedes vertex creation in `create_pipeline_state`.
`fc_vertex_layout=0` identifies layout `sf`, not vertex shader type zero.
No exact vertex function or clear-shader equivalence is claimed from this
fragment-only capture.

## Local verification

`tools/test-a5mali-qc-fp16.py` verifies the operator image UUID, exact instructions,
precision table and the production provider override. It checks that the same
CP-float request changes from `lpf_cpf` to `lph_cpf`, while Apple-family support
remains false. This is a host/static regression. Device verification of the new
capability selection and subsequent live draw remains outstanding.

## Full recovered capture census

The complete 0185 recovery is flush 22, with no ring overwrite: 1,350 decoded
lines and 125,680 bytes. The census below covers that entire capture. It
precedes the native-FP16 capability correction described above; the captured
request still has the `lpf_cpf` name.

| Boundary | Observed result | Evidence limit |
| --- | --- | --- |
| Platform | Four CPUs initialized, SGI1 verified at line 99 | No new CPU-start panic. |
| Installer | Line 254: complete files=13, sync=0 | Existing provider/probe/compiler payload installation completed; no six-app reinstall in this capture. |
| Private GPU suite | Line 189: 21 passed / 21 evaluated / 21 cases; 44 fence-completion receipts | Independent shader/resource tests, not stock compositor submissions. |
| Device and limits | Stock device accepted at line 863; limits remain `max2D=2048/2048` | Discovery and the fullHD dimension correction remain active. |
| Warmup pipelines | 20 acceptance receipts across 12 profile IDs; no rejection receipt | Repeated warmup acceptances are not 20 unique shaders or proof of the live generic variant. |
| Live protection | Lines 960–961: command buffer 2 created, `requested=0 supported=0 committed=0 result=0` | The previously missing unprotected setter call passes. |
| Captured specialization | Requests 0 and 1, beginning at lines 962 and 1024 | Two identical captured attempts, not two different shader variants. |
| Crash census | Three backboardd SIGABRT headers at lines 1085, 1217 and 1316 | All share the same PC/LR and ten-entry backtrace. One failure family. |
| Exit reason | Lines 1112, 1246 and 1340: namespace 13/code 7, “Metal failed to specialize fragment function” | This is a reasoned function-creation failure, not a captured GPU execution fault. |
| Live submission | Zero stock commit, Query17, resource-operation and native-phase receipts | No successful stock Metal draw submission or rendered frame is established. |
| Framebuffer | 47 metric windows; zero swaps, presentations, superseded frames and copied bytes | Summed metric time is 249,992 ms, approximately 4.17 minutes. |
| Later allocator warnings | No failed contiguous-page allocation receipt | The long-run 0183 allocator issue is not observed or disproved by this shorter capture. |

All three crash stacks return through runtime `0x1a4f822ac`. Subtracting the
recorded slide `0x1cafc000` gives `0x1884862ac`, the same QuartzCore
`create_fragment_shader` terminal failure site identified in 0184. Its next
caller maps to `create_pipeline_state` at `0x188380d88`. No new independent
backboardd crash signature appears.

### Request completeness and duplicate handling

The two complete dumps each contain exactly 58 named constant records, report
`truncated=0`, and contain zero indexed constants. An independent comparison of
all `(name, type, byte-count, raw-value)` tuples found the two lists identical.
Only the following records are nonzero:

| Constant | Metal type | Bytes | Raw value |
| --- | --- | ---: | --- |
| `fc_attachment_count` | UChar (49) | 1 | `01` |
| `fc_blend_function` | UChar (49) | 1 | `36` (decimal 54) |
| `fc_framebuffer_fetch` | Bool (53) | 1 | `01` |

The presence of `constants=1` in the request summary is a boolean indication
that constant values were supplied; it does not mean that only one constant was
requested. The explicit subsequent count is 58. No values or types need to be
inferred from a warmup profile.

This closes the main observation gap in 0184: the failing function name and its
complete typed specialization set are now known. The static capability table
and real metallib lookup above establish why this selected name cannot be
resolved from the operator's source library. The capture does not establish
successful specialization or execution of the predicted `fixed_frag_lph_cpf`
replacement selection. Private Mac compilation results and a later phone test
must be recorded separately.

### Other process activity and errors

Execution receipts include 90 xpcproxy starts, four backboardd starts, three
ACCHWComponentAuthService starts and one each of many normal boot services.
Three backboardd processes crash in the saved window; the fourth starts near
its end. Execution starts are not additional crash events. There are no
PosterBoard or assetsd crash headers, kernel panics, SIGILL events, GPU faults,
GPU timeouts or unrecognized-selector messages in this capture. The previous
PosterBoard assertion and assetsd exception family were not retested here.

Initial preboot/factorydata mount, missing SEP, user-session/persona notification,
virtual-random and swap-file warnings remain. A cached heap-string scan again
contains the optional missing `kCMPhotoCompressionOption_RestrictedEncoding`
symbol; that string does not replace the explicit namespace-13 failure and its
complete specialization request. No texture, sampler or buffer factory rejection
receipt identifies a different live blocker in the saved window.

Four kernel button transition receipts are present. Near the end, HID forwarding
reports zero clients after the backboardd crashes. These events do not prove a
working user interface, and absence of visible response in this state is not
by itself evidence that the physical button driver stopped working.

### Remaining verification boundary

The next trial must first confirm actual selection of `fixed_frag_lph_cpf` with
the same CP precision and typed constants, then real function and pipeline
acceptance. A changed name alone is insufficient. No alias, dummy function,
dropped constant or fabricated success may substitute for an executable
specialized variant and its actual resource contract. Stock encoder creation,
commit, native submissions, terminal completion and a changed live frame remain
unproven.

This capture review only changes this document. It performs no source-code edit,
Git commit, build or device write.


## 0186 implementation after this capture

A source-only recipe reproduces the real LPH/CP-float specialization using the
complete captured typed constant contract. SPIR-V validation and released Mesa
T720 compilation pass; the exact native fragment is 848 bytes. Its optimized
native code reads only VAR0 color and UBO0 ColorWriteRule at byte68. Declared
fragment Buffer1 and constant-blob resources are dead for this fingerprint.
The 1808-byte candidate std_vert0_lph stage is also compiled from actual stock
source. Profile600 supplies a narrow valid API implementation for that pair:
original packing0, VB1 position/Half4 color, VB2 matrix, one BGRA8 target and
copy blending. Function constants and all pipeline state are strictly matched.
This supported pair is a host-tested implementation choice; the capture does
not prove the live iOS vertex, attachment or blend state matches it.

Host tests cover each changed constant, extra indexed values, authentic native
code, caller snapshots, the actual emitter, RT0-only query/submit, terminal
fences and transport errors. The kernel whitelist adds600 without reusing
existing resource-operation IDs500/501. No dummy function or name alias is
introduced. Real on-phone matching, submit completion and frame pixels remain
the next verification boundary.
