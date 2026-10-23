# 0200: two captured textured fragment variants

## Previous device result

The user confirms that 0199 displays the Apple logo in the correct orientation.
Its short SYSTEM capture recovers all 100,373 recorded bytes (100,128 decoded
bytes, 1,151 lines). The existing 603 job retains 29,457 colored pixels across
the full 2,073,600-pixel target; three logged SwapWait calls succeed and no
process crash or kernel panic is present in this short capture. This does not
cover the later failure stage from the complete 0198 trial.

The complete 0198 capture already identified nine backboardd aborts with
namespace 13/code 7, "Metal failed to specialize fragment function". Eight
complete request captures resolve to two exact variants of `fixed_frag_lph_cph`:

| Profile | Change from 603 | Actual fragment operation | Native FS |
| --- | --- | --- | --- |
| 604 | `fc_texture_function`: 1 to 3 | Texture3 sample multiplied by interpolated vertex color | 1,120 bytes, 6 registers |
| 605 | `fc_image_function0`: 0 to 29 | Texture3 R to RGB, G to alpha | 896 bytes, 5 registers |

All other 57 typed fragment constants match 603. These are independent actual
AIR translations and released Mesa 26.2.4 Midgard compilations. Neither uses
603's fragment code as a substitute. Both share the verified 2,192-byte vertex
program; their complete live vertex/render-state pairing has not yet been
observed because the previous provider rejected fragment specialization first.

## Implementation

- Add exact 604/605 typed constants, registry entries, stage hashes and cache
  validation; retain explicit format, attachment, resource and bounds checks.
- Bind UV VAR0 and color VAR1 for 604; 605 consumes UV VAR0 only. Keep the
  negative-Y viewport correction confirmed in 0199.
- Support BGRA8, RG8 and R8 input views for these new profiles using the actual
  T720 format/swizzle descriptors. The phone's eventual source format remains
  to be observed; RG8 support is not evidence that iOS has requested RG8 yet.
- Carry the profiles through real indexed/nonindexed submission, retained
  snapshots, Texture3/Sampler0 binding, Query17/Submit18 and terminal fences.
- Add authenticated generic604/generic605 recipes to the phone compiler and
  exact kernel installer allowlist (patch 0194). Its stage table contains a
  complete vertex/fragment pair for each of 602 through 605.
- Preserve the existing 21 private GPU cases byte for byte. Append two real
  emitted jobs with independent pixel oracles: asymmetric BGRA sample times
  Half4 color, and asymmetric RG8 sample mapped to RGB/alpha. Total: 23 cases.
  Generated Apple-derived binaries and raw captures remain outside Git.

## Local verification and image

- Both new AIR/SPIR-V modules validate; admitted normalized sampler variants
  produce byte-identical native code. Exact receipts and resource reflection
  validate in the registry generator (28 profiles).
- Full native API/transport tests pass with actual 603/604/605 code, including
  indexed draws, no-copy/buffer-backed views, BGRA/RG8/R8, source-over, resource
  bounds, late writes, error fences and lifetime handling. Mock transport does
  not establish device pixels.
- Cache positive/corruption/owner/mode/link/lifetime tests pass for 602–605.
  Host end-to-end 604 and 605 requests pass real AIR translation, SPIR-V
  validation, Midgard compilation and cache publication, including preceding
  unsupported requests. iOS compilation and five Mach-O signatures pass.
- Independent source review found no concrete API/fixture blocker. Exact
  kernel patch application matches the staged source.
- Final actual kernel installer preflight passes all 18 files: 39,544,246 raw
  and 9,456,212 packed bytes, within the existing 10 MiB packed limit.
  Production provider is 741,072 bytes; compiler runner is 128,032 bytes.
- Complete XNU make including symbols passes. BOOT is 30,341,136 bytes,
  within the 33,554,432-byte BOOT p10 capacity; tested four-core settings,
  existing apps, input and logging remain enabled.

The next device trial must prove the two new pixel cases, actual 604/605
specialization and pipeline acceptance, terminal GPU jobs and visible UI.
This build closes the two captured requests; it does not claim that every
future iOS shader or render state is implemented.
