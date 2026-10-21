/* SPDX-License-Identifier: MIT
 * Independent byte oracle for one BGRA8 mip level, matching an actual Apple M4
 * Metal generateMipmapsForTexture comparison (six shapes, every mip level,
 * maximum per-step channel error1). Released Mesa util_blitter also uses a
 * scaled PIPE_TEX_FILTER_LINEAR blit for util_gen_mipmap. No production shader
 * or runtime emitter includes this test-only header.
 */
#ifndef A5_MIP_LINEAR_REFERENCE_H
#define A5_MIP_LINEAR_REFERENCE_H
#include <math.h>
#include <stdint.h>
static unsigned a5_mip_clamp(int x,unsigned limit){return x<0?0:(unsigned)x>=limit?limit-1:(unsigned)x;}
static uint8_t a5_mip_linear_channel(const uint8_t*source,unsigned row,
 unsigned sw,unsigned sh,unsigned dw,unsigned dh,unsigned x,unsigned y,unsigned c){
 double fx=((double)x+.5)*sw/dw-.5,fy=((double)y+.5)*sh/dh-.5;
 int ix=(int)floor(fx),iy=(int)floor(fy);double ax=fx-ix,ay=fy-iy;
 double top=source[a5_mip_clamp(iy,sh)*row+a5_mip_clamp(ix,sw)*4+c]*(1-ax)+
  source[a5_mip_clamp(iy,sh)*row+a5_mip_clamp(ix+1,sw)*4+c]*ax;
 double bottom=source[a5_mip_clamp(iy+1,sh)*row+a5_mip_clamp(ix,sw)*4+c]*(1-ax)+
  source[a5_mip_clamp(iy+1,sh)*row+a5_mip_clamp(ix+1,sw)*4+c]*ax;
 return (uint8_t)floor(top*(1-ay)+bottom*ay+.5);
}
#endif
