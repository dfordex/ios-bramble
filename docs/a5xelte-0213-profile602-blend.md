# 0213 profile602 blend rejection

## Evidence

The two recorded backboardd pipeline aborts contain the same retained factory
error: profile602 attachment0 has blending enabled, while its sole supported
attachment contract requires blending disabled. The first abort starts at decoded
line5066, with that mismatch at5093–5094 and5126–5127; the later abort starts at7702,
with the mismatch at7724–7727. Both termination reasons are `Metal failed to build
render pipeline`.

This is separate from the preceding render-resource allocation/import failures.
The capture establishes the first differing descriptor field. It does not expose
every factor of the rejected blend state because the factory diagnostics reached
their process limit.

## Implemented contract

Keep the authentic602 shader pair and typed specializations. The vertex exports
position, point size and one float4 colour. The fragment reads that interpolated
colour and the colour-write rule; it has no surviving sampled image, attachment
fetch, or fragment uniform-buffer1 read.

Add one supported RT0 equation to602 alongside its original copy state:

`result = source + destination * (1 - source.alpha)`

Both colour and alpha use ADD, ONE, ONE_MINUS_SOURCE_ALPHA. Other targets retain
their exact inactive descriptor defaults. Profiles600 and601 remain copy-only.
The registry generator and the native emitter each validate this complete narrow
contract. The renderer enables destination loads and performs the blend through
its existing native fixed-function equation. The fragment is unchanged, so the
blend is applied once.

A request with another operation, factor, write mask or inactive-target state
still fails validation. This extends implemented rendering support; it does not
ignore a descriptor mismatch or mark unsupported commands successful.

## Verification

The focused native wrapper test passed authentic library/function selection,
copy and source-over602 factories, real emitter submission, failure fences and
six incompatible blend states. The C descriptor test passed independent decoding of the
released Mesa renderer fields, checking destination loads, colour/alpha operands,
and unchanged shader bytes. Its copy602 descriptor remains byte-identical to the
original copy path.

The physical fixture uses the actual602 pair and production emitter. Two quads
have exact half-float premultiplied alpha0.25 and0.75 over a nonzero BGRA target.
Its independent oracle uses the equation above. A scissor border must remain
unchanged through destination preload; guard regions must remain intact. The GPU
input contains only the initial destination, never the expected result.

The refreshed29-profile factory test also passed, including the previously stale
604–606 executable expectations. The changed renderer compiled for iOS Cortex-A53.

Host tests and a generated physical fixture do not establish device success.
After installation, check the physical pixel comparison and whether backboardd
accepts its requested blend state without another pipeline abort.
