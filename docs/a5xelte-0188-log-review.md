# 0188: installer rejected the payload before the new provider ran

SYSTEM recovery is flush46:183,306 recorded bytes, all2,206 decoded lines /
183,061 decoded bytes, without overwrite. This was a read-only recovery.

## Observed result

| Question | Evidence |
| --- | --- |
| Did the new vertex run? |No. Line233: `payload preflight error=22; no files changed`. The existing provider still rejects `fixed_vert_lph_spc` with its unchanged4zero constants.|
| Did iOS submit a draw? |No recorded commit, native phase, Query17 or Submit18. All92 frame/presentation windows remain zero over489,323 summed ms.|
| Did automatic compilation run? |No new request/PUBLISHED/cache-bound marker. The old helper starts and records three old selftest cache hits, which do not establish the new `--serve` path.|
| Crash family |18 backboardd signal6 aborts, all namespace13/code6: Metal failed to specialize vertex function. No kernel panic captured.|
| Independent GPU tests |21/21 passed/evaluated;44 terminal fence receipts with header1/MMU0. These remain separate from compositor work.|

The previous BOOT write succeeded, but its embedded provider/compiler installation
did not. Thus this boot cannot test the new602 function implementation or the
automatic compiler/cache route. Existing root files were retained by the
preflight's no-write failure path.

## Concrete cause and repair

The embedded15-file package added exactly two destinations:

- `/usr/libexec/a5shader/generic602.json`
- `/usr/libexec/a5shader/midgard-generic602`

The package generator admitted them, but the kernel installer's exact path
allowlist did not. This was a missed installer integration step. The existing
preflight returns EINVAL before creating directories or changing files whenever
any payload path is outside that list. It is not evidence of a new GPU error.

Patch0188 adds only those exact two paths and a bounded rejected-path diagnostic.
The provider, compiler tools, native shaders and15-file payload remain unchanged.

The actual kernel preflight was extracted and compiled on the host with its
real private payload and real zlib streams. The original functions reproduce
EINVAL22. The patched functions accept all35,324,002raw /8,908,912packed bytes;
wrong siblings/traversal/child paths, duplicate destinations, invalid modes and
corrupted compressed streams still reject. The compiler stream rewind also
preserves the exact first decoded chunk.

The package generator now requires `--installer-source` for this automatic
compiler package. It runs the actual staged installer preflight against the
generated include before reporting packaging success. A nonzero result stops
the package step, rather than leaving this check until phone boot. This check
performs no filesystem installation or device writes.

0188b must demonstrate `install: complete files=15 sync=0`, the new provider's
vertex602 acceptance and subsequent live pipeline/submit results. Automatic
compilation additionally requires queued requests, `PUBLISHED profile=602` and
the independent `compile cache: bound ... source=phone-compiled` marker.
