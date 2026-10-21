# Mac shader GPU suite: measured phone results

## 0174 — recovered 2026-10-21

SYSTEM flush12 recovered53,818 raw bytes /785 decoded lines. This is hardware
execution of locally generated shader fixtures, separate from stock iOS draws.

| Test | Measured result |
| --- | --- |
| Existing downsample4 control | 1,024/1,024 pixels; source4,096/4,096 and guards2,048/2,048 intact |
| Eight BGRA blur/downsample cases | All4,096 byte components/case match within1; all fences complete and immutable regions intact |
| Blur23 RGBA16Float | All4,096 half components match within1 ULP; actual TLS and raw half packing execute successfully |
| Rect coverage | Masked interior/exterior reference checks pass; terminal fences23/24, immutable regions intact |
| Cubic coverage | Masked interior/exterior reference checks pass; terminal fences25/26, immutable regions intact |
| Stroke RGBA16Float | Masked reference checks pass exactly; terminal fences27/28, immutable regions intact |
| First buffer-blit | Vertex/tiler chain fence29 has MMU fault; no fragment submission/readback |
| Remaining eight misc cases | Not executed after queue halt |

The suite reports12 passes /12 evaluated /21 configured. Boundary masks on
the path/stroke cases exclude raster-edge uncertainty; masked-out elements
must not be counted as independently checked pixels. All nine blur cases have
unmasked full32x32 output comparisons. The passed tests exercise genuine
translated vertex and fragment code, dynamic inputs, SSBO reads and native
format conversion. They do not establish a complete QuartzCore render graph.

The first failing submission is the tiler at job address0x02000100. Its
captured fault address is0x02181ff0, MMU IRQ1, fault status0x100002c3.
The queue retained its pinned pages and stopped further submissions; the
failed case's immutable status was not evaluated. Patch0176 makes that last
distinction explicit in later per-case log lines.

## Source-backed descriptor corrections for 0175

Released v4 `ATTRIBUTE_BUFFER` descriptors are16 bytes, while the misc builder
placed varying descriptors at32-byte steps with consecutive buffer indices.
The InstanceID attribute also selected index1, although its special descriptor
was deliberately placed at+32 bytes, physical index2. Both are malformed
references; the passed blur/path builders use the actual16-byte table stride.

The corrected builder uses `pan_size(ATTRIBUTE_BUFFER)` consistently and binds
InstanceID index2. Packed readback checks every used varying pointer/stride/
size plus both special indices. It rejects the actual old phone-fault payload;
independent reintroduction of either indexing mistake is rejected too.

All nine corrected payloads keep shader bytes and CPU reference files unchanged.
Only descriptor bytes differ:63 per buffer-blit case,24 for home and11 per
clear case. The fault address is consistent with SSBO base0x02002000 plus
65535*24+8, but the two defects are corrected together; their individual causal
contributions have not been isolated on the phone.

The saved0174 window has no kernel panic or recorded process crash, no completed
stock-device acceptance response and no displayed frame. It contains one
SpringBoard/backboardd launch each,13 unchanged installer files with sync0 and
28 framebuffer metric windows with swaps0. It cannot establish later UI state.

0175 GPU results remain pending the next phone run. Native on-phone compiler
completion and general iOS GPU rendering are still separate open checks.
