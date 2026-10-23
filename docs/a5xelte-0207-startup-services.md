# 0207 startup-service investigation

This separates the three service failures in the private 0206 capture from
the FramebufferFetch compilation failure. No exception is suppressed and no service is replaced. Patch 0202
repairs a
confirmed TCC token-transport gap locally; device service recovery remains
unverified until the next physical boot.

## AttentionAwareness connection loss

The second backboardd fragment-specialization abort is at decoded line 10789.
At 10793 SpringBoard throws from `setConfiguration` because its additional XPC
proxy for `com.apple.AttentionAwareness` became invalid after interruption
(NSCocoaErrorDomain 4099). Its heap also contains the preceding 4097 connection
error. No separate attention daemon execution is recorded.

Read-only extraction of the exact device launch cache confirms that
`/System/Library/LaunchDaemons/com.apple.backboardd.plist` owns
`com.apple.AttentionAwareness` in `MachServices`, runs `/usr/libexec/backboardd`
and has `KeepAlive=true`. This is loss of a connection to the rendering/input
host, not evidence of an omitted standalone daemon or missing camera driver.
Keeping backboardd alive through its rendering request is the first repair
to test; the logs do not by themselves prove every later reconnect succeeds.
A general exception-ignore switch or a dummy AttentionAwareness service
would conceal the broken connection rather than restore its semantics.

## TCC sandbox-extension issue failure

assetsd's exception has a more specific underlying error than its termination
message alone: its heap contains `Failed to issue Sandbox Extension for
kTCCServicePhotos`, `auth_error_code=6`, `auth_value=0`, and `result=false`
(9333–9338 and9370–9375). SpringBoard also records an AddressBook extension
issue failure at11503–11508.

The current kernel's `sweet_sandbox_syscall` returns `ENOENT` for extension
issue (operation 5) and consume (operation6), deliberately, in
`xnu/patches/0050-sweet-sandbox-policy.patch`. The A5 registration/label change
in 0106 preserves these returns. tccd calls operation 5 at 1547. This is a
concrete implementation gap matching the reported failure, rather than
evidence that assetsd's stock TCC entitlement was removed.

Simply returning 0 is incorrect: issue must write a token into a caller-owned
buffer; consume must write an actual handle through a caller pointer. A
correct development-provider implementation needs the exact target library's
request ABI, bounded copyin/copyout, a token tied to its requested class and
target identity, consumption/release behavior, and explicit rejection of
unsupported extension kinds. It must not manufacture a successful TCC
authorization result or claim production sandbox enforcement: this port's
existing sandbox provider is permissive.

### Exact target ABI and implemented transport

The target library was recovered read-only from sparse HFS/shared-cache
ranges, following its HFS hard-link inode and split-cache mappings. Its image
is `/usr/lib/system/libsystem_sandbox.dylib`, base 0x1d1af4000. The actual
20H392 wrappers establish:

| Operation | Actual request fields, each 64-bit | Target-library code |
| --- | --- | --- |
|5 issue|class pointer, type, resource pointer, flags, output token buffer, PID, PID version|internal offset 0xf98; caller allocates 2048 bytes|
|6 consume|token pointer, strlen(token)+1, output handle pointer|offset 0xecc|
|7 release|handle, zero, zero|offset 0xc40|

Generic extensions use type 3 / resource 0. Process-bound wrappers select PID and
PID-version flags 0x10000/0x30000 from the audit token. The exact recovered tccd
imports both file and generic issuance; at preferred 0x100013a94 it calls
`sandbox_extension_issue_generic` with flags 0. Its strings construct the
`com.apple.tcc.` class family. No downloaded Apple binary or raw disassembly
is committed.

Patch 0202 implements only this TCC generic family in the existing A5
permissive development policy:

- The issuer must be a platform binary with identity `com.apple.tccd` and the
  exact stock executable path. The recovered launch job runs as `mobile`, so
  an invented root-UID requirement would reject the real daemon.
- Bounded class strings must start `com.apple.tcc.kTCCService` and have an
  alphanumeric service suffix. File/Mach/IOKit extensions and unknown flag
  combinations remain errors. This does not override TCC's authorization
  decision; it supplies the extension after tccd requests one.
- A kernel-PRNG token with 256 random bits is stored with its exact class,
  issuer process unique ID and optional PID/version target. The output buffer
  receives a 72-byte terminated opaque token. No uninitialized output or
  magic `invalid` token is returned as success.
- Consumption validates the token and target, claims it for one process
  unique ID and writes a positive handle. Repeated consumption by that same
  process increments a reference count. Another process cannot claim an
  already-consumed token. Last release destroys it, so subsequent replay and
  duplicate release fail.
- Limits are 1024 total records, 256 per issuer and 128 consumed records per
  client. Unconsumed tokens expire after 30 minutes. Process-exit notification
  clears the client's records and abandoned pending issuer/target records;
  already transferred tokens survive issuer exit.
- A mutex protects registry changes. Copyin/copyout, vnode lookup, entropy
  generation and logging run outside that mutex. Failed token/handle output
  rolls the reservation back. Unsupported, malformed and exhausted requests
  return explicit errors.

This is an intentionally narrower TCC transport contract, not a general
replacement for Apple's production sandbox or a multi-recipient file-token
implementation. The surrounding development policy remains permissive.

The actual added source passes 1623 ASan/UBSan assertions covering the verified
request sizes, issuer/class checks, target PID reuse, malformed requests,
copy faults and rollback, references/replay, expiry, quotas, exit cleanup and
concurrent claims. A private copy of the currently staged source accepts 0202
with zero fuzz, and the same harness passes against the applied include.
Full XNU build and actual assetsd/TCC runtime acceptance are separate gates.

## PosterBoard duplicate first-time setup

Both PosterBoard crashes repeat preferred PC0x1c1778268 and the assertion
`!_stateLock_switcherConfiguration`. Existing exact-cache symbolication in
[0183 review](a5xelte-0183-log-review.md) places this in
`_stateLock_setupSwitcherConfigurationForFirstTime`, reached through extension
refresh and `PRSServer` prewarm. This is a failed software invariant, not an
unknown CPU opcode. The logs do not establish why an existing configuration
reached first-time initialization. Preserve the invariant and inspect the
actual initialization/state path; do not replace the trap with an unchecked
return or erase user state as a speculative repair.

## Required device evidence after a real repair

- Backboardd remains alive through the formerly failing framebuffer-fetch
  specialization and submits the resulting pipeline.
- SpringBoard retains or re-establishes its AttentionAwareness configuration
  connection; no 4099 exception follows.
- tccd issues a token through the real target ABI, the recipient consumes it,
  and assetsd proceeds past its TCCPhotosService check.
- PosterBoard prewarm and extension refresh finish without the repeated
  first-time-configuration assertion.

Host compilation, kernel/provider tests and a successful BOOT write are
separate checks; none alone proves these runtime outcomes.
