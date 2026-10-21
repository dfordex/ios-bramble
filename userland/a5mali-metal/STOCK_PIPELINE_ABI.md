# iOS 16.7.16 QuartzCore pipeline boundary

This source-only audit describes the operator-supplied stock binaries. No Apple
binary, metallib or shader bytes are included. Static caller coverage and local
validation do not establish successful compositor rendering on the phone.

## 0162 failure

The saved 0162 device log repeats the same backboardd SIGSEGV 31 times and has
no completed GPU frames. Runtime PC/LR `0x1b352b660`, with image slide
`0x31aec000`, maps to Metal `0x181a3f660`:

```asm
; MTLPipelineLibraryBuilder::newLibraryWithFile(...) + 836
ldr x8, [x23, #0x10]
```

FAR is `0x10`. Earlier at `0x181a3f61c`, this builder calls the device's
`targetDeviceInfo` and puts its result in x23. The inherited implementation at
`0x181aabb14` returns NULL. The builder checks whether the selector exists, then
uses the returned pointer without checking NULL. Inheritance satisfies that
selector check, but supplies no native Apple target architecture.

The caller is QuartzCore `CA::OGL::new_metal_context(...)`:
`0x188488534` sends `newPipelineLibraryWithFilePath:error:`; the return address
`0x188488538` matches runtime frame `0x1b9f74538`. This is an unsupported native
Apple precompiled-pipeline builder, rather than a failed Mali GPU submission.
The safe boundary returns nil and an unsupported NSError; it must not fabricate
Apple target-device structures to let that builder continue.

## QuartzCore handles an absent pipeline library

The call at `0x188488538` stores the result in context offset `0xc58`. A nil
result proceeds through the failure-message branch at `0x188488548`; subsequent
messages to that nil library are harmless. The precompiled render lookup checks
the same field for NULL at `0x188375858` / `0x18837585c` and skips its lookup when
absent. Its `newRenderPipelineStateWithName:options:reflection:error:` call at
`0x188375908` is on an **MTLPipelineLibrary**, not on MTLDevice.

The direct fallback calls the custom device's
`newRenderPipelineStateWithDescriptor:error:` at `0x188381b9c` and
`0x188381bf4`. The compute caller uses
`newComputePipelineStateWithFunction:error:` at `0x188482e20`. These factories
still require implemented shader translations and matching descriptor support;
skipping a precompiled library does not create general shader compilation.

## Function descriptor factory

QuartzCore creates an MTLFunctionDescriptor at `0x1884829bc`, sets its name at
`0x1884829c8`, optionally supplies function constants at `0x1884829d8`, and calls
the library at `0x1884829e8`. The exact arm64 Objective-C method shape is:

```objc
- (id)newFunctionWithDescriptor:(id)descriptor error:(id *)error;
```

`A5MaliMetalLibrary` implements this selector for its authenticated QuartzCore
library identity. A plain descriptor is copied before validation. Only
`read_surf_vert` and `read_surf_frag`, with no constant-values object, no
specialized name, zero options and no archives are accepted. Even an empty
constant-values object is rejected; no translation of specialization values has
been established. Audited private getters, when present, also reject nonzero
pipeline options, any plugin data and nonempty private-function arrays.
Descriptor subclasses are unsupported. No generic selector forwarding or native
compiler fallback is used.

The stock initializer sets `applyFunctionConstants=YES` and creates an empty
private-function array. With constantValues absent, the former has no constants
to apply. Validation does not depend on fixed descriptor ivar offsets.

## Other inherited factories that bypass bounded custom methods

The inherited implementations of these APIs directly reach the native Apple
compiler or library builder. Guarding only the simplest synchronous factory is
insufficient:

- render descriptor with options/reflection, and both asynchronous variants;
- compute descriptor with error, options/reflection, and asynchronous variants;
- asynchronous source-library creation;
- file-library creation and private pipeline-library creation.

Unsupported completion factories must invoke their callback exactly once with
nil and an NSError. File-library creation can forward to authenticated URL
loading. Native pipeline libraries remain unsupported. The stock tile options
factories already reject, but explicit custom rejects keep this boundary clear.

## Verification

The host stock-library test was built with ARC, blocks and warnings as errors,
then run against the user's local, unmodified QuartzCore default.metallib.
Both ordinary descriptor names passed; missing or changed names, nil or wrong
descriptor objects, specialization values, options, archives and private
descriptor extensions were rejected with `kIOReturnUnsupported`. The factory
was also syntax-compiled for arm64 iOS 16 with warnings as errors. These checks
perform no GPU jobs and do not mutate the phone.
