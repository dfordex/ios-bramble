# 0220 full device readout

## Captured evidence

SYSTEM logger flush49 recovers391,106 logical bytes/4,720decoded lines. No CRASH marker, kernel panic or MMU fault is recorded. The user reports visible UI but no interaction. This is a shorter capture than0219, so absence of a crash does not prove long-run stability.

The touch fix is exercised: enabled1/log0, LDO33 supply, ZT7538 identity, firmwareCRC55aa, mode0ready and the contactHIDworker startup are recorded.189 SWEET HID touch records follow. Home/Power keyqueue heads advance from0through1664; later the head stays1664while the tail reaches1920. Input initialization and initial consumer progress are now established. Source43 rendering is not explicitly recorded in this capture, so the static43 adapter remains physically unverified.

Eleven recorded command-buffer results complete with status4/error0 throughCB12. The next CB13 rejects a static603 indexed draw: triangle3/u16,count6,index offset8160,index buffer262144bytes,ready1. Those outer index fields pass source guards. The generic failure still combines backing/alias/format/sampler/resource-window checks; adjacent dynamic texture logs do not identify the rejected603 bound resources. No admission rule is relaxed on that evidence.

Backboardd then waits repeatedly for a newly requested fragment. The exact owner-bound request is captured read-only and compiled on the Mac using the genuine AIR/validatedSPIR-V/releasedMesa toolchain:2128 native bytes,8registers,noTLS/WLS,nointerpolatedinputs/notextures,orderedframebufferfetch,UBO2minimum152bytes. Actual cache loader, factory and native emitter accept it with authenticated static603 and preserve its exact program bytes. Negative descriptor/resource tests remain rejected. These are structural host checks, not phone pixel execution.

## Compiler scheduling cause

The worker's first scan snapshots18 candidates. It archives an old terminal entry before completing that scan, spanning a large increase in eMMC active time. The second scan begins before the new fragment request exists; that request arrives while old snapshot work is still being processed, and the worker starts another old retirement before rechecking arrivals. No AIR/native spawn for the new fragment is captured. It is queued behind bookkeeping, not shown failing compilation.

0221 adds bounded fresh-request checks between old handlers and before archival. The independent directory cursor avoids shared HFS enumeration offsets; strict owner/canonical/dynamic validation and64candidate limits remain. Durable archival is deferred below63 candidates, leaving ordinary low-pressure scans free from the observed unnecessary archive. Under63/64pressure at most one attempt is retained. A real fsync can still block once a pressure-triggered archive starts; this correction does not claim otherwise.

Actual worker tests inject a genuine late vertex after the initial18entrysnapshot; it compiles and matches the1808byte reference before the first old handler. Malformed late identities are refused. No archive at18/62; one attempt at63/64. Existing priority, service and durable-retirement security regressions pass. The new fragment becomes the24th persistent stage in the next private payload.

Precise bounded indexed preflight diagnostics are included to expose the next failed guard without guessing formats or resource semantics. Physical UI responsiveness and that guard's exact value remain pending the next run.
