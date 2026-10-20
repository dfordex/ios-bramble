# T720 texture-copy shader fixture

`t720-copy-16x16.bin` is a 112-byte Midgard fragment shader generated with
Mesa 26.2.4 from `gen-t720-copy-shader.c`. The input is texture 0 with sampler
0; UV coordinates come from interpolated varying 0. The shader writes color
attachment 0. Its disassembly includes `TEX_GRAD.2d` and uses two work
registers. SHA-256:

`d69aa8e48bc24e6518ea9d3c027ca808bf96fa172e2132e176554bc032572d7e`

This is an **offline compile result only**. It has not sampled a texture on
the phone. It needs a T720 texture/sampler descriptor, varying buffer,
renderer state, tiler job and fragment job, plus a pinned source/destination
mapping and completion verification. Do not submit it with the current
fragment-clear descriptor alone.

To regenerate, add the C source as an executable to a Mesa 26.2.4 Panfrost
tool build. It links with `libpanfrost_compiler`, `idep_nir`, `idep_mesautil`,
`idep_bi_opcodes_h`, and `dep_libdrm`. Build full NIR (the tools-only default
uses `nir_stub.c`). Run the executable with an output path and compare the
printed Midgard disassembly and SHA-256. No Mesa or IPSW source is committed.
