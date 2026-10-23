/* SPDX-License-Identifier: MIT
 * Actual stock zero-texture ordered-fetch fixture. The private fragment's
 * optimized dataflow is a 3x4 half matrix of current target RGBA, alpha kept.
 * The target starts nonzero; CPU code never fills it with expected output.
 */
#define PAN_ARCH 4
#include "runtime_misc_encode.h"
#include "genxml/v4_pack.h"
#include "A5MaliCompiledRegistryData.inc"
#include "A5ZeroFetchFixtureData.inc"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
enum { BASE=0x02000000, OUTPUT=0x3e000 };
static unsigned vertex(uint8_t*v,unsigned n,float x,float y){
 const float position[]={x,y,0,1};memcpy(v+n*48,position,16);return n+1;
}
static unsigned quad(uint8_t*v,unsigned n,float left,float right){
 n=vertex(v,n,left,0);n=vertex(v,n,right,0);n=vertex(v,n,left,32);
 n=vertex(v,n,left,32);n=vertex(v,n,right,0);return vertex(v,n,right,32);
}
int main(int argc,char**argv){
 assert(argc==3||argc==4);unsigned overlapping=argv[2][0]=='1';
 unsigned vertexProfile=argc==4?(unsigned)strtoul(argv[3],NULL,10):603;assert(vertexProfile==602||vertexProfile==603);
 const A5MaliCompiledProfile*old=NULL;
 for(unsigned i=0;i<sizeof(kA5MaliCompiledProfiles)/sizeof(kA5MaliCompiledProfiles[0]);i++)
  if(kA5MaliCompiledProfiles[i].profileID==vertexProfile)old=kA5MaliCompiledProfiles+i;
 assert(old);
 A5MaliCompiledPass pass={.passID=A5MaliDynamicProfileID,.vertex=old->passes[0].vertex,
  .fragment={a5_zero_fetch_code,sizeof(a5_zero_fetch_code),A5_ZERO_FETCH_TAG,A5_ZERO_FETCH_REGS,0,0,A5_ZERO_FETCH_SHA}};
 A5MaliCompiledResource resources[4];A5MaliCompiledPushField pushes[4];
 unsigned resourceCount=0,pushCount=0;
 for(unsigned i=0;i<old->resourceCount;i++)if(old->resources[i].stage==1)resources[resourceCount++]=old->resources[i];
 for(unsigned i=0;i<old->pushFieldCount;i++)if(old->pushFields[i].stage==1)pushes[pushCount++]=old->pushFields[i];
 resources[resourceCount++]=(A5MaliCompiledResource){2,1,1,1,2,1,0,168,0,64};
 resources[resourceCount++]=(A5MaliCompiledResource){2,4,0,3,0,1,0,0,0,0};
 pushes[pushCount++]=(A5MaliCompiledPushField){2,1,1,64,4,0};
 pushes[pushCount++]=(A5MaliCompiledPushField){2,2,0,68,4,0x2222};
 A5MaliCompiledProfile p=*old;p.profileID=A5MaliDynamicProfileID;
 p.flags=A5MaliProfileDynamicStages|A5MaliProfileSourceOverBlend|
  A5MaliProfileFramebufferFetch|A5MaliProfileFragmentNoInputs|
  (vertexProfile==602?A5MaliProfileVertexColorOnly:0);
 p.passes=&pass;p.resources=resources;p.resourceCount=resourceCount;p.pushFields=pushes;p.pushFieldCount=pushCount;
 A5MaliCompiledAttachmentContract contracts[2];
 for(unsigned c=0;c<2;c++)for(unsigned a=0;a<8;a++){
  unsigned over=c==1&&a==0;
  contracts[c].attachments[a]=(A5MaliCompiledAttachmentState){15,over,0,0,1,over?5u:0u,1,over?5u:0u};
 }
 p.attachmentContracts=contracts;p.attachmentContractCount=2;
 p.immutableSamplers=NULL;p.immutableSamplerCount=0;
 assert(A5MaliDynamicRuntimeProfileSupported(&p));
 uint8_t vertices[12*48]={0};unsigned count=0;
 if(overlapping){count=quad(vertices,count,0,24);count=quad(vertices,count,8,32);}
 else count=quad(vertices,count,0,32);
 float matrix[16]={0};matrix[0]=2.f/32;matrix[5]=-2.f/32;matrix[10]=matrix[15]=1;
 matrix[12]=-1;matrix[13]=1;const float uv[]={1,1,0,0};
 uint8_t fragment[168]={0};const uint16_t swap[]={0,0,0x3c00,0,0x3c00,0,0x3c00,0,0,0,0,0};
 memcpy(fragment+128,swap,sizeof(swap));
 A5RuntimeMiscDraw m={0};m.draw.profile=&p;m.draw.descriptorGPUVA=BASE;
 m.draw.vertexCount=count;m.draw.primitive=A5RuntimeTriangle;
 m.draw.viewportWidth=m.draw.viewportHeight=32;m.draw.viewportFar=1;
 m.draw.scissorWidth=m.draw.scissorHeight=32;
 m.draw.vertexBuffers[1]=(A5RuntimeBuffer){0,count*48,0,vertices};
 m.draw.vertexBuffers[2]=(A5RuntimeBuffer){0,sizeof(matrix),0,(const uint8_t*)matrix};
 m.draw.vertexBuffers[3]=(A5RuntimeBuffer){0,sizeof(uv),0,(const uint8_t*)uv};
 m.draw.fragmentBuffers[1]=(A5RuntimeBuffer){0,sizeof(fragment),0,fragment};
 m.colorAttachments[0]=(A5RuntimeImage){0x04000000,4096,32,32,128,80};
 static uint8_t d[A5RuntimeJobBytes];assert(!A5MaliEncodeRuntimeMiscPass(&m,d,sizeof(d)));
 pan_unpack((struct mali_renderer_state_packed*)(d+0x540),RENDERER_STATE,rs);
 assert(rs.shader.shader==BASE+0x8000+A5_ZERO_FETCH_TAG&&rs.multisample_misc.load_destination);
 assert(!rs.shader.texture_count&&!rs.shader.sampler_count&&!rs.shader.varying_count);
 pan_unpack((struct mali_draw_packed*)(d+0x140),DRAW,draw);
 assert(!draw.textures&&!draw.samplers&&!draw.varyings&&!draw.varying_buffers);
 pan_unpack((struct mali_framebuffer_parameters_packed*)(d+0x320),FRAMEBUFFER_PARAMETERS,fb);
 fb.color_writeback.base=BASE+OUTPUT;
 MALI_FRAMEBUFFER_PARAMETERS_pack((struct mali_framebuffer_parameters_packed*)(d+0x320),&fb);
 pan_unpack((struct mali_surface_with_stride_packed*)(d+0x19a0),SURFACE_WITH_STRIDE,pre);
 pre.pointer=BASE+OUTPUT;
 MALI_SURFACE_WITH_STRIDE_pack((struct mali_surface_with_stride_packed*)(d+0x19a0),&pre);
 memset(d+0x39000,0xa7,0x5000);memset(d+0x3f000,0xa7,0x1000);
 const uint8_t initial[]={32,64,96,128};
 for(unsigned i=0;i<4096;i+=4)memcpy(d+OUTPUT+i,initial,4);
 FILE*f=fopen(argv[1],"wb");assert(f&&fwrite(d,1,sizeof(d),f)==sizeof(d)&&!fclose(f));return 0;
}
