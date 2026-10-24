# 0227 full device readout

## Capture and successful checkpoints

SYSTEM flush59 recovers all789,134 logical bytes /9,077 lines without ring
overwrite. Recovery/model/SYSTEM guards preceded a read of only the first8,193
sectors. A separate bounded read retrieves the exact logged project pipeline
request/status, reading140,288 physical bytes including HFS catalog nodes.
No partition writes or reboot occurred during this review. Private capture and
shader request files remain outside git.

- All367 installation files complete with sync0. The new2,464-byte publication
  is written at lines530–532 and accepted by backboardd at5084. Its single-UV
  dynamic pipeline is accepted at5087 with stride48.
- Seventy-five captured command buffers finish `status=4 error=0`. Successful
  native dynamic-profile emitter calls occur alongside static602–606 calls.
- Eight sampled source/panel comparisons have zero RGB/alpha mismatch. This
  proves those samples, not complete UI rendering or responsive interaction.
- No captured kernel panic, MMU fault or import failure. Threshold markers reach
  33/64; import eviction/reuse is still not physically established by this run.
- 31 HID touch and268 HID key records show input arrival.

The prior attribute3 offset8/32 rejection does not recur. However, a complete
stride16 acceptance receipt is not captured; accepted-message and stdout budgets
can exhaust during startup. Absence of that rejection alone does not establish
that the exact packed pipeline was exercised. The earlier host replay remains
the direct verification of that descriptor.

## Current recorded failure

Backboardd aborts at5095; its reason at5190 is now namespace13/code7:
`Metal failed to specialize fragment function`. This differs from the previous
namespace13/code4 pipeline-construction failure. The exact function identity and
provider NSError for this abort are not captured. Do not describe it as a known
new backend instruction failure or equate it with a later unsupported pipeline.

Immediately before the abort, lines5087–5088 reject a real buffer-backed37x37
texture, pixel format70 (RGBA8Unorm), row192, image7,060 bytes, buffer8,192 bytes.
Both linear-texture and allocation gates reject `pixel-format`. This is a
confirmed missing texture path. Its causal connection to the subsequent fragment
specialization abort is not proven by ordering alone.

SpringBoard separately aborts at5203 after an explicit AttentionAwareness
connection/proxy `NSInvalidArgumentException` at5196. It must not be reported as
the earlier FrontBoardServices null-processIdentity assertion.

## Queue pressure and unsupported request

The compiler first scans64 requests with `capped_users=1` (line5022), then retires
old entries; later scans contain62. No new function compiler child/publication
is recorded during this run. An `UNSUPPORTED` record at8621 was recovered along
with its exact request/status. It is a **full pipeline** and retains the old
exact602–606 typed-pair compiler restriction. It is not a newly failed standalone
fragment compilation, and is not sufficient to identify the first abort.

Source inspection exposes a relevant admission hazard:

- `A5MaliMetalAPI.m` forwards complete pipeline snapshots **before** checking
  whether the existing factory can already execute the pipeline.
- `A5MaliShaderCompileRequest.m` counts64 requests and returns ForwardFailed at
  the limit, rather than a retryable Busy result.
- `A5MaliMetalLibrary.m` immediately returns nil if forwarding a genuinely new
  function fails. That can produce the observed specialization failure class.

The full queue is device-observed and this failure path is source-confirmed;
the exact failing function's forwarding error is not captured, so quota remains
a candidate cause of this specific abort rather than a proven attribution.

## Next work

Implement the real RGBA8 source path, preserving channel order through texture
admission, resource mapping and native sampling. Prevent already executable
pipeline snapshots from consuming function compilation capacity, make transient
queue pressure retryable for functions, and retain an independent bounded
terminal specialization receipt with request ID/error before returning nil.
Those changes address the observed unsupported format and remove a concrete
queue failure mechanism; this readout does not implement or install them.
