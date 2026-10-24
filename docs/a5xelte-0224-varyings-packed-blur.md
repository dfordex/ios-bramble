# 0224: varying layout, packed blur sources and pipeline contracts

## Scope and observed cause

This build addresses the three independent failures in the full 0223 capture.
It does not establish a responsive lock screen until the new image runs on the
phone and its log is recovered.

1. The automatic compiler reached the genuine Midgard backend, then aborted in
   released Mesa's `pan_varying_collect_formats`. Dynamic FragCoord lowering
   assigned base 2 even when a dual-UV shader already used base 2 for color.
2. Profile 99 rejected an actual 542×963 BGR5A1 source with a 1088-byte row.
   Its native sampler path accepted only four-byte BGRA8 sources.
3. Late descriptor diagnostics exposed Float2 position attributes and
   premultiplied source-over state outside the static profiles' original
   descriptor contracts. The exact last crashing pipeline identity was not
   captured, so these are observed mismatch classes, not proof that every
   backboardd crash shares one cause.

## Source changes

### Compiler

Dynamic FragCoord now follows the complete declared input extent, measured
before dead-input optimization. It cannot alias UV/color slots or reuse a dead
declared slot. Bounds remain explicit; legacy static FragCoord keeps its old
base. The exact failed request now has UV0/base0, UV1/base1, color/base2 and
FragCoord/base3.

Replaying that request exposed a second real backend failure: `ddx_fine` was
absent from Midgard's NIR dispatch. Mesa 26.2.4 already maps default, fine and
coarse derivatives to the same hardware mode for each axis. The frontend now
canonicalizes that mapping, explicitly preserving half-precision conversions.
The native ABI checker admits only the supported fragment derivative shapes.
No collector assertion or NIR validation is disabled.

### Packed blur sampling

Profiles 99–108 can sample source format 43 in place using released v4
`MALI_RGB5_A1_UNORM` and the existing BGRA channel swizzle. Bounds use the actual
two-byte texel size and padded row. Nearest/linear state is retained. There is
no CPU color conversion or substitute source allocation.

The exact known 48-byte vertex layout can use Float2 position fetch through
RG32F and the missing-component values z=0, w=1. Other attributes and layout
fields remain checked.

### Pipeline adaptation

An owned profile adapter authenticates the original static program/descriptor
before adapting Float2 position, existing packed target handling, and the
implemented ONE / ONE_MINUS_SRC_ALPHA source-over state. Caller descriptors and
the global registry remain unchanged. Inline-blend and nonexecutable programs
are excluded from the new blend adaptation. Dynamic pipelines use the same
real Float2 fetch representation. Native encoders implement the corresponding
resource and blend contract rather than accepting an unimplemented state.

Three private Mesa helper builders also recognize an absolute or relative
standalone compiler source path when reusing Ninja's actual compile command.

## Verification

| Check | Result |
| --- | --- |
| Old FragCoord base 2 against assertion-enabled Mesa 26.2.4 | Reproduces the phone's collector assertion at line 370 |
| Production allocator/lowering | 16 dense/dead-slot cases plus declared, sparse, bounds and legacy cases pass |
| Actual native derivatives | 12 compilations pass; default/fine/coarse are byte-identical per axis and 16/32-bit shape |
| Exact failed request through automatic worker | Publishes a genuine 3,632-byte fragment, 8 registers, no TLS/WLS; actual provider cache validation passes |
| Static profiles 602–606 | All ten SPIR-V and ten native outputs remain byte-identical to prior pins |
| Packed source reference | All 65,536 words agree with unmodified Mesa B5G5R5A1 unpacking; padded-row, alpha, fractional filtering and clamp checks pass |
| Blur encode/provider | Ten structural profiles; u16/u32 and nearest/linear paths pass, with bounds/alias/import/fence negatives |
| Generic factory | 12 positives, 60 vertex negatives, 36 blend negatives and 24 success/error fence paths pass |
| Static/dynamic packed target matrix | 48 format/position/blend combinations pass through real factory and native encoder |
| New fragment plus actual dual-UV vertex | Eight cache → factory → native emitter cases pass across target 80/43, Float2/Float4 and copy/source-over |
| Device build | Cortex-A53 iOS Werror objects and signed provider build pass; final full XNU make exits 0 |
| Payload | Actual staged kernel installer validates all 100 streams and 27 complete shader publications |

The legacy broad native test script still has an old diagnostic-count assertion
that assumes at most 32 pipeline log messages. Focused production-path tests
above pass; that unrelated assertion is not presented as a passing test.
GPU pixels and UI interaction for the new paths still require the phone.

The host worker used the project's recovered iOS translator with only its
LC_BUILD_VERSION retargeted and a new local Mac signature; its instructions were
unchanged. The phone package retains the original iOS translator. The rebuilt
iOS generic backend contains the source fixes and uses 4 KiB signature pages.
Existing worker, validator, baseline compiler and recipes are preserved.

## Build and installation boundary

The build restores private inputs from the prior host BOOT, with exact
size/CRC checks, rather than reading device BOOT. All 26 old publications are
preserved. Their canonical requests were reconstructed from their reflection
and checked against every original request identity; the new publication is
added as the 27th. The 29-profile/36-program registry and existing optional GPU
fixture data are recovered unchanged. Apple libraries, generated shaders and
raw logs remain outside Git.

The matching firehose support archive was rebuilt from libdispatch 1415.140.2
with PRIVATE/KERNEL_PRIVATE headers and Cortex-A53 flags. Disassembly has no
LSE atomics. No runtime support source was patched to recover the build.

0224 BOOT is **31,891,472 bytes**, containing a **31,223,944-byte** kernel and
**943,920-byte** provider. The compiler backend is **11,432,912 bytes** after
4 KiB signing. All linked segments and all 100 embedded files were checked in
the final image. The complete selected FDT stages at
`0x41fd2800..0x41fec800`, below the unchanged `0x42000000` boundary.

Loader, ADT, DTBH and arguments are byte-identical to 0223: four cores,
736 MiB managed RAM, 32-sector eMMC requests, native GPU, quiet functional touch,
and optional GPU suites disabled. 0223 verified the RAM bootstrap count, not
exhaustive memory stability. This build makes no new performance claim.

Guarded recovery/model/TWRP/BOOT p10/capacity checks passed. A fresh unbuffered
file at offset zero supplied all **31,891,472 bytes**; `dd` acknowledged that
count, `sync` exited 0, and reboot was requested. No BOOT backup, post-write
readback or whole USERDATA transfer was performed. The new device UI/input,
packed-source pixel and compiler-runtime results remain pending.
