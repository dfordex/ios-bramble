# 0194 device log: runtime audit false rejection

## Complete capture

Read only the authorized lab phone's SYSTEM p20 reserved area in TWRP.
Flush 669 records 870,950 bytes, all recovered without ring overwrite; decoded
text is 870,705 bytes / 12,341 lines. Raw logs remain private. No data-root
transfer was performed.

## Result

The newly added runtime ABI audit blocks the Metal device before real iOS
command submission. It reports `RETURN_ABI` for the inherited device method
`indirectArgumentBufferCapabilities`, while its printed expected and actual
encodings are exactly equal:

```text
{IndirectArgumentBufferCapabilities=b1b1b1b29}16@0:8
```

The audit's Foundation signature/size parser path cannot establish this
bitfield aggregate, and wrongly treats the parser outcome as an ABI mismatch.
This is a validation regression, not evidence of a different GPU calling
convention or a missing implementation. The first rejection is at line 954,
followed by provider registration failure at 957 and backboardd SIGSEGV at
958–961. The probe has the same rejection and signal at 964–970. Eight retained
backboardd audit errors and one probe error precede the daemon tee budget
exhaustion; later crashes repeat the same PC/backtrace.

The complete capture contains 111 backboardd crashes, 16 contextstored,
four siriactionsd, one probe and one assetsd crash. There is no kernel panic or
SpringBoard crash record. No real Metal native phase or nonzero framebuffer
GPU/CPU presentation appears. Purge-selector text is absent, but the provider
never reaches rendering, so this does **not** verify the new purge method on
the phone. The other daemons' failures are separate and are not assigned a
cause from these limited messages.

The private GPU suite still passes all 21 evaluated pixel cases with terminal
fences (line 189). This validates those GPU fixtures independently of stock
Metal device registration; it is not an iOS compositor result.

## On-phone compiler progress

Unlike the previous run, automatic compilation actually completes and
publishes one profile 602 result (lines 6027–6030). `metal2vulkan` exits zero
after 59.141 seconds wall / 5.932 seconds CPU; `midgard-generic602` exits zero
after 1101.036 seconds wall / 41.980 seconds CPU. This proves publication,
not use by backboardd or rendered pixels. Five other requests are explicitly
unsupported. A subsequent metal2vulkan request is still running at its last
saved status; this is not universal shader support.

## 0195 repair

Check byte-identical method encodings before asking Foundation to parse them;
also accept byte-identical individual type encodings before size comparison.
Keep all mismatch, missing-method and unavailable-protocol rejection paths.
Emit the final audit summary to stderr so it is retained if the process exits
before stdout flush. Do not disable the audit or claim different types match.

The focused runtime regression uses real dynamically registered Objective-C
protocols/classes: the identical bitfield encoding passes; different return
width, argument width and missing selector fail. Cortex-A53 iOS cross-compile
and production bundle checks pass. The next phone log must show the audit
acceptance and subsequent resource/command behavior.

0195 packaging: full XNU make exited zero; provider and probe signature page
checks and actual installer preflight pass. The 16-file payload is39,515,422
raw/9,445,385 compressed bytes. BOOT is30,289,936 bytes, retaining the tested
four-core configuration, 21 GPU fixtures and existing compiler/registry.

## 0195 installation

After source commit `3c35fd6`, Mac ADB confirmed the same authorized lab phone
in TWRP and BOOT p10 capacity, streamed30,289,936 bytes to p10, received the
exact dd byte count, synced and requested reboot. No backup or post-write
hash/readback was taken, as requested. Device acceptance/rendering is pending.
