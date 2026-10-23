/* SPDX-License-Identifier: MIT
 * Physical GPU oracle using a profile composed by the actual dynamic provider.
 * This code supplies vertices/resources and builds real runtime jobs. It never
 * computes reference output pixels; the independent Python oracle does that.
 */
#define PAN_ARCH 4
#include "runtime_misc_encode.h"
#include "genxml/v4_pack.h"
#include <assert.h>
#include <string.h>

enum { BASE=0x02000000,SOURCE=0x3a000,OUTPUT=0x3e000,GUARD=0x3f000 };
int A5MaliBuildDynamicFixture(const A5MaliCompiledProfile *,void *,size_t,int);
int A5MaliBuildDynamicFixture(const A5MaliCompiledProfile *p,void *output,size_t length,int blend)
{
 if(!p||!output||length!=A5RuntimeJobBytes)return 0;
 uint8_t *bytes=output;
 assert(p->profileID==A5MaliDynamicProfileID&&(p->flags&A5MaliProfileDynamicStages));
 assert(A5MaliDynamicRuntimeProfileSupported(p)&&p->passCount==1);
 unsigned b1=0,b2=0;
 for(unsigned i=0;i<p->resourceCount;i++){
  const A5MaliCompiledResource *r=p->resources+i;
  if(r->stage==A5MaliStageFragment&&r->kind==A5MaliResourceBuffer){
   if(r->metalIndex==1)b1++;
   if(r->metalIndex==2){assert(r->nativeIndex==4&&r->uniformBytes==4);b2++;}
  }
 }
 assert(!b1&&b2==1); /* genuinely live reflected ABI, not profile606's B1 */
 uint8_t vertices[192]={0};
 for(unsigned i=0;i<4;i++){
  float x=(float)(i&1)*32,y=(float)(i>>1)*32;
  const float position[4]={x,y,0,1},uv[2]={x/32,y/32};
  const uint16_t color[4]={0x3800,0x3400,0x3c00,0x3800};
  memcpy(vertices+i*48,position,16);memcpy(vertices+i*48+16,uv,8);
  memcpy(vertices+i*48+32,color,8);
 }
 float matrix[16]={0};matrix[0]=2.f/32;matrix[5]=-2.f/32;
 matrix[10]=matrix[15]=1;matrix[12]=-1;matrix[13]=1;
 const float transform[4]={1,1,0,0},bias=0;
 A5RuntimeMiscDraw m={0};m.draw.profile=p;m.draw.descriptorGPUVA=BASE;
 m.draw.vertexBuffers[1]=(A5RuntimeBuffer){0,sizeof(vertices),0,vertices};
 m.draw.vertexBuffers[2]=(A5RuntimeBuffer){0,sizeof(matrix),0,(const uint8_t*)matrix};
 m.draw.vertexBuffers[3]=(A5RuntimeBuffer){0,sizeof(transform),0,(const uint8_t*)transform};
 m.draw.fragmentBuffers[2]=(A5RuntimeBuffer){0,sizeof(bias),0,(const uint8_t*)&bias};
 m.colorAttachments[0]=(A5RuntimeImage){0x04000000,4096,32,32,128,80};
 m.fragmentTextures[3]=(A5RuntimeImage){0x03000000,1024,32,32,32,1};
 m.fragmentSamplers[0]=(A5RuntimeSampler){.valid=1,.normalizedCoordinates=1,.maxAnisotropy=1};
 m.draw.vertexCount=4;m.draw.primitive=A5RuntimeTriangleStrip;
 m.draw.blend=blend?A5RuntimeBlendPremultipliedSourceOver:A5RuntimeBlendCopy;
 m.draw.scissorWidth=m.draw.scissorHeight=32;
 m.draw.viewportWidth=m.draw.viewportHeight=32;m.draw.viewportFar=1;
 if(A5MaliEncodeRuntimeMiscPass(&m,bytes,length))return 0;
 assert(!memcmp(bytes+0x6000,p->passes[0].vertex.bytes,p->passes[0].vertex.byteCount));
 assert(!memcmp(bytes+0x8000,p->passes[0].fragment.bytes,p->passes[0].fragment.byteCount));
 /* Suite-only relocation after the production emitter's non-alias checks. */
 pan_unpack((const struct mali_surface_with_stride_packed*)(bytes+0x620),SURFACE_WITH_STRIDE,s);
 s.pointer=BASE+SOURCE;MALI_SURFACE_WITH_STRIDE_pack((struct mali_surface_with_stride_packed*)(bytes+0x620),&s);
 pan_unpack((const struct mali_framebuffer_parameters_packed*)(bytes+0x320),FRAMEBUFFER_PARAMETERS,fb);
 fb.color_writeback.base=BASE+OUTPUT;
 fb.color_preload_enable=false;fb.color_load_address=0;fb.color_load_row_stride=0;fb.color_load_surface_stride=0;
 fb.clear_color_0=fb.clear_color_1=fb.clear_color_2=fb.clear_color_3=0;
 MALI_FRAMEBUFFER_PARAMETERS_pack((struct mali_framebuffer_parameters_packed*)(bytes+0x320),&fb);
 pan_unpack((const struct mali_surface_with_stride_packed*)(bytes+0x19a0),SURFACE_WITH_STRIDE,pre);
 pre.pointer=BASE+OUTPUT;MALI_SURFACE_WITH_STRIDE_pack((struct mali_surface_with_stride_packed*)(bytes+0x19a0),&pre);
 memset(bytes+0x39000,0xa7,0x1000);memset(bytes+SOURCE,0x5b,0x4000);
 for(unsigned y=0;y<32;y++)for(unsigned x=0;x<32;x++)bytes[SOURCE+y*32+x]=(uint8_t)(x*5+y*7+13);
 memset(bytes+OUTPUT,0xcd,4096);memset(bytes+GUARD,0xa7,4096);
 if(blend)for(unsigned i=0;i<4096;i+=4){bytes[OUTPUT+i]=32;bytes[OUTPUT+i+1]=64;bytes[OUTPUT+i+2]=96;bytes[OUTPUT+i+3]=128;}
 pan_unpack((const struct mali_texture_packed*)(bytes+0x600),TEXTURE,tex);
 assert(tex.width==32&&tex.height==32&&tex.levels==1);
 assert(tex.format==((MALI_R8_UNORM<<12)|0x124)&&tex.swizzle==0x688);
 pan_unpack((const struct mali_renderer_state_packed*)(bytes+0x540),RENDERER_STATE,fs);
 assert(fs.shader.texture_count==1&&fs.shader.sampler_count==1&&fs.shader.varying_count==1);
 assert(fs.multisample_misc.load_destination==(bool)blend);
 pan_unpack((const struct mali_uniform_buffer_packed*)(bytes+0x740+4*8),UNIFORM_BUFFER,lod);
 assert(lod.entries==1&&lod.pointer>=BASE+0x20000&&lod.pointer+4<=BASE+0x30000);
 assert(!memcmp(bytes+(unsigned)(lod.pointer-BASE),&bias,4));
 assert(s.row_stride==32&&s.surface_stride==1024&&fb.color_writeback.row_stride==128);
 return 1;
}
