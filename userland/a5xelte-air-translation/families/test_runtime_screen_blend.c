/* SPDX-License-Identifier: MIT
 * Decode real producer RSD state against released Mesa v4 definitions.
 * Host arithmetic/descriptor checks do not claim physical GPU pixel proof. */
#define PAN_ARCH 4
#include "genxml/v4_pack.h"
#include <assert.h>
#include <math.h>
#include <stdint.h>
void A5MaliCheckScreenBlendState(const uint8_t*,unsigned);
void A5MaliCheckScreenBlendState(const uint8_t*jobs,unsigned mode){
 pan_unpack((const struct mali_renderer_state_packed*)(jobs+0x540),RENDERER_STATE,s);
 assert(mode<=2&&s.multisample_misc.load_destination==!!mode);
 assert(s.blend_equation.rgb.a==MALI_BLEND_OPERAND_A_SRC);
 assert(s.blend_equation.rgb.b==(mode?MALI_BLEND_OPERAND_B_DEST:MALI_BLEND_OPERAND_B_SRC));
 assert(s.blend_equation.rgb.c==(mode==2?MALI_BLEND_OPERAND_C_SRC:mode?MALI_BLEND_OPERAND_C_SRC_ALPHA:MALI_BLEND_OPERAND_C_ZERO));
 assert(s.blend_equation.alpha.c==(mode?MALI_BLEND_OPERAND_C_SRC_ALPHA:MALI_BLEND_OPERAND_C_ZERO));
 assert(s.blend_equation.rgb.invert_c==!!mode&&s.blend_equation.alpha.invert_c==!!mode);
 if(mode==2){
  const float src[]={.25f,.5f,.75f,.8f},dst[]={.8f,.1f,.3f,.6f},want[]={.85f,.55f,.825f,.92f};
  for(unsigned c=0;c<4;c++)assert(fabsf(src[c]+dst[c]*(1-src[c])-want[c])<.00001f);
  assert(fabsf(src[0]+dst[0]*(1-src[3])-want[0])>.4f); /* alpha-only blend would be wrong */
 }
}
