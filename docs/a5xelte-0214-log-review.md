# 0214 complete capture and 0215 candidate

## Recovered phone evidence

The SYSTEM capture is complete:772,359bytes,9,215lines,flush151, with the expected0214 kernel timestamp. No wrap or kernel panic appears. Raw logs and HFS files remain private.

The actual602 source-over case passes4096/4096 elements with both fences successful, MMU0 and immutable inputs. The full physical suite passes41/45. Four earlier raw204/R8/ordered-fetch fixtures still fail; this result does not establish general compositor correctness.

No texture rejection or import/map selector failure appears. Real logical imports reach33, above the former32-entry limit; capacity128 is active. Thirty-two logged native submission samples report status0/MMU0, and completed command buffers2–7 report status4/error0. Framebuffer samples include real GPU copies with matching sampled source/panel pixels.

Home, Power and volume events are delivered. HID queue head advances through14,336 without a full queue, with one consumer before the final crash. Thus the user's unresponsive lock screen is not evidence that keys stopped reaching iOS. After backboardd exits, its HID consumer disappears.

## Exact new draw rejection

Command buffer8 requests profile99 DS4 with linear minification and magnification, source137x242 BGRA/IOSurface and target100x64. The implementation explicitly rejects `unverified-DS4-linear`, then fails the indexed draw with Unsupported. This is a concrete missing path, separate from the later render-pipeline abort.

The0215 change removes only that filter restriction. Released Mesa26.2.4 sampler packing preserves each requested min/mag filter; other sampler constraints remain. Fresh stock AIR translation and SPIR-V validation reproduce the genuine3472-byte DS4 fragment and2048-byte vertex for all four filtering combinations. Machine code is identical: filtering is descriptor state. No Apple programs are committed.

Host tests exercise all10blur profiles and four min/mag combinations, plus the actual137x242/100x64 request through the real wrapper/Query17/Submit18 paths. Two physical indexed u16/u32 cases use fractional/clamped coordinates and independent4096-byte pixel references. A nearest-filter counterfactual differs at1,000bytes per case. These two device pixel results are pending;47cases are prepared in total.

## Final backboardd abort

Two new fragments publish on the phone (1168 and992bytes), followed by an1808-byte vertex. Backboardd then aborts with namespace13/code4, `Metal failed to build render pipeline`. Startup logging had exhausted its budget, so the exact final rejected descriptor/reason is absent. Historical error strings in retained heap samples are not treated as the current failure.

Both fragments were recovered and authenticated through the actual provider cache loader. The last vertex publication was absent from both the checkpointed HFS catalog and validated journal view. Read-only journal inspection checks17transactions and518blocks; no catalog bytes differ. This does not prove why the newest publication is absent.

The production worker was rebuilt on the Mac using the pinned AIR source and released Mesa. It produces the genuine vertex with its actual typed constants; native bytes match the existing compact position/color vertex. Both complete descriptor states found across22 recovered fixed pipelines (copy and source-over) pass the real loader, factory and native emitter with the actual vertex/fragment. No ABI or descriptor relaxation is justified by this evidence.

Independent, bounded terminal rejection receipts now cover every dynamic composer gate, include canonical stage identities and report the first mismatched attribute/layout. A separate shared48-receipt limit covers the public factory and synchronous/asynchronous reflection-option entry gates without changing their admission or callback behavior. The final abort remains unresolved until its actual failing contract is captured.

PosterBoard separately traps at the previously identified first-time switcher-state invariant. No new CPU-instruction explanation or missing-package conclusion follows from that trap. No SpringBoard crash appears in this capture.

## Persistent shader cache

The existing worker writes native code, reflection and receipt, fsyncs each file and its staged directory, atomically renames the publication and fsyncs its parent. Requests are keyed by source, typed constants, stage and compiler ABI. Accepted cache entries avoid recompilation; new variants still need their first compilation. An accepted stage is not a guarantee that its complete pipeline is supported.

All21 exact captured function requests (2vertex/19fragment) have now been compiled with the real production worker on the Mac. The next incremental payload carries authenticated outputs, preserving the existing four publications and removing first-compilation waits for the additional17. The phone compiler remains available for genuinely new variants. The rebuilt Mac AIR tool uses a newly resolved dependency lock because the older private lock was cloud-only; this provenance difference is recorded privately. Both recovered phone fragment publications match the rebuilt host code, reflection and receipt byte for byte. All21 publications total295,532bytes, including36,864bytes of native code. The phone compiler itself is unchanged.

## Status

Source/host verification and provider compilation pass. Physical DS4 filtering, lock-screen interaction and the exact final pipeline rejection remain device checkpoints. No0215 write has occurred at this documentation checkpoint.
