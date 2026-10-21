/* SPDX-License-Identifier: MIT
 * Actual runtime-generated RAW204 source-over + textured-preload GPU oracle.
 */
#define PAN_ARCH 4
#include "runtime_misc_encode.h"
#include "genxml/v4_pack.h"
#include "runtime_preload.h"
#include "A5MaliCompiledRegistryData.inc"
#include <stdio.h>
#include <string.h>
static uint8_t old[A5RuntimeJobBytes],d[A5RuntimeJobBytes];
int main(int argc,char**argv){
 int r8=argc==4;int rg8=r8&&!strcmp(argv[3],"rg8");if(argc!=3&&argc!=4)return 2;FILE*f=fopen(argv[1],"rb");if(!f)return 2;
 if(fread(old,1,sizeof(old),f)!=sizeof(old)||fgetc(f)!=EOF)return 2;fclose(f);
 const A5MaliCompiledProfile*p=NULL;for(unsigned i=0;i<sizeof(kA5MaliCompiledProfiles)/sizeof(kA5MaliCompiledProfiles[0]);++i)if(kA5MaliCompiledProfiles[i].profileID==(r8?202u:204u))p=kA5MaliCompiledProfiles+i;
 if(!p||(!r8&&!(p->flags&A5MaliProfileInlineSourceOver))||p->passCount!=1)return 2;
 uint16_t src[4]={0x3000,0x3400,0x3600,0x3800};
 if(r8){src[0]=0x3400;src[1]=0x3800;src[2]=0x3a00;src[3]=0x3c00;} /* .125,.25,.375,.5 */
 A5RuntimeMiscDraw m={0};m.draw.profile=p;m.draw.descriptorGPUVA=0x02000000;
 m.colorAttachments[0]=(A5RuntimeImage){0x03000000,8192,32,32,r8?32u:256u,r8?10u:115u};
 m.draw.viewportWidth=m.draw.viewportHeight=32;m.draw.viewportFar=1;m.draw.scissorWidth=m.draw.scissorHeight=32;m.draw.vertexCount=4;m.draw.primitive=A5RuntimeTriangleStrip;m.draw.blend=A5RuntimeBlendPremultipliedSourceOver;
 m.draw.vertexBuffers[1]=(A5RuntimeBuffer){0,24,0,old+0x2000};m.draw.vertexBuffers[2]=(A5RuntimeBuffer){0,64,0,old+0x1800};
 m.draw.fragmentBuffers[1]=(A5RuntimeBuffer){0,8,0,(const uint8_t*)src};m.draw.fragmentBuffers[9]=(A5RuntimeBuffer){0,1024,0,old+0x20000};
 if(r8){m.draw.scissorX=m.draw.scissorY=8;m.draw.scissorWidth=m.draw.scissorHeight=16;}
 if(A5MaliEncodeRuntimeMiscPass(&m,d,sizeof(d)))return 2;
 if(rg8){
  A5RuntimeImage im={0x03000000,8192,32,32,64,30};
  if(a5_runtime_preload(d,m.draw.descriptorGPUVA,&im))return 2;
  /* Standalone physical RG8 preload copy, NOT a fabricated Metal profile.
   * Disable the unrelated application draw's colour writes. */
  pan_unpack((const struct mali_renderer_state_packed*)(d+0x540),RENDERER_STATE,rs);
  rs.stencil_mask_misc.write_enable=false;rs.blend_equation.color_mask=0;
  MALI_RENDERER_STATE_pack((struct mali_renderer_state_packed*)(d+0x540),&rs);
 }
 pan_unpack((const struct mali_framebuffer_parameters_packed*)(d+0x320),FRAMEBUFFER_PARAMETERS,fb);
 fb.color_writeback.base=0x0203c000;
 if(rg8){fb.internal_format=MALI_COLOR_BUFFER_INTERNAL_FORMAT_R8G8B8A8;fb.color_writeback_format=MALI_COLOR_FORMAT_R8G8;fb.color_writeback.row_stride=64;fb.swizzle=0x688;}fb.clear_color_0=fb.clear_color_1=fb.clear_color_2=fb.clear_color_3=0;
 MALI_FRAMEBUFFER_PARAMETERS_pack((struct mali_framebuffer_parameters_packed*)(d+0x320),&fb);
 pan_unpack((const struct mali_surface_with_stride_packed*)(d+0x19a0),SURFACE_WITH_STRIDE,pre);pre.pointer=rg8?0x0203b000:0x0203c000;
 MALI_SURFACE_WITH_STRIDE_pack((struct mali_surface_with_stride_packed*)(d+0x19a0),&pre);
 const uint16_t dst[4]={0x3400,0x3000,0x3800,0x3800}; /* .25,.125,.5,.5 */
 if(r8)memset(d+0x3c000,rg8?0xcd:192,8192);
 else for(unsigned i=0;i<1024;++i)memcpy(d+0x3c000+i*8,dst,8);
 if(rg8)for(unsigned y=0;y<32;++y)for(unsigned x=0;x<32;++x){d[0x3b000+(y*32+x)*2]=(x*7+y*3)&255;d[0x3b001+(y*32+x)*2]=(x*11+y*17)&255;}
 memset(d+0x3e000,0xa7,0x2000);f=fopen(argv[2],"wb");if(!f)return 2;
 int ok=fwrite(d,1,sizeof(d),f)==sizeof(d)&&!fclose(f);return !ok;
}
