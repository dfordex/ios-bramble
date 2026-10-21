# Typed Midgard BGRA8 encoder

`midgard_encode.c` lowers two fixed graphics operations to Mali-T720 Midgard
v4 descriptors: a BGRA8 source-to-destination rectangle copy and a bounded BGRA8
attachment clear. Copy uses the previously generated 112-byte texture-sample
shader, one tiler job on JS1 and one fragment job on JS0. Clear uses one
fragment job on JS0. The Mesa 26.2.4 fixture supplies the packed shader and
draw descriptors; the framebuffer fields follow its `v4.xml` layout.

The caller must be trusted kernel code. It validates surface ownership, BGRA8
format and single-plane layout, pins/map pages in one GPU address space,
allocates an independent 8 KiB descriptor region, stores CPU caches, submits
the jobs in order, waits for finite fences, invalidates GPU-written caches and
handles faults before releasing any mapping. No user-supplied Mali address,
job, shader or descriptor may pass directly to this encoder. `mapped_bytes`
must be the size of the pinned mapping, and the mapped range must be disjoint
from the descriptor range and the other image.

This implementation limits both images to at most 2048 × 2048 BGRA8
with a 16-byte-aligned row up to 8192 bytes. The copy rectangles may differ in
origin but must have equal dimensions. The destination preload bit preserves
pixels outside the destination rectangle; partial copy and partial clear
have **not** been verified on the phone. Their packed fields pass local tests only. The
full-frame texture-copy path is the existing hardware reference, not proof
that this refactored encoder or a Metal provider works on device.

This does not compile arbitrary Metal/AIR shaders, implement alpha blending,
multiple render targets, texture formats, render passes, resource hazards,
command-buffer scheduling or the Apple Metal/IOGPU discovery ABI. It is not
connected to stock iOS graphics. A build containing only this module must not
claim that SpringBoard rendering runs on Mali.

Run the local descriptor test with:

```sh
clang -std=c11 -Wall -Wextra -Werror -pedantic \
  midgard_encode.c test_midgard_encode.c -o /tmp/a5xelte-midgard-encode-test
/tmp/a5xelte-midgard-encode-test
```

`t720_fixture_words.inc` is the nonzero 0x300–0x93f portion of
`tools/a5xelte-gpu/t720-texture-fixture.bin`; test texels are excluded.
