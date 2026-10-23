# UniXNU NativeMetal comparison for A5XELTE

Inspected2026-10-24: public NativeMetal source commit
`c6d29caad6d880cc8204ebe3bc34d77479a3255d`, cloned privately for read-only
comparison. UniXNU documents a GPU-composited desktop on sheng/Adreno740;
that project claim is separate from our A5XELTE hardware verification.

## Useful source patterns

- `NativeBridgeMetalFrontend.mm:1440`: copy the actual render descriptor,
  function specializations, archives and options into `NmbRenderPipelineDescriptor`.
  Rust `NativeMetalObjects.rs` delegates the complete descriptor to metal2vulkan
  runtime. Its general pipeline creation is a useful contrast to our current
  static603..606 fallback gate and reflected native graph contracts.
- `NativeBridgeMetalFrontend.mm:714`: actual indexed Metal parameters are
  forwarded through one bridge, including instance count/base vertex/base
  instance; buffer ownership is retained until completion. Our blur index path
  now passes actual GPU tests, but live profile100 rejects a resource contract.
- `bridge/quartzcore_blur_host.mm:127`: real unchanged blur shaders are tested
  with linear/clamp sampling. Our blur wrapper currently requires nearest.
  This is a concrete comparison target; the phone sampler has not been logged
  precisely enough to prove it is the rejected field.
- `bridge/patches/0002-resource-wait-storage-dependencies.patch`: resource waits
  follow storage identity/overlap, including imported IOSurface aliases, buffer
  textures and heaps. Compare these dependency rules while preserving actual
  fence lifetime and alias validation.
- `GpuScanoutPresenter.h`: import frame/scanout pages without a CPU pixel copy,
  submit a GPU blit and wait for its terminal completion. It handles equal and
  unequal row stride separately. Our existing GPU-source presentation counters
  already show an active path; do not treat another presenter as a repair for
  rejected pipeline creation.
- `bridge/patches/0006-skip-draws-without-a-pipeline.patch`: refuse recording a
  null Vulkan pipeline to avoid a driver crash. This is a crash containment
  measure; dropping a draw does not make its pixels correct.

## Scope for the Mali port

Use the Metal descriptor/resource/ownership patterns as references. Keep
Exynos7580/Mali-T720 power, MMU, JM descriptors and Midgard compilation grounded
in the existing tested Mali path and released Panfrost source. Adreno GMU, CP,
IR3 and Turnip packets target different hardware. The published plugin also
contains QuartzCore addresses tied to its target image; our iOS16 build requires
its own verified interfaces. No Adreno code was installed and no current device
configuration was changed by this review.

References:
- https://unixnu.com/drivers/native-adreno
- https://github.com/UniXNU/NativeMetal/tree/c6d29caad6d880cc8204ebe3bc34d77479a3255d
