# 0212 phone readout: native two-image success; untextured pipeline rejection

## Scope and verified progress

Read-only SYSTEM capture flush142 recovers all990,796 recorded bytes,
10,307 decoded lines, no overwrite. Eight selected HFS request/publication files
and the two live launchd configuration files were also read through bounded
64KiB ranges. No phone write or reboot occurs during this analysis. Raw logs,
stock configuration, request identities and native code stay private.

| Private decoded log lines | Observation |
| --- | --- |
|271–273| New actual two-texture/dual-UV nearest/linear GPU case4096/4096 passes, fences85/86status0/header1/MMU0/immutable. Total38/42; same four old failures remain. |
|324–355| Final25-file installer preflight0, both complete publications installed, compiled metadata0, sync0. |
|3724–3728| Actual1328-byte fragment and2592-byte vertex are accepted and link as position-two-uv-color. Exact pipeline creation succeeds. |
|5729,5890,5936,6369,9015| Phone compiler publishes five native fragments:3728/2128/1104/2240/176bytes. The new worker diagnostics observe actual exec and exit0 for translator/backend. |
|1103–6796|32 logged live native submissions allstatus0/header1/MMU0, including four dynamic submissions and live blur100/104. Six recorded command-buffer results are Completed/error0. Bounded logs do not uniquely attribute each dynamic submission to a shader hash. |
|6949–8646| Multiple full-panel GPU presentations continue, commonly46–50copies per approximately5.3second window. This is presentation throughput, not proof all iOS work executes onGPU. |
|6353–6378| Power-key event enters HID queue; compiled2240-byte untextured fragment is accepted by cache but refused by combined pipeline IO predicate. BackboarddSIGABRT follows. |
|9015–9111| Later176-byte untextured fragment also fails pipeline creation; backboardd495 aborts, then SpringBoard499 throws AttentionAwareness4099 and aborts. |

The user reports a visible clock screen, followed by spinner/restarts when Home
or Power is pressed. Key down/up and HID queue consumption are recorded. The log
supports a rendering-pipeline failure during this progression; it does not prove
that every button press independently creates a process crash.

## Confirmed first rejection

Both native stages compile successfully, then the factory rejects
`fragment.native-texture-liveness-or-no-input-fetch` with static602 vertex.
The current factory requires either sampled textures or a zero-input ordered
fetch. These real stock variants need two additional authenticated native shapes:

-2240-byte fragment: no sampled textures/samplers; one color vec4 interpolant at
native location32/base0; ordered color0 framebuffer fetch; live UBO0minimum72
and FragmentBuffer1/nativeUBO2minimum136. Native tag8/workregs7/TLS0/WLS0.
-176-byte fragment: no inputs, sampled resources or framebuffer fetch; live
UBO0minimum72. Native tag5/workregs2/TLS0/WLS0. The enabled function constant
alone does not establish a fetch after optimization.

Their declared ConstantBlob is optimized dead; accepted backend/native liveness
must still prove this. Admission must map the actual color export for2240 and
zero interpolants for176, preserve real UBO/push bounds and reject incompatible
vertex/resource/fetch/side-effect contracts. Adding dummy textures or pretending
all untextured stages read an attachment would be incorrect.

## SpringBoard connection failure and remaining issues

The AttentionAwareness service is provided by backboardd in both fresh live
launchd files. Its connection exception follows the second backboardd Metal
abort; there is no independently evidenced missing daemon/disabled MachService.
See [crash chain](a5xelte-0212-attention-crash-chain.md). Preserve its provider
and repair the primary native pipeline failure first.

No kernel panic or native MMU/fence error is recorded. Last eMMC metrics show
291,216requests/6,265,389,568readbytes/215,950,336writebytes/errors0. The four older
RAW204/R8 source-over and ordered-fetch-noise pixel failures remain visible.
A stable interactive home screen and complete GPU compositor coverage are not
established by this capture. Next change is the actual untextured stage ABI,
followed by independent device pixel tests and button/wake validation.
