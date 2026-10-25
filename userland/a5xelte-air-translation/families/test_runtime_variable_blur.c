/* SPDX-License-Identifier: MIT */
#define PAN_ARCH 4
#include "runtime_misc_encode.h"
#include "genxml/gen_macros.h"
#include "genxml/v4_pack.h"
#include <assert.h>
#include <string.h>
void A5MaliTestVariableBlurDescriptors(const A5MaliCompiledProfile*);
void A5MaliTestVariableBlurDescriptors(const A5MaliCompiledProfile*p){
 static uint8_t jobs[A5RuntimeJobBytes],uniforms[2][31][4096],vertices[256];
 A5RuntimeMiscDraw m={0};m.draw.profile=p;m.draw.descriptorGPUVA=0x02000000;
 m.draw.vertexCount=4;m.draw.primitive=A5RuntimeTriangleStrip;
 m.draw.blend=A5RuntimeBlendState;
 m.draw.viewportWidth=m.draw.scissorWidth=17;m.draw.viewportHeight=m.draw.scissorHeight=9;m.draw.viewportFar=1;
 unsigned row=p->colorFormats[0]==43?48:80;
 m.colorAttachments[0]=(A5RuntimeImage){0x04000000,row*9,17,9,row,p->colorFormats[0]};
 for(unsigned i=0;i<p->resourceCount;i++){
  const A5MaliCompiledResource*r=p->resources+i;
  if(r->kind==A5MaliResourceBuffer)(r->stage==1?m.draw.vertexBuffers:m.draw.fragmentBuffers)[r->metalIndex]=(A5RuntimeBuffer){0,r->uniformBytes,0,uniforms[r->stage-1][r->metalIndex]};
  else if(r->kind==A5MaliResourceTexture)m.fragmentTextures[r->metalIndex]=(A5RuntimeImage){0x06000000,4096,32,32,128,80};
 }
 m.draw.vertexBuffers[1]=(A5RuntimeBuffer){0,A5MaliRuntimeVertexSpan(p,4),0,vertices};
 assert(A5MaliEncodeRuntimeMiscPass(&m,jobs,sizeof(jobs))==A5RuntimeOK);
 pan_unpack((const struct mali_renderer_state_packed*)(jobs+0x500),RENDERER_STATE,vs);
 pan_unpack((const struct mali_renderer_state_packed*)(jobs+0x540),RENDERER_STATE,fs);
 assert(vs.shader.attribute_count==3&&vs.shader.varying_count==4);
 assert(fs.shader.texture_count==1&&fs.shader.sampler_count==1&&fs.shader.varying_count==1);
 pan_unpack((const struct mali_draw_packed*)(jobs+0x140),DRAW,draw);
 unsigned sampler=(unsigned)(draw.samplers-m.draw.descriptorGPUVA);
 assert(sampler+MALI_SAMPLER_LENGTH<=sizeof(jobs));
 pan_unpack((const struct mali_sampler_packed*)(jobs+sampler),SAMPLER,state);
 assert(!state.minify_nearest&&!state.magnify_nearest&&state.normalized_coordinates);
 assert(state.wrap_mode_s==MALI_WRAP_MODE_CLAMP_TO_BORDER&&state.wrap_mode_t==MALI_WRAP_MODE_CLAMP_TO_BORDER&&state.wrap_mode_r==MALI_WRAP_MODE_CLAMP_TO_BORDER);
 assert(!state.border_color_r&&!state.border_color_g&&!state.border_color_b&&!state.border_color_a);
 assert(state.minimum_lod==0&&state.maximum_lod==15);
 unsigned record=0x1400+352;uint32_t u;float f;
 memcpy(&u,jobs+record,4);assert(u==1);memcpy(&u,jobs+record+4,4);assert(u==32);memcpy(&u,jobs+record+8,4);assert(u==32);
 memcpy(&f,jobs+record+16,4);assert(f==0);memcpy(&f,jobs+record+20,4);assert(f==15);memcpy(&f,jobs+record+24,4);assert(f==0);
 A5MaliCompiledProfile bad=*p;A5MaliCompiledSampler s=*p->immutableSamplers;bad.immutableSamplers=&s;
 s.lodMaxClamp=16;assert(!A5MaliDynamicRuntimeProfileSupported(&bad));s=*p->immutableSamplers;s.sAddressMode=A5RuntimeSamplerMirrorRepeat;assert(!A5MaliDynamicRuntimeProfileSupported(&bad));
 bad=*p;bad.flags|=A5MaliProfileDynamicColorVarying;assert(!A5MaliDynamicRuntimeProfileSupported(&bad));
 bad=*p;bad.flags&=~A5MaliProfileVertexTwoUV;assert(!A5MaliDynamicRuntimeProfileSupported(&bad));
}
