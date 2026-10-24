# 0212 AttentionAwareness connection interruption

## Finding

The captured SpringBoard exception follows the death of the process that owns
its AttentionAwareness connection. The evidence supports a secondary connection
failure after backboardd's Metal pipeline abort. It does not establish a missing
attention daemon, a disabled launch job, or an independent authorization failure.

## Device evidence

The complete decoded 0212 SYSTEM capture records this order:

| Decoded line | Observation |
| --- | --- |
| 6371–6374 | A compiled fragment is rejected by the dynamic native IO gate; the first backboardd instance aborts. |
| 6478–6491 | Its recorded termination reason is `Metal failed to build render pipeline`; backboardd and SpringBoard subsequently execute again. |
| 9016, 9096 | The later backboardd instance also aborts, with the same recorded Metal pipeline failure category. |
| 9100 | A replacement backboardd starts. |
| 9102–9109 | SpringBoard throws from `setConfiguration`: its additional proxy for `com.apple.AttentionAwareness` was interrupted and became invalid, Cocoa error4099. SpringBoard then aborts. |
| 9907 | SpringBoard executes again. |

A fresh read-only extraction of both the device's launch cache and standalone
backboardd launch plist confirms one AttentionAwareness provider: the backboardd
job. Both configurations execute `/usr/libexec/backboardd`, use the mobile
account, publish that Mach service, and set `KeepAlive` and `RunAtLoad` true.
Neither configuration disables the job. The launch cache also retains the
previous scoped QuartzCore Mach-send option; that option did not prevent this
separate invalid-proxy exception.

The capture contains no independently recorded AttentionAwareness server abort
or Attention-specific sandbox denial. SpringBoard's earlier privilege1007 denial
is `PRIV_DARKBOOT` in the staged XNU header, not evidence of an AttentionAwareness
Mach-service authorization failure. A general TCC extension operation elsewhere
in the capture does not establish that this connection was denied.

## Action and limits

No Attention-related executable, launch-job, sandbox, or exception-suppression
change is justified by this capture. The first repair to test is the concrete
Metal IO gate that terminates the existing service provider. Keeping that
backboardd instance alive preserves the connection that SpringBoard needs;
a replacement service or ignored exception would not restore its protocol.

This is a causal diagnosis supported by provider ownership and event ordering,
not proof that every future reconnect will succeed. After the GPU gate repair,
check that backboardd remains alive and SpringBoard progresses without another
AttentionAwareness interruption. Investigate the attention protocol separately
only if its failure recurs while its provider remains alive.

No raw logs, stock binary data, opaque request identities, or device writes are
included in this report. Runtime recovery remains a subsequent device test.
