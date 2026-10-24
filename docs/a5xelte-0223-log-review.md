# 0223 device log review

**Verdict: FAIL for complete interactive UI; direct compiler startup and RAM capacity are verified in this capture.**

The full SYSTEM ring contains 1,293,039 logical bytes at flush 123, with 14,466 decoded lines and no overwritten bytes. Only recovery reads were performed. This run gets past the previous intermediary startup stall and reaches the real Mali compiler. A varying-layout assertion then aborts that compiler and causes a repeated compositor failure. An independent packed-source blur rejection is also recorded.

## Device evidence

Line numbers below refer to the private decoded full capture, which is not committed.

| Evidence | Location | Result |
| --- | --- | --- |
| RAM bootstrap | line 4 | 172,445 free + 15,971 wired pages = 188,416 4 KiB pages = 736 MiB. Capacity is verified; exhaustive allocation stability is not. |
| Real translator execution | 5355–5616 | Direct spawn and EXEC_OBSERVED; AIR/SPIR-V translator exits zero after 34.700 seconds. Its own diagnostic reports verified PASS. |
| Real Mali backend execution | 5617–5852 | EXEC_OBSERVED, then SIGABRT after 11.844 seconds. Exact assertion is in pan_varying_collect_formats, pan_nir_collect_varyings.c:370. |
| Packed blur source rejected | 3620–3632 | Profile 99 receives source format 43, 542×963, and target format 80, 139×4. CB9 rejects before submission with e00002c7. |
| Completed GPU work | throughout | 187 recorded command-buffer results are Completed/error0/submitted1 across process lifetimes; one is Error/e00002c7/submitted0. These are records, not 187 globally unique command-buffer IDs. |
| Input | throughout | 109 HID touch records, 249 hardware-key records; sampled key queue advances to head 8192 with full=0. These do not establish visible interactive UI. |
| Process crashes | 5801, 6669, 7381, 10261, 12037, 13712, 14375 | One compiler abort, five backboardd aborts (three fragment specialization, two render pipeline), one SpringBoard abort. No kernel panic is recorded. |
| Storage | final counters 14151–14153 | 3,537,734,144 read bytes, 192,293,888 written bytes, zero errors. Controller-lock active time 688,757 ms, aggregate wait 12,770,664 ms; logger time 2,318 ms. Active includes preemption while holding the lock; this is not raw card busy time. Different workload/lifetime prevents an isolated speed comparison. |

## Findings and next corrections

| Priority | Finding | Evidence and smallest next step |
| --- | --- | --- |
| P1 | Native compiler varying indices collide. | The exact captured assertion rejects an already populated layout slot. The unchanged official Mesa 26.2.4 collector indexes that slot from each intrinsic's base. Our dynamic fragment-coordinate lowering hardcodes base 2 in families/misc_backend.c. Reproduce the captured noise-enabled stage, inspect live input bases, then allocate nonoverlapping indices consistently with reflected runtime descriptors. Do not disable the assertion. The precise colliding pair remains unverified because the full intermediate shader was deleted. |
| P1 | Blur source format 43 is unsupported. | A5MaliMetalAPI.m:1366 accepts BGRA8 only for this route; the actual view is BGR5A1. Implement sampling format/swizzle/row-stride handling and an independent packed-source pixel test before admitting it. Simply removing the format check is not a fix. |
| P1 | Pipeline admission still has descriptor restrictions. | Later crash scans retain float2-vs-float4 vertex attribute and blend-enabled-vs-disabled mismatches. Three small exact request/status reads confirm terminal pipeline requests are marked unsupported by the old exact-pair gate; this is distinct from compiling a typed function. Validate the actual requested vertex packing and source-over descriptor together with the native pipeline, rather than fabricating a matching descriptor. |
| P2 | Failure diagnostics discard the intermediate workspace. | a5shader_compile.m:62–71 emits only the final 2,048 bytes of each tool log, removes activeWork, then records a failure path into that removed directory. Targeted recovery reads confirm the named intermediate files are absent while the exact function request and failed status survive. Preserve a bounded failure summary/input-layout diagnostic for future failures. |

The captured new function uses noise, fragment coordinates and framebuffer fetch. Its raw request is preserved privately. It reaches genuine AIR translation automatically, but no `STAGE PUBLISHED` appears; calling automatic compilation complete would be incorrect. Three additional recovered pipeline requests and four worker statuses are retained privately. Two bounded HFS reads fetched 310,272 physical bytes including catalog nodes; the whole USERDATA partition was not transferred.

SpringBoard's recorded exception follows the first backboardd death and reports an interrupted AttentionAwareness connection. The log supports fixing the compositor failure first, not claiming an independent input-driver or AttentionAwareness root cause. Successful presentation records continue across restarts, so the device is not a total GPU or kernel hang.

The official collector source was compared read-only using the [Mesa 26.2.4 source](https://gitlab.freedesktop.org/mesa/mesa/-/blob/mesa-26.2.4/src/panfrost/compiler/pan_nir_collect_varyings.c). Source inspection identifies the slot-collision contract; actual regression replay and the fixes remain pending. No new BOOT was written or reboot requested during this review.
