# 0192: actual source-over state, active image span and backboardd send option

## Rendering changes

Profile603 now admits both the previous exact copy contract and the actual0191
RT0 premultiplied source-over state: BGRA8, all channels, ADD, sourceONE and
destinationONE_MINUS_SOURCE_ALPHA for both RGB and alpha. Other attachment
slots retain their exact defaults. Native shader bytes and typed constants
are unchanged. The profile explicitly carries SourceOverBlend capability.

The native emitter validates both contracts and encodes the actual fixed
source-over equation. Destination loading and the existing preload job retain
the previous framebuffer pixels before blending. It no longer rejects every
non-copy textured draw. Unsupported factors/state still reject. The compiled
cache deep-copies both contracts and the flag, so phone-compiled shader bytes
cannot silently revert the executable profile to copy-only behavior.

Linear buffer texture validation now distinguishes final active bytes from
padded GPU row footprint. For the actual194x237 BGRA8 request, row832 and
image197128 equal `(height-1)*row + width*4`; padded footprint197184 fits the
200704-byte backing. The declared image need not be64-byte aligned. Offset/row
alignment, arithmetic overflow, active-span lower bound and full GPU backing
span remain checked. Views continue to alias the actual Shared/no-copy buffer.

## Existing error-ignore option

The local iOS QuartzCore binary contains CA_IGNORE_MACH_SEND_ERRORS (string
file offset0x316186), read by
CA::Render::should_abort_on_send_failures's initialization block at
0x1884d4450. The separate Metal pipeline failure branches report reason
namespace13/code4 and terminate; no general pipeline-error continuation switch
was identified in those inspected paths.

The optional embedder flag `--backboard-ignore-mach-send-errors` updates only
EnvironmentVariables.CA_IGNORE_MACH_SEND_ERRORS to string1 in the exact
existing com.apple.backboardd cached launch job. Other jobs, properties and
existing environment variables are preserved. Malformed/missing/different
jobs are rejected. The provider logs the received option value when present.
The actual embedded binary launch-cache entry was decoded and checked.

This option affects Mach send failure policy. It does not supply a missing
pipeline, suppress explicit driver failures or establish successful rendering.
The actual pipeline rejection is repaired through the executable blend path.

## Verification and artifact

- Focused603 C descriptor test passes with real pinned shaders: copy and
  source-over equations/load-destination, preload dependency order, bounds and
  strict invalid-state rejection; host and Cortex-A53 emitter compilation pass.
- Full native Metal API harness passes. Buffer texture603 tests exercise both
  public/private selectors with copy and source-over pipeline admission,
  negative alpha factor, commit-time bytes, real query/submit descriptors and
  genuine/error terminal fence behavior through mock transport.
- Registry26profile/all-contract tests and deliberate native-code corruption
  rejection pass. Cache602/603 flags/contracts/lifetime tests pass.
- Exact194x237 final-row-trimmed image test passes, including last-pixel alias
  access, one-byte-short/overflow and inadequate-padded-backing rejection;
  Cortex-A53 texture compilation passes.
- Launch-cache option tests check only the intended key changes, binary-plist
  roundtrip, idempotence, preserved original cache and malformed-job rejection.
- Production provider649824bytes builds/signs with4KiB signature-page checks.
  Existing signed compiler runner127856bytes and tools are retained.
- Actual staged installer preflight accepts16files/39425358raw/9422487packed
  bytes, within existing limits. Full XNU make completes including symbols.

Host transport/descriptor tests do not prove physical source-over pixels or
backboardd survival. The existing21 GPU oracle cases remain in BOOT; the new
stock pipeline/linear view and error option require the next phone log.
Installation and device results are recorded in A5XELTE_PROGRESS.md.
