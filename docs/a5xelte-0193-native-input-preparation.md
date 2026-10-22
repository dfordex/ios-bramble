# 0193: prepare native out-of-line input before snapshot

## Verdict

PASS for the focused host regression, repository validation and full XNU build.
Phone execution remains pending. Patch0190 repairs the input-descriptor lifecycle
that can produce the0192 first-submit kernel panic; GPU fences and pixels still
require the next physical run.

## Implementation

Both nativeSubmit(selector18) and nativeBulkWrite(selector19) use the same
bounded input snapshot helper. Out-of-line input is prepared with
kIODirectionOut before readBytes, then completed with the matching direction
before resource locks, header/token validation or GPU dispatch. Prepare errors
return without reading/completing; short reads still complete and return
Underrun; completion errors propagate. Each failed call frees its owned copy
and cannot submit a GPU job or write the destination buffer. Inline input keeps
its previous memcpy route. The GPU continues to consume the owned kernel copy,
never the caller descriptor. Existing size, token, mapping epoch and queue
validation remain intact. The XNU wire-count check is unchanged.

Source evidence: xnu/patches/0190-a5xelte-prepare-native-ool-input.patch changes
only A5XELTENativeClient.inc. The prior finding and physical screen timeline are
recorded in a5xelte-0192-log-review.md.

## Verification

The new test rebuilds the actual native-client source from repository patches
and requires byte-for-byte equality with the staged kernel source. It compiles
the entire native-client include against strict descriptor/transport stubs,
then invokes its real nativeSubmit and nativeBulkWrite entry points with
AddressSanitizer and UndefinedBehaviorSanitizer enabled.

Eighteen cases cover both entry points: successful OOL transfer, prepare error,
short read, completion error, invalid header, invalid size, allocation failure,
caller-memory mutation at completion and inline input. They verify paired
prepare/read/complete counts, no remaining wire/allocation/lock, no dispatch
or destination write on failure, and snapshot ownership after completion.
The old0192 source aborts on the stub's unprepared readBytes assertion; the
corrected source passes every case. Stubs cannot establish real VM wiring or
GPU rendering, so the phone trial remains required.

Repository validation passes190 sequential patches,31 Python tools and10 shell
scripts. Full XNU make rebuilds A5XELTEGPUUserClient and exits0, including kernel,
dSYM, CTF and symbol sets. The known platform/header warnings remain warnings.

The fresh BOOT is30273552 bytes, built with the existing0192 provider649824,
compiler payload,21 private GPU oracle cases and four tested CPU cores. The
incremental installer payload is retained; this fix needs a kernel replacement,
not a whole USERDATA image transfer. Physical installation is recorded in
A5XELTE_PROGRESS.md after the actual ADB receipt.

## Next device checkpoint

Require the clear-submit18 phase to return and a terminal native GPU fence.
Then examine subsequent603 textured/source-over commands and framebuffer
presentation separately. This input repair does not prove those later stages
or full iOS graphics coverage in advance.
