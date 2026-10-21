# Bounded stock Metal phase logging

Requested after the0178 capture: pipeline factories succeed and the hardware
queue is ready, but no native completion or UI transfer is recorded. Existing
silent returns cannot identify whether stock iOS has reached command submission.

The next provider records metadata at the actual boundaries:

- Texture allocation/import rejection, including dimensions, format, storage,
  usage, mip count and row layout; no pixel bytes.
- Sampler rejection with actual filter/address/LOD settings.
- Command queue/buffer creation and an explicit unsupported unretained-buffer
  request.
- The first command-buffer encoding error and public selector.
- Commit begin/result, with actual encoder, draw and queued-operation counts.
- NativeQuery17 begin/result and request/reply validation phase.
- Clear/blur/misc/path query, runtime encoding and native submission results.

Atomic category budgets bound repeated messages; a local command-buffer number
correlates API phases. Query receipts pair begin/result. These identifiers are
process-local counters, not device identifiers or resource contents.

Return values, supported operations, resource ownership and GPU completion
requirements remain unchanged. An accepted pipeline or successful empty commit
must not be interpreted as a rendered frame. A future capture must connect an
actual queued draw to terminal GPU fences and display transfer separately.
