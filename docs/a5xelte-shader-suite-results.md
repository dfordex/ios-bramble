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

## 0175 — recovered 2026-10-21

SYSTEM flush 7 recovered 55,941 raw bytes / 791 decoded lines. All 21 configured
cases were evaluated and passed; no cases were skipped. All 46 fences, including
the two existing control pairs, reached terminal completion with header 1 and
MMU IRQ 0. Every suite case reports evaluated=1 and immutable=1.

| Test family | Measured result |
| --- | --- |
| Nine blur/downsample variants | All pass again, including RGBA16Float and TLS cases |
| Rect, cubic and stroke | All three masked reference checks pass again |
| Six buffer-image blit target replays | BGRA8, R8/RG8 and RGBA16Float outputs pass; fences 29–40 complete |
| Home two-texture case | All 4,096 byte components match within 1; fences 41/42 complete |
| Two attachment-clear replays | All 4,096 byte components per output match exactly; fences 43–46 complete |

The unchanged DS4 control also passes 1,024/1,024 pixels, with source and guards
intact. The previous misc fault is absent after the descriptor corrections;
individual attribution between those two corrections remains unisolated.

The entire saved window contains no kernel panic or recorded CRASH marker.
It includes one SpringBoard and one backboardd execution, unchanged installation
of all 13 files with sync=0, and 18 framebuffer measurement windows with swaps=0.
It ends during service startup, before stock Metal acceptance or a displayed
frame is recorded. Absence of a crash in this short window does not establish
stable backboardd operation. Native on-phone compiler completion remains open.

These are real GPU pixel results for bounded private jobs. They do not connect
stock iOS pipeline creation to these compiled functions, resolve every missing
fragment function, or establish general compositor rendering. The original
ordered multi-attachment path-blit pass remains excluded on single-target T720.


## 0178 — recovered 2026-10-22

SYSTEM flush40 yielded101687raw bytes/1301lines. After correcting the shared
preload sampler alignment, all16fences terminate normally, header1/MMU0; the
0177fragment DATA_INVALID_FAULT is absent. Six of seven new tests pass with
all seven evaluated and immutable regions intact. Actual checked counts:
rect768/768, cubic697/697, stroke3328/3328, RAW2044096/4096, R8partial
scissor1024/1024 and standalonephysicalRG82048/2048. Masked path elements
are excluded from these counts. StandaloneRG8 is not active stockprofile proof.

Dynamic32x32blur completes but matches2962/4096byte components (tolerance1),
first_bad384 actual64 expected0. Source audit finds legacyRGBAinput was copied
unchanged into a BGRA-declared runtime texture. Exchanging R/B in the expected
output predicts the exact observed match count and first mismatch, without
changing shader arithmetic. The0179fixture therefore converts only its input
RGBA->BGRA:3712sourcebytes change; G/A, descriptors, uniforms, nativecode,
expectedpixels and guards remain identical. Exactsourceformat/stride and
negativealreadyBGRA tests pass. Correctedinput hardware replay is pending.

The native compiler now records read_surf cache hits, genuine downsample_4
compilation and cache verification, GREEN LINE and DONE. Backboardd accepts14
pipelines with no recorded crash, but native iOS draw completion and rendered
frame presentation remain unproven. Full review:a5xelte-0178-log-review.md.
