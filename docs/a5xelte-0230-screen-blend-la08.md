# 0229 readout and 0230: screen blend and LA08 import

## Device evidence

The complete SYSTEM capture has 1,083,712 logical bytes, 12,096 lines and flush72, without ring overwrite. It contains 80 captured command-buffer results Completed/error0 and 199 touch / 364 key HID records. These counts establish captured GPU completion and input arrival, not responsive UI or distinct frame rate.

The first explicit backboardd pipeline terminal receipt rejects static profile602 because attachment0.blendEnabled is1 while the copy contract expects0. The complete corresponding request was recovered through a bounded, read-only project-file allowlist. Its descriptor requests ADD with source ONE and destination ONE_MINUS_SOURCE_COLOR for both RGB and alpha. It then aborts with namespace13/code4, `Metal failed to build render pipeline`. This is an unsupported render-state contract, not evidence of missing native shader code.

An independent external texture request rejects RG8Unorm30, 1152x72, row2304, allocation167936, two bytes per element and IOSurface LA08. The existing canonical RG8 identity is 2C08. Later SpringBoard SIGABRT/SIGTRAP records remain separate unresolved failures; this change does not claim to repair them. The earlier Map4 NoResources failure is absent from this capture, which alone does not prove every residency scenario.

## Corrections

Static authenticated generic600..606 and reflected dynamic pipelines can now preserve the exact screen blend contract: `source + destination * (1 - source)` independently per channel. The native v4 RSD uses SRC for the RGB C operand, destination loading and inverted C; alpha uses SRC_ALPHA. Existing copy and premultiplied source-over remain distinct. The producer carries the selected mode through to the misc native emitter. Shader identity, resource, layout, bounds, attachment and fence checks remain enforced; blur/inline blend routes are not silently changed.

External LA08 storage is accepted only as a two-byte RG8Unorm view. Provider validation, span-to-native-image validation, bridge element sizing and kernel resource import agree. Its actual LA08 identity and row stride are preserved. New allocations keep their canonical format. There is no RGBA/BGRA substitution or luminance expansion.

## Verification and limits

- All52 recovered complete pipeline snapshots pass the actual provider factory with exact descriptor serialization equality, including the newly recovered failing screen-blend request. No missing native stage in this replay.
- All18 existing native wrapper regression executables pass. The generic600/601/602 production producer additionally exercises copy, source-over and screen with Float4/Float2 positions. Released Mesa v4 descriptor decoding verifies the actual submitted blend operands; unequal channel/alpha values distinguish screen from source-over. Transport is mocked, so this is not physical GPU pixel proof.
- Real host IOSurface allocation reproduces the exact LA08 dimensions/stride/allocation. RG8 import and native-image span succeed; unequal two-byte texels round-trip at the final pixel, a wrong R16 view rejects, and cleanup balances. Existing private/shared/mipmap/bounds cases pass.
- Actual kernel resource helpers pass ASan/UBSan layout tests including LA08, incorrect element size, short allocations and overflow.
- Signed iOS provider uses verified 4KiB signature pages. Actual installer preflight accepts373 files and32 persistent genuine stages. Original app content and metadata are preserved.

## Build and installation

Full XNU make exits0. BOOT25,686,032 bytes, kernel25,019,736 bytes and signed provider963,952 bytes. All373 embedded files match final linked-kernel CRCs. Only the provider executable changes in the payload;32 stages,270 original app files and their metadata remain exact. Loader, ADT, DTBH and arguments remain exactly0229, including four CPUs,736MiB,32-sector storage, quiet functional touch and native GPU; optional suites stay disabled. Selected FDT staging remains below0x42000000.

The recovery/model/p10/capacity guards pass. Direct offset-zero BOOT write acknowledges all25,686,032 bytes; sync succeeds and reboot is requested. No BOOT backup, post-write readback or full USERDATA transfer. Physical result is pending. The next phone run must establish actual screen-blend pixels, LA08 consumption and UI progression. No claim of universal Metal support or completed UI follows from host replay.
