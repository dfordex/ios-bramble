# 0179 recovered log review — 2026-10-22

Read-only SYSTEM recovery yielded flush36,103333raw bytes and1301decoded lines,
without overwrite. Entire capture reviewed; raw logs remain private.

## Seven GPU oracle cases pass

All seven cases evaluate and pass with immutable regions intact. Rect/cubic
additive coverage, stroke and RAW204 source-over, R8partial-scissor, standalone
physical RG8preload and dynamic32x32blur all complete. Blur now matches4096/4096
byte components within1 after converting only test inputRGBA->BGRA. The expected
pixels, native shader bytes and production emitter are unchanged from0178.
This device replay corroborates the identified input-format defect.

All20 logged fences, including later presentation work, terminate status0,
header1/MMU0. Hardware runtime queue becomes ready. Compiler cache verification
again records GREEN LINE and DONE; the green line remains a CPU status marker.

## First stock command buffer: resources rejected before submission

The new phase records establish the actual ordering:

1. Backboardd creates a Metal queue and command buffer1.
2. It requests776x24 BGRA8 textures with10mip levels. Private attempts are
   rejected as mipmap-level-count; a Memoryless attempt has both that unsupported
   mip count and storage mode, with the first diagnostic reason being mip count.
3. Command buffer1 records its first error, kIOReturnUnsupported/e00002c7, at
   renderCommandEncoderWithDescriptor:.
4. Further texture calls request format43/BGR5A1Unorm and a single-level
   Memoryless BGRA8 texture; both are rejected.
5. Later calls request1D textures, also rejected. They include R16Uint3072,
   R16Float4096, R32Float1024/4096 and RG32Float1024.

These enum names are verified against the local Apple Metal SDK headers.
No sampler or buffer rejection is logged. Fourteen pipeline factory calls across
twelve profiles still succeed. There are no commit begin/result, NativeQuery17,
native-emitter/Submit18 or G3Dnative-completion records. No unretained-buffer
request is recorded. The failure is therefore observed at stock resource/encoder
setup before a recorded commit, not as a submitted native GPU job that hangs.

The776x24/10mip command buffer matches the known QuartzCore warmup scratch
flow, which does not commit. Its first encoding error alone must therefore not
be named the sole UI stopping cause. The later1D requests expose further
resource-setup gaps. The log does not identify the render-pass attachment
responsible for that first encoder error, distinguish every capability probe
from a mandatory UI resource,
or establish that implementing only mip allocation would finish the compositor.
The observed resource contracts need actual storage, format/access and mip
semantics; returning a single-level2D object under another advertised type would
not implement them.

## GPU presentation happens separately

Backboardd creates full-panel BGRA IOSurface2. The existing final-transfer path
completes fences19/20 and logs full-frame source2 shown1. One framebuffer window
accounts one GPU presentation and8294400bytes, exactly one1080x1920x4panel frame;
CPU presentation count/bytes remain0. This is evidence of a GPU surface-to-panel
transfer, not stock Metal rendering of the UI. There is no pixel readback of
that frame; the user reports black except for the green compiler line.

Across72measurement windows (384275ms summed intervals), swaps total6, shown3;
later printed swaps reference default console surface1. One backboardd and one
SpringBoard execution are recorded, with no CRASH or kernel panic. Four key
transitions/HID delivery and later services continue to the capture end.

## Next implementation boundary

The measured gaps are texture resource contracts: proper mip subresource layout
and operations, Memoryless render-pass semantics, actual requested format
packing/access, and1D textures including widths beyond the current2048 limit. Shared1D lookup
resources also need genuine CPU replaceRegion transfer/cache/upload semantics;
currently those methods reject CPU texture transfer. Accepting allocation alone
would expose the next unsupported access path.
After those are implemented, retain these phase records to identify subsequent
encoding/submission requirements. Seven private GPU tests and one final transfer
do not establish general iOS compositor rendering.
