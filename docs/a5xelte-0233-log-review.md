# 0233 phone result and plain-function loader follow-up

## Observed phone behavior

The user sees volume-key HUD drawings, intermittent spinner and a mostly black
App Library transition. This is real incremental rendering, not a complete UI
or smooth animation result.

The complete recovered SYSTEM ring contains 11,360 lines without wrap. All
1,822 recorded GPU fences complete, with zero nonzero MMU status fields. The
145 framebuffer intervals include 104 with zero swaps; the highest interval
reports17fps. These counters are intermittent and do not establish steady17fps.
Input continues:39 touch and120 HID key receipts remain in the saved log.
No kernel panic is recorded.

Three process failures are recorded:

- SpringBoard SIGTRAP at the previously classified FrontBoardServices null
  `processIdentity` assertion. The underlying missing identity remains unknown.
- Backboardd SIGABRT, termination namespace13/code2: `Metal failed to load fragment function`.
- A subsequent SpringBoard SIGABRT includes AttentionAwareness configuration
  failure and interrupted-connection strings. Temporal order does not by itself
  prove this is caused by backboardd's death.

Two nonindexed `drawPrimitives:vertexStart:vertexCount:` calls separately report
Unsupported. Nearby successful pipeline messages do not identify the rejected
calls. The old resource-rejection logger explicitly excluded nonindexed draws,
so the saved log lacks their precise resource/argument reasons.

## Compiler result

The previously waiting fragment completes real on-phone AIR translation,
validation and native publication. One recorded translation takes282.137s wall
but approximately9.941s CPU, followed by9.430s native compilation wall time.
This proves eventual completion, not that CPU compilation itself consumed the
whole delay. Process samples still show background priority4; the reason for
that task policy is unresolved.

Bounded read-only project-cache recovery also verifies a genuinely published
1008-byte shader-blend variant with the requested inverse-destination-alpha
source factor and destination factorOne. Successful publication is not proof
of correct pixels for every later compositor draw.

## Exact backboardd call-path classification

Bounded read-only QuartzCore code/table pages were inspected privately. The
backtrace lands in the fragment loader at unslid0x18848566c, via0x188380d84.
The namespace/code selection at0x188486044..0x188486050 uses code2 when the
constant-values pointer is nil and code7 when nonnil. The helper at0x188482774
constructs a function descriptor and invokes the library's descriptor API.
Thus this particular abort is the **plain function-loading path**, not the
already handled fixed-fragment specialization failure.

The corresponding source table includes named downsample/blur, gradient,
alpha/color and path functions. The exact selected function name is absent
from the runtime log. No individual table entry is claimed as the culprit.
Raw code pages, tables and device logs remain private and are not committed.

## 0234 source follow-up, not installed

- Parse NAME/TYPE from the complete SHA-verified stock MTLB function directory.
  All141 entries are enumerated. Vertex/fragment stage selection uses the
  directory, replacing substring guesses. Kernel functions remain unsupported.
- Forward an unregistered plain vertex/fragment load through the same genuine
  request/cache/worker path used by typed specialization. Return actual native
  code or a terminal error; no synthetic successful function is returned while
  compilation is pending. Known required-constant functions still reject a
  missing constants object.
- Supply the real opposite-stage companion's required constants during
  translation. Previously a plain fragment left the scaffold vertex constants
  unset. Requested constants retain precedence; only the requested stage is
  published.
- Give nonindexed resource failures and actual rejected draw arguments bounded,
  independent receipts. Draw admission gates are unchanged.
- Label a registry miss as a registry miss, rather than reporting an eventual
  successful dynamic request as Unsupported.

## Verification and remaining limits

- Existing52 captured complete pipelines pass the actual provider factory.
- A real stock `attachment_clear_frag_lpf` absent from the compiled registry is
  translated, SPIR-V validated, compiled to288 native bytes and published by
  the actual worker. Provider tests consume that unchanged publication through
  name, descriptor and empty-constant APIs. Catalog count, nonexistent names
  and missing required constants are also checked.
- The asynchronous library/method contract suite passes.
- Signed iOS16/Cortex-A53 provider and worker build;4KiB signature pages verify.
- Additional actual plain-stage trials expose remaining compiler limitations:
  alpha-threshold, upsample and home-affordance stages reject their fixed
  translation companion with UnmatchedVarying. P3-clamp passes AIR/SPIR-V but
  rejects an unimplemented native descriptor kind. These are not accepted as
  executable pipelines and are not known to be the phone's exact failing name.

This follow-up closes forwarding/discovery and companion-constant omissions,
but **does not establish general plain-stage translation or a fixed phone UI**.
The next device receipt must identify the actual requested function and the
nonindexed draw rejection. A BOOT image was neither prepared nor flashed in
this readout/follow-up;0233 remains the installed checkpoint.
