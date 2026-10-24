# 0220 installation checkpoint

## Changes and checks

0219 exposes two independent defects: quiet contact logging disabled functional touch initialization; static602 rejects the packed BGR5A1 render target43 while dynamic target43 already works. See [full0219 review](a5xelte-0219-log-review.md).

Patch0207 separates `a5touch` (default1) from `a5touchlog` (default0). Quiet contacts still reach HID. Explicit touch/probe disable returns before MMIO; the established PMIC/reset/controller/readiness/poll sequence is unchanged. The actual extracted probe/contact code passes six gate combinations, quiet press/release, explicit-disabled zero-hardware-access and patch round-trip checks. Explicit `--touch-input` requires the fixed kernel marker and writes `a5touch=1 a5touchlog=0` into the image.

The authenticated static602–606 owned-target43 adapter and native emitter pass24 actual factory/emitter cases plus descriptor/resource/ownership negatives. Three changed production units compile for actual iOS/Cortex-A53 with warnings as errors. Signed provider926,800bytes has225 verified4096-byte code pages; the unchanged signed compiler230,608bytes and23 existing persistent compiled stages pass actual embed/installer preflight.

Full XNU make exits0. Kernel31,273,520bytes; BOOT31,940,624bytes fits33,554,432capacity. Actual compressed new provider/unchanged compiler and all23 stage keys are embedded. Loader, ADT and safe DTBH exactly match0219; the whole selected FDT source41fde800..41ff8800 remains below42000000. Boot line556bytes,4CPUs,32-sector eMMC, native GPU enabled, both optional shader/downsample tests explicitly0. No optional GPU test is enabled by this correction.

## Device installation

The first two attempts stop before any write because ADB does not expose the target. USB inventory sees the correct device; restarting the host ADB server restores its recovery transport. The guarded installer checks only the authorized target serial, a5xelte, TWRP3.3.0-0, BOOT aliasp10 and capacity. A fresh unbuffered offset-zero image descriptor writes exactly31,940,624bytes; device dd acknowledges all bytes, sync exits0, and reboot is requested.

No BOOT backup/post-write readback/hash/full USERDATA transfer. RECOVERY/EFS/GPT/radio partitions are not written. Only exact project provider/compiler/cache installer paths update during HFS boot. Private preference reads remain read-only and no state seeding is performed.

Physical touch, Home/Power transitions, unlock stability and static43 GPU pixels remain pending user/device evidence. Continuing GPU completion and an advancing clock do not establish interactive UI support. The known separate PosterBoard switcher-state assertion remains unresolved; the approved conventional path read does not identify its expected container path.
