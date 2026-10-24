/* SPDX-License-Identifier: MIT
 * Decode real producer RSD state against released Mesa v4 definitions.
 * Host arithmetic/descriptor checks do not claim physical GPU pixel proof. */
#define PAN_ARCH 4
#include "genxml/v4_pack.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
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

#include "../../a5mali-metal/A5MaliRenderState.h"
_Static_assert(MALI_BLEND_OPERAND_A_ZERO==1&&MALI_BLEND_OPERAND_A_SRC==2&&MALI_BLEND_OPERAND_A_DEST==3,"released v4 A encodings");
_Static_assert(MALI_BLEND_OPERAND_B_SRC_MINUS_DEST==0&&MALI_BLEND_OPERAND_B_SRC_PLUS_DEST==1&&MALI_BLEND_OPERAND_B_SRC==2&&MALI_BLEND_OPERAND_B_DEST==3,"released v4 B encodings");
_Static_assert(MALI_BLEND_OPERAND_C_ZERO==1&&MALI_BLEND_OPERAND_C_SRC==2&&MALI_BLEND_OPERAND_C_DEST==3&&MALI_BLEND_OPERAND_C_SRC_ALPHA==5&&MALI_BLEND_OPERAND_C_DEST_ALPHA==6,"released v4 C encodings");
void A5MaliCheckLoweredBlendState(const uint8_t*,const A5MaliCompiledAttachmentState*);
void A5MaliCheckLoweredBlendState(const uint8_t*jobs,const A5MaliCompiledAttachmentState*input){
 struct MALI_RENDERER_STATE rs;MALI_RENDERER_STATE_unpack((const struct mali_renderer_state_packed*)(jobs+0x540),&rs);
 A5MaliBlendPlan p=A5MaliLowerRenderState(input);assert(p.route==A5MaliStateFixed);
 assert(rs.blend_equation.color_mask==p.writeMask);
 /* Existing copy mode may omit a conservative destination load. */
 if(input->blendEnabled||input->writeMask!=15)assert(rs.multisample_misc.load_destination==p.loadDestination);
 const struct MALI_BLEND_FUNCTION *out[2]={&rs.blend_equation.rgb,&rs.blend_equation.alpha};
 const A5MaliBlendEquation *want[2]={&p.rgb,&p.alpha};
 for(unsigned i=0;i<2;i++){
 if(out[i]->a!=want[i]->a||out[i]->b!=want[i]->b||out[i]->c!=want[i]->c)fprintf(stderr,"STATE mismatch channel%u actual=%u/%u/%u expected=%u/%u/%u metal=%u/%u op=%u\n",i,out[i]->a,out[i]->b,out[i]->c,want[i]->a,want[i]->b,want[i]->c,input->sourceRGB,input->destinationRGB,input->rgbOperation);
 assert(out[i]->a==want[i]->a&&out[i]->b==want[i]->b&&out[i]->c==want[i]->c&&out[i]->invert_c==want[i]->invertC&&out[i]->negate_a==want[i]->negateA&&out[i]->negate_b==want[i]->negateB);
 }
}
