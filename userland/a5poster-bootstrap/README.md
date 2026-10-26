# A5 PosterBoard bootstrap compatibility

This is a scoped iOS 16 lab compatibility shim, not a general PosterBoard patch.
The captured state trap is in first-time switcher setup. The stock lazy getter
can build and store an empty `PRSwitcherConfiguration` before initial extension
loading. The update path selects first-time setup using
`_stateLock_initialExtensionsLoaded`; that setup requires the configuration slot
to be nil. Thus the empty lazy result and the initial-load flag can disagree.

The shim runs only for the exact PosterBoard bundle identity/path. It verifies
stock method shape, ivar types/offsets and the observed two state-load
instructions. With the stock state lock already held, it clears only an empty
configuration before initial extension loading, and calls the original setup.
Active, selected, held, nonempty, initialized and unknown states are preserved.
It never fabricates a poster, changes preferences, marks initial loading done,
or suppresses the stock assertion for another state.

`test_bootstrap.m` compiles the actual shim policy under ASan/UBSan with test
objects and a recorded original-method call. It checks repair, forwarding,
ownership and preservation cases. The stock Apple implementation is not executed
by this host test. Runtime installation and configuration creation must be
confirmed in the next device log.

`prepare_executable.py` privately adds one mandatory `LC_LOAD_DYLIB` in existing
Mach-O header padding. The executable text and entitlement dictionary remain
exact. It requires the original input hash and a complete output
`PosterBoard.app` resource tree with the original Info.plist, but without the
output executable. The shim is loaded before main regardless of Metal discovery.
The local executable is re-signed for this unsigned-root port; Apple bytes do not
belong in this repository.

Signing metadata uses a temporary directory outside the app, and the receipt
must also be external. Verify the entire signed application and every sealed
resource, not only CodeDirectory pages. Preserve all existing app resources in
the staged tree before signing. A sparse tree cannot establish the final phone
resource seal.

Compile the policy test:

```sh
clang -fobjc-arc -fblocks -Wall -Wextra -Werror \
  -fsanitize=address,undefined test_bootstrap.m \
  -framework Foundation -o /private/tmp/a5poster-test
/private/tmp/a5poster-test
```

Build the dylib for the phone with the iPhoneOS SDK, arm64/iOS 16/Cortex-A53,
ARC/blocks and Foundation. Set its install name to
`/usr/libexec/a5poster-bootstrap.dylib`, then ad-hoc sign using 4096-byte pages.
Patch0222 permits only that additional exact installer path. PosterBoard's
executable/resource seal use the existing selected-app gate; other apps and
factory partitions are not targets. The `--poster-bootstrap` BOOT option adds
PosterBoard to the diagnostic `/dev/null` capture list for verification.
