# iOS 16 Metal selector audit

This audit compares the provider classes with the **required instance
methods** recorded in the locally extracted iOS 16 Metal Objective-C metadata.
The extraction is private and is not committed. Its SHA-256 is pinned in
`ios16_metal_surface_baseline.json`. The baseline lists every known missing
selector with a reason category. A newly missing or unclassified method fails
the check. The `private_spi` section is deliberately separate from the public
protocol surface.

Run against the staged extraction:

```sh
sh userland/a5mali-metal/test_ios16_metal_surface.sh \
  /private/tmp/a5metal-dsc-objc-verbose.txt
```

`audit_ios16_metal_surface.py` reads actual protocol methods, including
inherited protocol methods, and parses the provider's Objective-C
implementations and synthesized property accessors. It recognizes methods
inherited by `A5MaliMetalDevice` from the iOS `_MTLDevice` class separately.
Those stock superclass methods provide selectors; they do **not** establish
Mali feature support. A zero missing-selector count is not a rendering test.
The static calling-shape check covers return/argument categories and basic
widths; it does not prove every struct layout or runtime method encoding.

`A5ProtocolRuntimeAudit.m` exports `A5MaliAuditRuntimeMetalSurface()` for a
pre-registration check in the target iOS process. It uses the OS protocol
registry and loaded classes to check inherited selectors and coarse
Objective-C type encodings. Its standalone `main` is excluded by
`A5_MALI_RUNTIME_AUDIT_LIBRARY=1`; without that define, it can load a supplied
provider bundle path for a direct audit. It intentionally does not make the
provider classes claim Metal protocol conformance. A successful host compile
only checks the audit program's syntax; it cannot replace a target-iOS run.

The available iOS 16 Metal image has no `MTLCommandQueue`,
`MTLRenderCommandEncoder`, `MTLBlitCommandEncoder`, or
`MTLComputeCommandEncoder` protocol declarations. This audit checks the common
`MTLCommandEncoder` methods for the two vended encoders, and lists the missing
protocols explicitly. The installed Xcode SDK contains later declarations,
which can guide implementation but are **not** used as the iOS 16 gate. For a
separate informational comparison, pass `--sdk-headers` with the installed
`Metal.framework/Headers` directory. That output filters methods explicitly
marked for iOS 17 or newer, but the installed SDK may still differ from the
actual iOS 16 protocol set (the local SDK used here is iPhoneOS 27.1). It
never affects the pinned iOS 16 pass/fail gate.
`--sdk-surrogate-json /private/tmp/a5-ios16-sdk-surrogate-missing.json` also
writes each missing selector with its installed-SDK header line and signature.
For a separate development gate, add `--require-sdk-surrogate-zero`. It never
changes the result of the actual iOS 16 metadata check.

The source-only audit is designed to reveal gaps during development. Class
construction, selector behavior, actual GPU work, and QuartzCore acceptance
still require their corresponding host and device tests.
