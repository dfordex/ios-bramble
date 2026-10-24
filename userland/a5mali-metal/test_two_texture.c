/* SPDX-License-Identifier: MIT
 * Actual dual-UV stage descriptor checks and optional device pixel fixture.
 * Mock checks never claim GPU execution. Expected pixels remain outside jobs.
 */
#include "../a5xelte-air-translation/families/runtime_misc_encode.h"
#include "genxml/v4_pack.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static int zero(const uint8_t*p,size_t n){for(size_t i=0;i<n;i++)if(p[i])return 0;return 1;}
static void setup(A5RuntimeMiscDraw*m,const A5MaliCompiledProfile*p,uint8_t*v,float*matrix,float*uv,float*lod,unsigned blend){
 memset(m,0,sizeof(*m));m->draw.profile=p;m->draw.descriptorGPUVA=0x02000000;
 m->draw.vertexCount=6;m->draw.primitive=A5RuntimeTriangle;m->draw.blend=blend;
 m->draw.viewportWidth=m->draw.viewportHeight=32;m->draw.viewportFar=1;
 m->draw.scissorWidth=m->draw.scissorHeight=32;
 m->draw.vertexBuffers[1]=(A5RuntimeBuffer){0,288,0,v};
 m->draw.vertexBuffers[2]=(A5RuntimeBuffer){0,64,0,(uint8_t*)matrix};
 m->draw.vertexBuffers[3]=(A5RuntimeBuffer){0,32,0,(uint8_t*)uv};
 m->draw.fragmentBuffers[2]=(A5RuntimeBuffer){0,8,0,(uint8_t*)lod};
 m->colorAttachments[0]=(A5RuntimeImage){0x04000000,4096,32,32,128,80};
 m->fragmentTextures[3]=(A5RuntimeImage){0x05000000,4096,32,32,128,80};
 m->fragmentTextures[4]=(A5RuntimeImage){0x06000000,4096,32,32,128,80};
 for(unsigned i=0;i<2;i++)m->fragmentSamplers[i]=(A5RuntimeSampler){.valid=1,.minFilter=i,.magFilter=i,.normalizedCoordinates=1,.maxAnisotropy=1};
}
void A5MaliCheckTwoTextureNative(const uint8_t*d,uint64_t base);
void A5MaliCheckTwoTextureNative(const uint8_t*d,uint64_t base){
 struct MALI_RENDERER_STATE vs,fs;
 MALI_RENDERER_STATE_unpack((const struct mali_renderer_state_packed*)(d+0x500),&vs);
 MALI_RENDERER_STATE_unpack((const struct mali_renderer_state_packed*)(d+0x540),&fs);
 assert(vs.shader.attribute_count==4&&vs.shader.varying_count==5&&fs.shader.varying_count==3);
 assert(fs.shader.texture_count==2&&fs.shader.sampler_count==2&&fs.properties.uniform_buffer_count==5);
 struct MALI_DRAW draw;MALI_DRAW_unpack((const struct mali_draw_packed*)(d+0x140),&draw);
 assert(draw.textures==base+0x4100&&draw.samplers==base+0x4140);
 for(unsigned i=0;i<2;i++){
  struct MALI_SAMPLER sampler;MALI_SAMPLER_unpack((const struct mali_sampler_packed*)(d+0x4140+32*i),&sampler);
  assert(sampler.minify_nearest==!i&&sampler.magnify_nearest==!i&&sampler.normalized_coordinates);
 }
 for(unsigned i=0;i<3;i++){
  struct MALI_ATTRIBUTE_BUFFER buffer;MALI_ATTRIBUTE_BUFFER_unpack((const struct mali_attribute_buffer_packed*)(d+0xc80+16*i),&buffer);
  assert(buffer.pointer==base+0x32000+0x1000*i&&buffer.stride==(i==2?16:8));
 }
 struct MALI_ATTRIBUTE uv1,color;
 MALI_ATTRIBUTE_unpack((const struct mali_attribute_packed*)(d+0x810),&uv1);
 MALI_ATTRIBUTE_unpack((const struct mali_attribute_packed*)(d+0x818),&color);
 assert(uv1.offset>=24&&color.offset-uv1.offset==8);
}
int A5MaliTestTwoTextureProfile(const A5MaliCompiledProfile*p,unsigned blend);
int A5MaliTestTwoTextureProfile(const A5MaliCompiledProfile*p,unsigned blend){
 assert(A5MaliDynamicRuntimeProfileSupported(p)&&p->passes[0].vertex.byteCount==2592&&p->passes[0].fragment.byteCount==1328);
 assert((p->flags&(A5MaliProfileVertexTwoUV|A5MaliProfileFragmentTwoUV|A5MaliProfileDynamicColorVarying))==(A5MaliProfileVertexTwoUV|A5MaliProfileFragmentTwoUV|A5MaliProfileDynamicColorVarying));
 assert(!(p->flags&A5MaliProfileFramebufferFetch));
 uint8_t vertices[288]={0};float matrix[16]={0},uv[8]={0},lod[2]={.375f,.625f};
 A5RuntimeMiscDraw m;setup(&m,p,vertices,matrix,uv,lod,blend);
 uint8_t*d=malloc(A5RuntimeJobBytes);assert(d);
 assert(!A5MaliEncodeRuntimeMiscPass(&m,d,A5RuntimeJobBytes));A5MaliCheckTwoTextureNative(d,m.draw.descriptorGPUVA);
 assert(!memcmp(d+0x6000,p->passes[0].vertex.bytes,2592)&&!memcmp(d+0x8000,p->passes[0].fragment.bytes,1328));
 struct MALI_UNIFORM_BUFFER u;MALI_UNIFORM_BUFFER_unpack((const struct mali_uniform_buffer_packed*)(d+0x740+4*8),&u);
 assert(u.pointer>=m.draw.descriptorGPUVA+0x20000&&u.pointer-m.draw.descriptorGPUVA<A5RuntimeJobBytes-8);
 assert(!memcmp(d+(size_t)(u.pointer-m.draw.descriptorGPUVA),lod,8));
 m.fragmentTextures[4].bytes=4095;assert(A5MaliEncodeRuntimeMiscPass(&m,d,A5RuntimeJobBytes)&&zero(d,A5RuntimeJobBytes));m.fragmentTextures[4].bytes=4096;
 m.fragmentSamplers[1].normalizedCoordinates=0;assert(A5MaliEncodeRuntimeMiscPass(&m,d,A5RuntimeJobBytes)&&zero(d,A5RuntimeJobBytes));m.fragmentSamplers[1].normalizedCoordinates=1;
 m.draw.fragmentBuffers[2].bytes=7;assert(A5MaliEncodeRuntimeMiscPass(&m,d,A5RuntimeJobBytes)&&zero(d,A5RuntimeJobBytes));m.draw.fragmentBuffers[2].bytes=8;
 A5MaliCompiledProfile bad=*p;bad.flags&=~A5MaliProfileVertexTwoUV;m.draw.profile=&bad;
 assert(!A5MaliDynamicRuntimeProfileSupported(&bad)&&A5MaliEncodeRuntimeMiscPass(&m,d,A5RuntimeJobBytes)&&zero(d,A5RuntimeJobBytes));
 free(d);printf("PASS actual two-texture factory/emitter contracts blend=%u (no GPU execution)\n",blend);return 1;
}
int A5MaliWriteTwoTextureFixture(const A5MaliCompiledProfile*p,const char*path);
int A5MaliWriteTwoTextureFixture(const A5MaliCompiledProfile*p,const char*path){
 uint8_t vertices[288]={0};const float pos[6][2]={{0,0},{32,0},{0,32},{0,32},{32,0},{32,32}};
 const uint16_t color[]={0x3800,0x3400,0x3c00,0x3800};
 for(unsigned i=0;i<6;i++){
  float position[]={pos[i][0],pos[i][1],0,1},uv0[]={pos[i][0]/32-.25f/32,pos[i][1]/32+.25f/32},uv1[]={1-pos[i][0]/32+.5f/32,.5f};
  memcpy(vertices+48*i,position,16);memcpy(vertices+48*i+16,uv0,8);memcpy(vertices+48*i+24,uv1,8);memcpy(vertices+48*i+32,color,8);
 }
 float matrix[16]={0};matrix[0]=2.f/32;matrix[5]=-2.f/32;matrix[10]=matrix[15]=1;matrix[12]=-1;matrix[13]=1;
 float uv[]={1,1,0,0,1,1,0,0},lod[2]={0,0};A5RuntimeMiscDraw m;setup(&m,p,vertices,matrix,uv,lod,0);
 static uint8_t d[A5RuntimeJobBytes];assert(!A5MaliEncodeRuntimeMiscPass(&m,d,sizeof(d)));A5MaliCheckTwoTextureNative(d,m.draw.descriptorGPUVA);
 struct MALI_FRAMEBUFFER_PARAMETERS fb;MALI_FRAMEBUFFER_PARAMETERS_unpack((const struct mali_framebuffer_parameters_packed*)(d+0x320),&fb);fb.color_writeback.base=m.draw.descriptorGPUVA+0x3e000;MALI_FRAMEBUFFER_PARAMETERS_pack((struct mali_framebuffer_parameters_packed*)(d+0x320),&fb);
 struct MALI_SURFACE_WITH_STRIDE pre;MALI_SURFACE_WITH_STRIDE_unpack((const struct mali_surface_with_stride_packed*)(d+0x19a0),&pre);pre.pointer=m.draw.descriptorGPUVA+0x3e000;MALI_SURFACE_WITH_STRIDE_pack((struct mali_surface_with_stride_packed*)(d+0x19a0),&pre);
 for(unsigned i=0;i<2;i++){struct MALI_SURFACE_WITH_STRIDE image;unsigned at=0x4020+64*i;MALI_SURFACE_WITH_STRIDE_unpack((const struct mali_surface_with_stride_packed*)(d+at),&image);image.pointer=m.draw.descriptorGPUVA+0x3b000+4096*i;MALI_SURFACE_WITH_STRIDE_pack((struct mali_surface_with_stride_packed*)(d+at),&image);}
 memset(d+0x39000,0xa7,0x1000);memset(d+0x3d000,0xa7,0x1000);memset(d+0x3f000,0xa7,0x1000);
 for(unsigned y=0;y<32;y++)for(unsigned x=0;x<32;x++){
  uint8_t a[]={32+(x*23+y*9)%192,32+(x*7+y*19)%192,32+(x*x*11+y*5)%192,192};
  uint8_t b[]={201,37,113,(x*x*7+x*31+29)%256},initial[]={17,33,49,65};
  memcpy(d+0x3b000+128*y+4*x,a,4);memcpy(d+0x3c000+128*y+4*x,b,4);memcpy(d+0x3e000+128*y+4*x,initial,4);
 }
 FILE*f=fopen(path,"wb");assert(f&&fwrite(d,1,sizeof(d),f)==sizeof(d)&&!fclose(f));return 1;
}
