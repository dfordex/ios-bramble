# 0211: metadata-based inactive blur target adaptation

Fixes0210's confirmed profile104 failure: iOS omits RT1 while the compiled
narrow_blur_19 registry declares an inactive secondary attachment. The existing
profile100-only adaptation now applies across native blur99..108 according to
actual authenticated metadata: one pass, logical target0, secondary format80 or115,
all attachment contracts disable RT1 writes/blending, and no input-attachment
resource reads RT1. A private descriptor copy changes only omitted RT1; the full
function/constants/layout/blend/sample selector must still identify that exact
registry entry. The caller descriptor is unchanged.

Auxiliary allocation, format/size reuse checks and the independent native emitter
use the same metadata and actual BGRA8/RGBA16Float byte sizes. An inactive target
never receives a GPU write bit or SFBD color writeback. Bounds, alias and terminal
fence rules remain enforced. This does not add general active MRT support.

## Verification

All18 native wrapper binaries and final Cortex-A53/iOS compile pass, including
all ten blur profiles with actual IOSurface auxiliary allocation, caller-provided
RT1, Query17 mapping, Submit18 read7/write2, immutable caller uniforms and real
failure handling. Negative format/state/layout/device, mapping-span/alias,
allocation and missing-fence cases pass. Structural native tests cover both
index widths, inactive-format byte sizes and rejection of an active RT1 for all
ten profiles. Kernel transport is mocked; hardware acceptance remains pending.

The signed production provider and19-file embedded payload preflight pass
(40,637,664 raw /9,834,431 packed bytes). Full XNU compile/link/dSYM/strip/symsets
pass. BOOT31,709,200 bytes fits32MiB. Loader/ADT are identical to0210/proven0207d;
the exact signed provider is embedded in the linked kernel. Suite41 retains all
previous39 cases plus real104/19tap BGRA8 and108/23tap RGBA16 indexed pixel cases.
Their independent legacy arithmetic oracles are never written into GPU inputs.
The old four pixel failures and independent PosterBoard/dasd issues remain open.

The automatic compiler may still mark the captured blur pipeline request
unsupported: its binary is already compiled in the registry, and this repair
admits the corrected descriptor directly. No new shader compilation or ignored
pipeline error is used to mask this mismatch. Phone results follow installation.
