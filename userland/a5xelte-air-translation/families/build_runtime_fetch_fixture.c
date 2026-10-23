/* SPDX-License-Identifier: MIT
 * Physical ordered-fetch oracle. Real SPIR-V->NIR->Midgard code is supplied
 * privately; initial target/source pixels are deliberately not expected output.
 */
#define PAN_ARCH 4
#include "runtime_misc_encode.h"
#include "genxml/v4_pack.h"
#include "A5MaliCompiledRegistryData.inc"
#include "A5FetchFixtureData.inc"
#include <assert.h>
#include <stdio.h>
#include <string.h>
enum{BASE=0x02000000,SOURCE=0x3a000,NOISE=0x3b000,OUTPUT=0x3e000};
static unsigned vtx(uint8_t *v,unsigned index,float x,float y){
 const float pos[4]={x,y,0,1},uv[2]={0.5f,0.5f};
 memcpy(v+index*48,pos,16);memcpy(v+index*48+16,uv,8);return index+1;
}
static unsigned quad(uint8_t*v,unsigned index,float left,float right){
 index=vtx(v,index,left,0);index=vtx(v,index,right,0);index=vtx(v,index,left,32);
 index=vtx(v,index,left,32);index=vtx(v,index,right,0);return vtx(v,index,right,32);
}
int main(int argc,char**argv){
 assert(argc==3);int overlap=argv[2][0]=='1';
 const A5MaliCompiledProfile*old=NULL;
 for(unsigned i=0;i<sizeof(kA5MaliCompiledProfiles)/sizeof(kA5MaliCompiledProfiles[0]);i++)
  if(kA5MaliCompiledProfiles[i].profileID==603)old=kA5MaliCompiledProfiles+i;
 assert(old);
 A5MaliCompiledPass pass={.passID=A5MaliDynamicProfileID,.vertex=old->passes[0].vertex,
  .fragment={a5_fetch_code,sizeof(a5_fetch_code),A5_FETCH_TAG,A5_FETCH_REGS,0,0,A5_FETCH_SHA}};
 A5MaliCompiledResource resources[7]={
  {1,1,2,0,1,1,0,64,0,0},{1,1,3,1,2,1,0,16,0,4},
  {2,4,0,5,0,1,0,0,0,0},{2,2,3,7,0,1,0,0,0,0},{2,3,0,7,0,1,0,0,0,0}};
 A5MaliCompiledPushField pushes[]={{1,1,2,0,4,0},{1,1,3,4,4,0}};
 A5MaliCompiledProfile p=*old;p.profileID=A5MaliDynamicProfileID;
 p.flags=A5MaliProfileDynamicStages|A5MaliProfileSourceOverBlend|A5MaliProfileFramebufferFetch;
 p.passes=&pass;p.resources=resources;p.resourceCount=5;p.pushFields=pushes;p.pushFieldCount=2;
 #if A5_FETCH_NOISE
 A5MaliCompiledSampler sampler={1,0,0,0,1,1,1,1,0,0.25f};
 resources[5]=(A5MaliCompiledResource){2,2,9,8,1,1,0,0,0,0};
 resources[6]=(A5MaliCompiledResource){2,3,31,8,1,A5MaliResourceRead|A5MaliResourceImmutableSampler,0,0,0,0};
 p.resourceCount=7;p.immutableSamplers=&sampler;p.immutableSamplerCount=1;p.flags|=A5MaliProfileFragmentPosition;
#endif
 assert(A5MaliDynamicRuntimeProfileSupported(&p));
 uint8_t vertices[12*48]={0};unsigned count=0;
 if(overlap){count=quad(vertices,count,0,24);count=quad(vertices,count,8,32);}
 else count=quad(vertices,count,0,32);
 float matrix[16]={0};matrix[0]=2.f/32;matrix[5]=-2.f/32;matrix[10]=matrix[15]=1;
 matrix[12]=-1;matrix[13]=1;const float uv[4]={1,1,0,0};
 A5RuntimeMiscDraw m={0};m.draw.profile=&p;m.draw.descriptorGPUVA=BASE;
 m.draw.vertexCount=count;m.draw.primitive=A5RuntimeTriangle;
 m.draw.viewportWidth=m.draw.viewportHeight=32;m.draw.viewportFar=1;
 m.draw.scissorWidth=m.draw.scissorHeight=32;
 m.draw.vertexBuffers[1]=(A5RuntimeBuffer){0,count*48,0,vertices};
 m.draw.vertexBuffers[2]=(A5RuntimeBuffer){0,sizeof(matrix),0,(const uint8_t*)matrix};
 m.draw.vertexBuffers[3]=(A5RuntimeBuffer){0,sizeof(uv),0,(const uint8_t*)uv};
 m.colorAttachments[0]=(A5RuntimeImage){0x04000000,4096,32,32,128,80};
 m.fragmentTextures[3]=(A5RuntimeImage){0x03000000,4096,32,32,128,80};
 #if A5_FETCH_NOISE
 m.fragmentTextures[9]=(A5RuntimeImage){0x05000000,512,8,8,64,115};
#endif
 m.fragmentSamplers[0]=(A5RuntimeSampler){.valid=1,.normalizedCoordinates=1,.maxAnisotropy=1};
 static uint8_t d[A5RuntimeJobBytes];assert(!A5MaliEncodeRuntimeMiscPass(&m,d,sizeof(d)));
 pan_unpack((struct mali_renderer_state_packed*)(d+0x540),RENDERER_STATE,rs);
 assert(rs.shader.shader==BASE+0x8000+A5_FETCH_TAG&&rs.multisample_misc.load_destination);
 unsigned texture=A5_FETCH_NOISE?0x4020:0x620;
 pan_unpack((struct mali_surface_with_stride_packed*)(d+texture),SURFACE_WITH_STRIDE,tex);
 tex.pointer=BASE+SOURCE;MALI_SURFACE_WITH_STRIDE_pack((struct mali_surface_with_stride_packed*)(d+texture),&tex);
#if A5_FETCH_NOISE
 pan_unpack((struct mali_surface_with_stride_packed*)(d+0x4060),SURFACE_WITH_STRIDE,noise);
 noise.pointer=BASE+NOISE;MALI_SURFACE_WITH_STRIDE_pack((struct mali_surface_with_stride_packed*)(d+0x4060),&noise);
#endif
 pan_unpack((struct mali_framebuffer_parameters_packed*)(d+0x320),FRAMEBUFFER_PARAMETERS,fb);
 fb.color_writeback.base=BASE+OUTPUT;MALI_FRAMEBUFFER_PARAMETERS_pack((struct mali_framebuffer_parameters_packed*)(d+0x320),&fb);
 pan_unpack((struct mali_surface_with_stride_packed*)(d+0x19a0),SURFACE_WITH_STRIDE,pre);
 pre.pointer=BASE+OUTPUT;MALI_SURFACE_WITH_STRIDE_pack((struct mali_surface_with_stride_packed*)(d+0x19a0),&pre);
 const uint8_t source[]={64,96,128,160},dest[]={32,64,96,128};
 memset(d+0x39000,0xa7,0x1000);memset(d+SOURCE,0x5b,0x4000);memset(d+0x3f000,0xa7,0x1000);
 for(unsigned i=0;i<4096;i+=4){memcpy(d+SOURCE+i,source,4);memcpy(d+OUTPUT+i,dest,4);}
 #if A5_FETCH_NOISE
 const uint16_t eighths[]={0,0x3000,0x3400,0x3600,0x3800,0x3900,0x3a00,0x3b00};
 for(unsigned y=0;y<8;y++)for(unsigned x=0;x<8;x++){
  uint16_t rgba[]={eighths[x],eighths[y],eighths[(x+y)%8],0x3800};
  memcpy(d+NOISE+y*64+x*8,rgba,8);
 }
#endif
 FILE*f=fopen(argv[1],"wb");assert(f&&fwrite(d,1,sizeof(d),f)==sizeof(d)&&!fclose(f));
 return 0;
}
