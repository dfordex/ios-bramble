/* SPDX-License-Identifier: MIT
 * Actual registry602 native pair, production emitter and nonzero destination.
 * Expected pixels are generated independently by the Python companion. */
#include "runtime_misc_encode.h"
#include "A5MaliCompiledRegistryData.inc"
#include "genxml/v4_pack.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
int main(int argc,char**argv){
 assert(argc==2);const A5MaliCompiledProfile*p=NULL;
 for(unsigned i=0;i<sizeof(kA5MaliCompiledProfiles)/sizeof(*kA5MaliCompiledProfiles);i++)
  if(kA5MaliCompiledProfiles[i].profileID==602)p=kA5MaliCompiledProfiles+i;
 assert(p&&p->flags==A5MaliProfileSourceOverBlend&&p->attachmentContractCount==2);
 assert(p->passes[0].vertex.byteCount==1808&&p->passes[0].fragment.byteCount==848);
 static uint8_t d[A5RuntimeJobBytes],v[12*48];
 const float xy[6][2]={{0,0},{1,0},{0,1},{0,1},{1,0},{1,1}};
 const uint16_t colors[2][4]={{0x3000,0x2c00,0x3200,0x3400},{0x3600,0x3200,0x3880,0x3a00}};
 for(unsigned q=0;q<2;q++)for(unsigned i=0;i<6;i++){
  float pos[]={16*(q+xy[i][0]),32*xy[i][1],0,1};
  memcpy(v+(q*6+i)*48,pos,sizeof(pos));memcpy(v+(q*6+i)*48+32,colors[q],8);
 }
 float matrix[16]={0};matrix[0]=2.f/32;matrix[5]=-2.f/32;
 matrix[10]=matrix[15]=1;matrix[12]=-1;matrix[13]=1;
 A5RuntimeMiscDraw m={0};m.draw.profile=p;m.draw.descriptorGPUVA=0x02000000;
 m.draw.vertexCount=12;m.draw.primitive=A5RuntimeTriangle;
 m.draw.viewportWidth=m.draw.viewportHeight=32;m.draw.viewportFar=1;
 m.draw.scissorX=m.draw.scissorY=4;m.draw.scissorWidth=m.draw.scissorHeight=24;
 m.draw.blend=A5RuntimeBlendPremultipliedSourceOver;
 m.draw.vertexBuffers[1]=(A5RuntimeBuffer){0,sizeof(v),0,v};
 m.draw.vertexBuffers[2]=(A5RuntimeBuffer){0,sizeof(matrix),0,(const uint8_t*)matrix};
 m.colorAttachments[0]=(A5RuntimeImage){0x04000000,4096,32,32,128,80};
 assert(A5MaliEncodeRuntimeMiscPass(&m,d,sizeof(d))==A5RuntimeOK);
 struct MALI_RENDERER_STATE rs;MALI_RENDERER_STATE_unpack((const struct mali_renderer_state_packed*)(d+0x540),&rs);
 assert(rs.multisample_misc.load_destination&&rs.blend_equation.rgb.invert_c&&rs.blend_equation.alpha.invert_c);
 struct MALI_FRAMEBUFFER_PARAMETERS fb;MALI_FRAMEBUFFER_PARAMETERS_unpack((const struct mali_framebuffer_parameters_packed*)(d+0x320),&fb);
 fb.color_writeback.base=m.draw.descriptorGPUVA+0x3e000;MALI_FRAMEBUFFER_PARAMETERS_pack((struct mali_framebuffer_parameters_packed*)(d+0x320),&fb);
 struct MALI_SURFACE_WITH_STRIDE pre;MALI_SURFACE_WITH_STRIDE_unpack((const struct mali_surface_with_stride_packed*)(d+0x19a0),&pre);
 pre.pointer=m.draw.descriptorGPUVA+0x3e000;MALI_SURFACE_WITH_STRIDE_pack((struct mali_surface_with_stride_packed*)(d+0x19a0),&pre);
 memset(d+0x39000,0xa7,0x5000);memset(d+0x3f000,0xa7,0x1000);
 const uint8_t initial[]={32,64,96,128};for(unsigned i=0;i<4096;i+=4)memcpy(d+0x3e000+i,initial,4);
 FILE*f=fopen(argv[1],"wb");assert(f&&fwrite(d,1,sizeof(d),f)==sizeof(d)&&!fclose(f));return 0;
}
