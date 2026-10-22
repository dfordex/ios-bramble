# 0199: Metal clip-space Y to upper-left raster rows

The user reports and photographs a visible Apple logo after0198, vertically
inverted relative to the phone. This is physical screen evidence. The0198
SYSTEM log has not yet been recovered, so its pixel counts and CPU/GPU
presentation path are not inferred from the photograph.

## Coordinate contract and correction

The actual AIR translator documents that its SPIR-V uses an upper-left fragment
origin and expects the binder to apply a negative-height viewport. The actual
compiled misc vertex programs preserve clip-space Y, then Panfrost lowers the
position as `position.xyz / w * viewportScale + viewportOffset`; there is no
additional final-position Y negation.

This was checked in the local NIR for profiles200/202/204/206/207 and600–603,
including the live602/603 pair. The source-address arithmetic negation in the
blit shader is separate from its final raster position. All nine programs use
the same runtime misc viewport boundary.

The bridge supplied positive `height/2`. Correct it once to:

```
scaleY  = -height / 2
offsetY = originY + height / 2
```

Thus NDC+1 maps to originY and NDC−1 to originY+height. X, texture UVs,
scissor, vertex/fragment native bytes, the603 normalized sampler and the
source-to-panel copy are unchanged. This is a raster coordinate repair, not
a texture flip or an inversion of the final physical framebuffer.

Separate blur/downsample and path encoders retain their existing tested
conventions; this change covers the nine stock AIR misc profiles. Their own
coordinate contracts need an independent pixel regression before extending
the correction to those encoders.

## Verification

The real Metal→native transport tests now decode the actual emitted viewport
sysvals for602 and the other misc jobs. The603 test uses origin(3,5), size24×20
and independently checks all four NDC boundary mappings: X3..27 and Y5..25.
It also retains the existing immutable shader, texture layout, vertex/UV
snapshot and resource checks, distinguishing raster inversion from changes
to texture coordinates. Transport tests do not establish GPU pixels or the
orientation of the next phone screen.

The phone's0198 log should be recovered before booting the new image. The
next physical trial must confirm the logo orientation and any later UI output.

The full native transport suite and Cortex-A53 provider build pass with the
new Y convention. Actual kernel installer preflight validates the15-file
payload (39,515,958raw /9,450,189packed bytes). Full XNU build including symbols
passes; the resulting0199 BOOT is30,308,368bytes. It has not been flashed:
the phone is still running the observed0198 trial, pending its return to TWRP.
