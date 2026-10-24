/* SPDX-License-Identifier: MIT
 * Actual published untextured shaders through the production native emitter.
 * Transport checks do not claim physical GPU execution. */
#include "../a5xelte-air-translation/families/runtime_misc_encode.h"
#include "genxml/v4_pack.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static int zero(const uint8_t*p,size_t n){for(size_t i=0;i<n;i++)if(p[i])return 0;return 1;}
static unsigned colorOnly,fetch;
void A5MaliCheckUntexturedNative(const uint8_t*d);
void A5MaliCheckUntexturedNative(const uint8_t*d){
 struct MALI_DRAW draw;MALI_DRAW_unpack((const struct mali_draw_packed*)(d+0x140),&draw);
 struct MALI_RENDERER_STATE rs;MALI_RENDERER_STATE_unpack((const struct mali_renderer_state_packed*)(d+0x540),&rs);
 assert(!draw.textures&&!draw.samplers&&!rs.shader.texture_count&&!rs.shader.sampler_count);
 assert(rs.shader.varying_count==colorOnly);
 if(colorOnly){assert(draw.varyings&&draw.varying_buffers);}
 else assert(!draw.varyings&&!draw.varying_buffers&&zero(d+0xc00,0x100));
 if(fetch)assert(rs.multisample_misc.load_destination);
}
static void setup(A5RuntimeMiscDraw*m,const A5MaliCompiledProfile*p,uint8_t*v,uint8_t u[2][31][4096],unsigned blend){
 memset(m,0,sizeof(*m));m->draw.profile=p;m->draw.vertexCount=6;
 m->draw.primitive=A5RuntimeTriangle;m->draw.descriptorGPUVA=0x02000000;
 m->draw.blend=blend?A5RuntimeBlendPremultipliedSourceOver:A5RuntimeBlendCopy;
 m->draw.viewportWidth=m->draw.viewportHeight=32;m->draw.viewportFar=1;
 m->draw.scissorWidth=m->draw.scissorHeight=32;
 for(unsigned i=0;i<p->resourceCount;i++){
  const A5MaliCompiledResource*r=p->resources+i;
  assert(r->kind!=A5MaliResourceTexture&&r->kind!=A5MaliResourceSampler);
  if(r->kind!=A5MaliResourceBuffer)continue;
  (r->stage==1?m->draw.vertexBuffers:m->draw.fragmentBuffers)[r->metalIndex]=(A5RuntimeBuffer){0,r->uniformBytes,0,u[r->stage-1][r->metalIndex]};
 }
 m->draw.vertexBuffers[1]=(A5RuntimeBuffer){0,288,0,v};
 m->colorAttachments[0]=(A5RuntimeImage){0x04000000,4096,32,32,128,80};
 colorOnly=!!(p->flags&A5MaliProfileFragmentColorOnly);fetch=!!(p->flags&A5MaliProfileFramebufferFetch);
}
int A5MaliTestUntexturedProfile(const A5MaliCompiledProfile*p,int blend);
int A5MaliTestUntexturedProfile(const A5MaliCompiledProfile*p,int blend){
 assert(A5MaliDynamicRuntimeProfileSupported(p));
 assert((p->passes[0].fragment.byteCount==2240&&p->passes[0].fragment.firstTag==8)||
        (p->passes[0].fragment.byteCount==176&&p->passes[0].fragment.firstTag==5));
 assert(!!(p->flags&A5MaliProfileFragmentColorOnly)==(p->passes[0].fragment.byteCount==2240));
 assert(!!(p->flags&A5MaliProfileFramebufferFetch)==(p->passes[0].fragment.byteCount==2240));
 static uint8_t u[2][31][4096];uint8_t v[288]={0};A5RuntimeMiscDraw m;setup(&m,p,v,u,blend);
 uint8_t*d=malloc(A5RuntimeJobBytes);assert(d);
 assert(!A5MaliEncodeRuntimeMiscPass(&m,d,A5RuntimeJobBytes));A5MaliCheckUntexturedNative(d);
 assert(!memcmp(d+0x8000,p->passes[0].fragment.bytes,p->passes[0].fragment.byteCount));
 struct MALI_RENDERER_STATE rs;MALI_RENDERER_STATE_unpack((const struct mali_renderer_state_packed*)(d+0x540),&rs);
 assert(rs.properties.uniform_buffer_count==(colorOnly?3u:1u));
 assert(rs.properties.work_register_count==p->passes[0].fragment.workRegisters);
 if(colorOnly){
  struct MALI_ATTRIBUTE_BUFFER a;MALI_ATTRIBUTE_BUFFER_unpack((const struct mali_attribute_buffer_packed*)(d+0xc80),&a);
  assert(a.pointer==m.draw.descriptorGPUVA+((p->flags&A5MaliProfileVertexColorOnly)?0x32000:(p->flags&A5MaliProfileVertexTwoUV)?0x34000:0x33000)&&a.stride==16&&a.size==96);
  struct MALI_ATTRIBUTE color;MALI_ATTRIBUTE_unpack((const struct mali_attribute_packed*)(d+0xc00),&color);
  assert(color.buffer_index==0&&(color.format>>12)==MALI_RGBA32F);
  m.draw.fragmentBuffers[1].bytes=135;assert(A5MaliEncodeRuntimeMiscPass(&m,d,A5RuntimeJobBytes)&&zero(d,A5RuntimeJobBytes));
  m.draw.fragmentBuffers[1].bytes=168;
 }
 A5MaliCompiledProfile bad=*p;
 if(colorOnly){
  const unsigned invalid[]={A5MaliProfileFragmentNoInputs,A5MaliProfileFragmentTwoUV,A5MaliProfileFragmentPosition,A5MaliProfileDynamicColorVarying,A5MaliProfileFramebufferFetch};
  for(unsigned i=0;i<sizeof(invalid)/sizeof(*invalid);i++){bad=*p;bad.flags^=invalid[i];assert(!A5MaliDynamicRuntimeProfileSupported(&bad));}
 }else{bad=*p;bad.flags|=A5MaliProfileFramebufferFetch;assert(!A5MaliDynamicRuntimeProfileSupported(&bad));}
 A5MaliCompiledResource added[17];assert(p->resourceCount<17);memcpy(added,p->resources,p->resourceCount*sizeof(*added));
 added[p->resourceCount]=(A5MaliCompiledResource){2,A5MaliResourceSampler,0,7,0,A5MaliResourceRead,0,0,0,0};
 bad=*p;bad.resources=added;bad.resourceCount++;assert(!A5MaliDynamicRuntimeProfileSupported(&bad));
 bad=*p;bad.flags|=colorOnly?A5MaliProfileFragmentNoInputs:A5MaliProfileFragmentColorOnly;
 assert(!A5MaliDynamicRuntimeProfileSupported(&bad));m.draw.profile=&bad;
 assert(A5MaliEncodeRuntimeMiscPass(&m,d,A5RuntimeJobBytes)&&zero(d,A5RuntimeJobBytes));
 m.draw.profile=p;m.colorAttachments[0].gpuVA=m.draw.descriptorGPUVA;
 assert(A5MaliEncodeRuntimeMiscPass(&m,d,A5RuntimeJobBytes)&&zero(d,A5RuntimeJobBytes));
 free(d);printf("PASS actual untextured FS%u native descriptor/UBO/alias contracts blend=%d; no GPU execution\n",p->passes[0].fragment.byteCount,blend);return 1;
}
int A5MaliWriteUntexturedFixture(const A5MaliCompiledProfile*p,const char*path);
int A5MaliWriteUntexturedFixture(const A5MaliCompiledProfile*p,const char*path){
 static uint8_t u[2][31][4096];memset(u,0,sizeof(u));uint8_t v[576]={0};
 /* Two constant-alpha quads distinguish genuine interpolated colour from
  * UV, zero/missing interpolants, and either half of the real target. */
 const float pos[6][2]={{0,0},{1,0},{0,1},{0,1},{1,0},{1,1}};
 for(unsigned q=0;q<2;q++)for(unsigned i=0;i<6;i++){
  unsigned n=q*6+i;float xyz[]={16*(q+pos[i][0]),32*pos[i][1],0,1};
  uint16_t color[]={0x3800,0x3400,0x3a00,q?0x3a00:0x3400};
  memcpy(v+48*n,xyz,16);memcpy(v+48*n+32,color,8);
 }
 float matrix[16]={0};matrix[0]=2.f/32;matrix[5]=-2.f/32;matrix[10]=matrix[15]=1;matrix[12]=-1;matrix[13]=1;
 memcpy(u[0][2],matrix,64);
 /* Actual cubic coefficients, half4 at live FragmentBuffer1 byte128: f(L)=1. */
 const uint16_t cubic[]={0,0,0,0x3c00};memcpy(u[1][1]+128,cubic,8);
 A5RuntimeMiscDraw m;setup(&m,p,v,u,0);m.draw.vertexCount=12;m.draw.vertexBuffers[1].bytes=sizeof(v);
 static uint8_t d[A5RuntimeJobBytes];assert(!A5MaliEncodeRuntimeMiscPass(&m,d,sizeof(d)));A5MaliCheckUntexturedNative(d);
 struct MALI_FRAMEBUFFER_PARAMETERS fb;MALI_FRAMEBUFFER_PARAMETERS_unpack((const struct mali_framebuffer_parameters_packed*)(d+0x320),&fb);fb.color_writeback.base=m.draw.descriptorGPUVA+0x3e000;MALI_FRAMEBUFFER_PARAMETERS_pack((struct mali_framebuffer_parameters_packed*)(d+0x320),&fb);
 struct MALI_SURFACE_WITH_STRIDE pre;MALI_SURFACE_WITH_STRIDE_unpack((const struct mali_surface_with_stride_packed*)(d+0x19a0),&pre);pre.pointer=m.draw.descriptorGPUVA+0x3e000;MALI_SURFACE_WITH_STRIDE_pack((struct mali_surface_with_stride_packed*)(d+0x19a0),&pre);
 memset(d+0x39000,0xa7,0x5000);memset(d+0x3f000,0xa7,0x1000);
 const uint8_t initial[]={32,64,96,128};for(unsigned i=0;i<4096;i+=4)memcpy(d+0x3e000+i,initial,4);
 FILE*f=fopen(path,"wb");assert(f&&fwrite(d,1,sizeof(d),f)==sizeof(d)&&!fclose(f));return 1;
}
