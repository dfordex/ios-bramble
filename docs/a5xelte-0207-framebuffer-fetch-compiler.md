# 0207 ordered color fetch: compiler implementation and host evidence

The failed0206 fragment now translates and compiles on the host. This closes
the observed AIR/compiler refusal; GPU execution and a complete iOS frame are
separate device gates.

## Actual lowering, rather than a capability-only change

The pinned metal2vulkan source already implements ordered color input as
`SubpassData`/`OpImageRead`, `GraphicsState.input_attachments` and
`rasterization_order_attachment_access`. The dynamic worker derives a private
translation profile exposing only rasterization-order **color** access. Its
installed baseline profile stays unchanged for the existing602–606 recipes.

Both reflected-manifest generators require one float color0 input, one sample
and ordered access. The backend checks the actual SPIR-V/NIR descriptor,
attachment index and zero XY offsets, then emits `nir_load_output` for color0.
Released Mesa26.2.4 Midgard emits the tilebuffer wait and the T720-specific
`ld_special` load for this operation. It is not converted into an unordered
sampled framebuffer texture. Runtime preload and ordered rasterization are
required in the corresponding emitter.

The captured shader also exposes genuine additional contracts:

- Texture3 with application Sampler0, plus Texture9 with an immutable nearest,
  normalized Repeat sampler, LOD0..0.25.
- Pixel position, mapped to native fragment input2 so it cannot collide with
  UV input0. The existing position/color/UV conventions otherwise remain.
- A two-byte readonly half uniform, represented by one four-byte native UBO
  word. Native metadata reports `min_bytes:4, logical_bytes:2`; the runtime
  must copy only the two app bytes into a zero-padded native snapshot. This
  narrow two-byte case does not round arbitrary truncated buffer windows up.
- A4672-byte native fragment, first tag8,14 work registers, two textures and
  samplers, no TLS or WLS. Dynamic code is bounded at8192 bytes. The native
  first tag is checked against the executable's actual first byte.

Nonzero attachment offsets, other attachments, multisample fetches, writable
images and unsupported sampler/resource forms remain errors.

## Cache upgrade and reproducible packaging

New dynamic receipts include `support_generation:2`. Previously completed
stages remain usable. Only matching old failed fragment requests explicitly
requiring a destination fetch may be retried once: the public failure and its
matching root-private status are exclusively renamed and preserved. A crash
between the two renames resumes; a new-generation failure stays terminal.
This does not bump the global compiler ABI or discard successful caches.

Temporary build files were lost. Public pinned translator/Mesa/toolchains were
restored, and the stock library plus installed recipes/validator were recovered
from the existing HFS root. `rebuild_recovered_package.py` preserves each old
recipe byte for byte only after current AIR translation, real `spirv-val`,
native recompilation and reflected layouts match committed source pins.
It does not fabricate missing original capture files or bypass their checks.

## Gates actually run

- The actual previously failing request passes AIR translation and Vulkan1.2
  SPIR-V validation, then produces the4672-byte native stage above.
- Real worker publication passes old-generation retry, interrupted-retirement
  recovery and current-generation terminal-failure tests. Its actual fragment
  receipt, reflection and native bytes are published through the normal path.
- Three authored native fetch shaders compile: destination-half; destination
  half plus one UV sample; and that sample plus a second immutable-sampler
  texture indexed by pixel position. Six actual malformed SPIR-V/manifest
  cases reject, as do four malformed reflected fetch contracts.
- The existing four-stage dynamic backend regression, eleven malformed ABI
  cases and unsupported-sysval test pass; the old static pair remains byte
  identical.603/606 vertex and fragment hashes match their committed pins.
- The full existing worker regression passes known606 compilation, unknown
  fragment/vertex publication, malformed requests and failure/restart handling.
- All five recovered602–606 pairs retranslate, validate and recompile to their
  exact existing SPIR-V/native pins and layouts. Cortex-A53 iOS AIR/backend
  and production worker build; all five compiler executables pass strict
  signatures and4096-byte code-signature page verification.

Physical overlapping-fragment, two-texture/RGBA16F, pixel-position and final
compositor results must be recovered from the next device run. None is implied
by these host checks.
