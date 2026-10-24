# 0215b black-screen capture and0216 correction

## Physical boot result

The user saw XNU text before the black screen. The complete SYSTEM record has flush19 and151,324raw bytes (151,079decoded bytes/1,627lines). It contains the expected kernel timestamp,4/4CPUs initialized, HFS root, launchd, backboardd and SpringBoard. Thus the former early Samsung-logo reset checkpoint is passed. No kernel panic or process CRASH record appears in this capture.

The installer validates all82files, including21compiled shader publications, and finishes with sync0. All21publications are existing/matching: this confirms persistent files survive the reboot. It does not prove that every complete pipeline is accepted.

## First fatal GPU event

The earlier45fixtures produce the same41passes/four numerical failures. Actual602source-over again passes4096/4096. The first new DS4u16fixture completes vertex fence93, but fragment fence94 remains active with MMU1, fault_status080002c2 and fault_va04000080. The second DS4fixture is not evaluated.

This sets sticky GPU queue fault state before runtime readiness is published. AS1 mappings then cannot acquire the runtime queue;20logged selector4map failures returne00002be (`kIOReturnNoResources`). Backboardd therefore cannot import its screen/working textures. Logged framebuffer presentation uses CPU fallback only, with no successful native GPU presentation. The capture never reaches the previous final-pipeline failure checkpoint; absence of that crash is not proof it was fixed.

## Exact cause and change

The new private DS4fixture relocated its application source and framebuffer writeback into its single mapped02000000..02040000BO, but omitted the real destination-preserve TILER job texture at descriptor offset19a0. That preload retained04000000, so its second128-byte row reads the exact observed fault04000080.

The fixture now relocates that preload pointer to0203e000. Only three pointer bytes change in each u16/u32payload. Genuine shader code, uniforms, indices, source pixels and independent expected pixels remain identical. Direct SFBD load/clear aliases are explicitly cleared. A new decoded range checker covers preload/application textures, writeback, job dependencies, UBO/code/index/attribute/varying/heap pointers. Both corrected payloads pass; both actual old faulty payloads reject with the unmapped preload address.

No production emitter, MMU permission, timeout quarantine or ambiguous-job lifetime rule is relaxed.

## Normal UI boot

0216 explicitly selects a5shadersuite=0 and a5downsampletest=0 while preserving native GPU/resource/framebuffer settings. Optional development fixture execution therefore does not run before normal iOS graphics. The existing two-fence bootstrap prerequisite remains active. The packer has explicit skip flags; omitting test flags alone previously retained inherited=1arguments. Six focused argument tests cover duplicate removal, native/unrelated settings and conflicting options.

Corrected physical DS4 fixture pixel results remain pending in a separate opt-in test boot. The normal UI boot tests actual iOS resource mapping and drawing after the mandatory healthy bootstrap. The21compiled publications and provider remain unchanged. Full build, packaging and installation results are recorded below when completed.

## 0216 build checkpoint

Full XNU make exits0. BOOT remains31,924,240bytes and preserves the physically booted0215b loader, ADT and safe DTBH byte for byte. The exact signed provider,21cache publications and45previous fixtures remain unchanged; both corrected DS4 payloads are verified inside the linked kernel. Command line546bytes explicitly disables optional fixture boots and retains native GPU, compiler, framebuffer,4CPUs and32-sector storage. No physical UI result is claimed before reboot observation.
