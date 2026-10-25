/* SPDX-License-Identifier: MIT */
#define PAN_ARCH 4
#include "genxml/v4_pack.h"
#include <assert.h>
#include <string.h>
void A5MaliCheckShaderBlend(const uint8_t*,const float*);
void A5MaliCheckShaderBlend(const uint8_t *jobs,const float *constants){
 struct MALI_RENDERER_STATE state;
 MALI_RENDERER_STATE_unpack((const struct mali_renderer_state_packed*)(jobs+0x540),&state);
 assert(state.multisample_misc.load_destination&&state.blend_equation.color_mask==15);
 assert(state.blend_equation.rgb.a==2&&state.blend_equation.rgb.b==2&&state.blend_equation.rgb.c==1);
 assert(!state.blend_equation.rgb.negate_a&&!state.blend_equation.rgb.negate_b&&!state.blend_equation.rgb.invert_c);
 assert(!memcmp(&state.blend_equation.rgb,&state.blend_equation.alpha,sizeof(state.blend_equation.rgb)));
 assert(!memcmp(jobs+0x1400+480,constants,16));
}
