# 0186: observed CP-half request and corrected FP16 branch model

The complete recovered capture is flush 37: **1,772 decoded lines, 153,257
bytes**. The phone now requests **`fixed_frag_lph_cph`**, not the CP-float name
predicted in the original 0185 review. Both complete requests carry the same 58
typed named constants as 0185, with no indexed constants. This confirms a real
precision-selection change; it does not establish successful specialization or
a live compositor draw.

## Correction to the 0185 prediction

The earlier model traced native-FP16 capability bit20 into fragment bit4, then
incorrectly held fragment bit12 constant. It omitted the second use of the
native-FP16 result later in `get_pipeline_spec`. That omission also affected the
original regression tool. Both the historical document and the tool are now
explicitly corrected; the historical CP-float host compilation remains a separate
artifact, not an implementation of the CP-half request.

This analysis uses the operator-supplied QuartzCore image with UUID
`9e40b2eb-260c-3af1-ae45-a1a551a8c1b9`. Addresses below are its preferred virtual
addresses, not slid phone addresses.

| Stock location | Exact effect relevant to precision |
| --- | --- |
| `0x1884889ec–a50` | Constructor queries `supportsNativeHardwareFP16`, ORs Apple-family-1 support, and stores capability bit20 at context `+0xa3c`. The provider explicitly supplies native FP16 while Apple families remain false. |
| `0x188483908–924` | `get_pipeline_spec` moves context bit20 to fragment-spec bit4. The resulting `w16` is zero or `0x10`. |
| `0x188483a70–a78` | If `w16` is zero, force `w8=0x1000`: CP-float bit12 is one regardless of the precision configuration. |
| `0x188483a7c–a94` | Otherwise, initialize the once-controlled configuration if needed, load its byte at `0x1e1df7118`, and shift it left12. |
| `0x188483c78–c8c` | The once path initializes through the block at `0x1d5b491c8`, then returns to the configuration-byte load. This review does not infer an external preference name from that byte. |
| `0x188483a98–acc` | Merge the precision result and other reviewed spec fields, then store the fragment-spec halfword at `+0xd`. The other final merged context fields are masked to bits13 and14, not CP bit12. |
| `0x188485714–72c` | `create_fragment_shader` selects table row `!bit4` and column `bit12`. |

The actual four-entry name table at `0x1d5b48030` therefore produces:

| Native FP16 (Apple-family-1 false) | Configuration byte | Selected name | Evidence |
| --- | ---: | --- | --- |
| false | 0 | `fixed_frag_lpf_cpf` | Forced CP-float branch; 0185 observed this name. |
| false | 1 | `fixed_frag_lpf_cpf` | Same forced branch; configuration does not participate. |
| true | 0 | `fixed_frag_lph_cph` | Actual 0186 request. |
| true | 1 | `fixed_frag_lph_cpf` | Valid alternative branch in the stock image; not observed in 0186. |

Thus 0185's `lpf_cpf` did **not** prove that enabling native FP16 would preserve
CP-float. The actual 0186 selection is consistent with configuration zero in the
newly reachable branch. No function-name substitution, Apple GPU-family claim,
or precision coercion is needed or justified.

## Complete capture census

| Boundary | Observed result | Scope |
| --- | --- | --- |
| Private GPU tests | Line189: 21 passed /21 evaluated /21 cases; 44 completed fence receipts | Independent GPU pixel tests, not compositor submissions. |
| Installer | Line254: complete files=13, sync=0 | Payload installation completed. |
| Limits | Lines852,862,1203: `max2D=2048/2048` | Earlier fullHD dimension fix remains active. |
| Device | Line864: stock Mali-T720 device accepted | Device acceptance remains distinct from function/pipeline acceptance. |
| Warmup | 20 accepted-pipeline receipts across 12 profile IDs | Repeated acceptance receipts do not establish live generic shader coverage. |
| FullHD backing | Line995: 1080×1920 BGRA IOSurface, row4352, size8,355,840 | The live path progresses past the original dimension rejection. |
| Live command buffer | Line1002: command buffer2 created | Three command-buffer creation receipts in the whole capture. |
| Protection | Line1003: requested0, supported0, committed0, result0 | One captured receipt; the zero-protection setter no longer aborts. |
| Generic specialization | Lines1004 onward: request0 `fixed_frag_lph_cph`, unsupported | The failure is still function specialization, before stock commit. |
| Exact request dumps | Two complete named sets of58, `truncated=0`; two indexed sets of0 | 116 named-key records, 122 specialization lines total. Both sets equal 0185's typed constants. |
| backboardd crashes | Nine signal6 headers and nine namespace13/code7 reasons | Every reason is “Metal failed to specialize fragment function”; all nine share one ten-entry backtrace. |
| Stock GPU submission | Zero commit, Query17 and native-phase receipts | No successful stock draw submission is established. |
| Frame metrics | 75 swap windows and75 presentation windows, all zero | Zero swaps, shown frames, copied bytes and GPU/CPU presentations over399,987 summed ms (about6.67min). |
| Kernel/allocator | No kernel panic or failed contiguous-page-allocation receipt | Absence in this capture does not disprove longer-run issues. |

All nine crash stacks contain runtime `0x1c6d6e2ac`. Subtracting slide
`0x3e8e8000` gives **`0x1884862ac`**, the already identified
`create_fragment_shader` failure site. The next QuartzCore caller is
`0x188380d88`, `create_pipeline_state`; the following draw caller is
`0x1882cbf64`. These are repeated observations of one failure family, not nine
independent defects.

Execution receipts include ten backboardd and five SpringBoard starts. Starts
are not additional crash records. Private test fence completion and stock
device acceptance do not override the zero live-submission/frame results.

### Exact specialization contract

Both captures preserve UChar type49 (one byte), UChar3 type51 (three bytes), and
Bool type53 (one byte). Only these three records are nonzero:

| Name | Type | Bytes | Raw value |
| --- | --- | ---: | --- |
| `fc_attachment_count` | UChar49 | 1 | `01` |
| `fc_blend_function` | UChar49 | 1 | `36` (decimal54) |
| `fc_framebuffer_fetch` | Bool53 | 1 | `01` |

All other captured constants, including `fc_vertex_layout`, are zero. An exact
comparison of the `(name,type,byte-count,raw-value)` tuples from 0185 and0186
finds no change. `constants=1` in the summary indicates a supplied constant
object; it is not a count of one constant.

The captured request alone still does not identify the live vertex function,
target pixel format, pipeline blend/write masks, or prove equivalence to a
clear shader. The genuine `fixed_frag_lph_cph` specialization must be compiled
and admitted under its actual complete pipeline/resource contract. CP-float
profile600 cannot be reused by aliasing this name. Any newly prepared CP-half
profile needs its own host validation and subsequent phone evidence.

## Focused regression verification

`tools/test-a5mali-qc-fp16.py` now UUID-checks the stock image, guards every
instruction in `0x188483a70–acc` plus the once path, verifies the exact name
table, and models all four native-FP16/configuration0-or1 combinations. It also
checks the explicit provider FP16 override and unchanged false Apple-family and
feature-set methods. The corrected test passes against the operator image.

This review changes only source analysis and that regression tool. Production
device code is unchanged; no additional build, commit or device write is
performed here. Runtime evidence confirms the selected CP-half name, not a
working CP-half pipeline or displayed frame.
