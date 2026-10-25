# 0235: line rendering, larger geometry and variable blur

## Scope

This completes the three remaining source gaps identified in the 0234 readout:
line primitives, geometry above 256 vertices, and the plain variable-blur stage
that failed translation with an incompatible fixed-function companion. It also
packages the previously committed 4096-operation command-list bound and
immediate typed compiler-failure publication. Physical UI progress is a separate
checkpoint; host compilation and descriptor tests do not establish it.

## Native lines and geometry

Metal lines and line strips now reach the real Mali v4 line/line-strip draw
modes. Line width is one pixel. The line provoking-vertex selection follows the
released Panfrost descriptor path; unsupported lines are not converted to
triangles or silently skipped. Both nonindexed and u16/u32 indexed routes retain
index, source-span, ownership, resource and fence validation.

Generic profiles 600..606 and reflected dynamic profiles support up to 1024
vertices. The 256 KiB job allocation remains unchanged. Draws through 256 keep
the existing output layout; larger draws place position, point size, UV and
color in separate bounded planes. Even the largest two-UV/color layout ends
before the allocation boundary. CPU input snapshots remain limited by the
64 KiB input arena; larger valid inputs use mapped external uploads. Old
blur/home/path encoders retain their independently verified 256-vertex bound.
Index-count, nonzero-base and instancing restrictions are unchanged.

## Real variable-blur compilation and linkage

The worker pairs `variable_blur_vert_lph` with
`variable_blur_downsample_frag_lph` in both compilation directions. Neither
stage invents function constants. Real stock AIR translation and released-Mesa
native compilation produce a 2432-byte vertex program and a 2000-byte fragment
program. The vertex takes position and two UV fields and exports no color;
the pipeline factory and native fetch/varying tables now represent that ABI.
A fragment that needs an absent vertex color export still rejects.

A shared validator translates the reflected immutable sampler into native
nearest/linear filtering, repeat/clamp-edge/transparent-black-border addressing
and bounded LOD state. It rejects comparison, anisotropy, unsupported border
colors, mip modes, bias and malformed values. The actual blur uses linear
filtering and transparent border, LOD 0..15. Native sampler descriptors preserve
that state; they do not substitute clamp-to-edge. Texture dimensions and sampler
LOD system values are populated per actual reflected texture. The compiler
admits only those bounded system-record reads that the emitter supplies.

The half-sized fragment uniform keeps its logical two-byte window and receives
a zero-padded final native word. Successful stages remain immutable. Only this
newly supported blur feature may retire a matching old failed publication or
old status-only failure once, under support generation 3. Prior evidence stays
archived. Current-generation failures remain terminal, and an interrupted
retirement can resume without an infinite compile loop.

## Verification

- Native API tests cover line counts 2/164/176/186/196/256/312/330/1024,
  line strips, u16/u32 indices through vertex 1023, exact draw fields and fences.
- Six genuine static/dynamic shader pairs pass decoded descriptor tests across
  2..1024 vertices, including output-plane nonoverlap and cleared failure output.
  ASan/UBSan passes. Oversized inline snapshots reject; external inputs pass.
- Real worker tests compile both blur stages, publish their actual native code,
  retry the old failed state once, resume interrupted retirement, preserve a
  current failure and keep publications stable across repeated scans.
- The production cache, Metal pipeline factory and native emitter accept that
  actual blur pair with three required or four declared vertex fields, BGRA8
  and BGR5A1 targets. Tests decode the two UV exports, no-color contract,
  transparent border, LOD 15, texture system records and padded uniform.
- All 52 captured complete pipeline snapshots still pass the real factory with
  exact descriptor round trips and no missing stages. All 18 existing native
  wrapper regressions and the iOS/A53 compile pass.
- Strict dynamic-cache tests, the real plain-fragment positive path, real AIR
  terminal failure delivery and actual ordered-fetch stage publications pass.
  Queue tests retain 96/4096 operations in order and reject 4097/recommit; their
  GPU transport is mocked.

## Build and device result

The signed provider, worker and backend use iOS ARM64/A53 builds and verified
4 KiB code-signature pages. The 374-file payload preserves all 32 prior shader
publications and 270 stock application files. Its actual kernel installer passes
ASan/UBSan preflight. The corrected worker will compile the blur stages on the
phone; no Apple input, captured request or generated native program is committed.

Full XNU make exits zero. BOOT is 25,800,720 bytes; kernel is 25,134,488
bytes. Final checks compare all linked kernel segments and all 374 embedded
file CRCs against the actual image, retain the exact 0230 loader/ADT/DTBH and
boot arguments, four CPUs, 736 MiB managed RAM, 32-sector storage I/O, functional
quiet touch and native rendering. Optional diagnostic pixel suites remain off.

The guarded TWRP/model/partition/capacity installation writes BOOT p10, receives
all 25,800,720 bytes, completes sync and requests reboot. No BOOT backup,
post-write readback/hash or whole USERDATA transfer is performed, per the user's
instructions. Recovery, EFS, radio and partition tables are not write targets.
The Mac artifact, installer receipt and test proofs are saved privately under
`experiments/ios-a5xelte/research/builds/0235` in the project workspace.

**Physical line rendering, blur execution and UI responsiveness are pending the
next run's screen report and recovered runtime log.**
