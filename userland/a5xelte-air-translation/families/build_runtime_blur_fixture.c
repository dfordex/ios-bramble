/* SPDX-License-Identifier: MIT
 * Actual runtime encoder/offscreen viewport GPU oracle. Private input shaders
 * and independently generated CPU reference pixels are provided by the recipe.
 */
#define PAN_ARCH 4
#include "runtime_encode.h"
#include "genxml/v4_pack.h"
#include "A5MaliCompiledRegistryData.inc"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
static unsigned char legacy[A5RuntimeJobBytes], out[A5RuntimeJobBytes];
int main(int argc,char**argv){
 if(argc!=3)return 2;FILE*f=fopen(argv[1],"rb");if(!f)return 2;
 if(fread(legacy,1,sizeof(legacy),f)!=sizeof(legacy)||fgetc(f)!=EOF)return 2;fclose(f);
 const A5MaliCompiledProfile*p=NULL;
 for(unsigned i=0;i<sizeof(kA5MaliCompiledProfiles)/sizeof(kA5MaliCompiledProfiles[0]);++i)
  if(kA5MaliCompiledProfiles[i].profileID==100)p=kA5MaliCompiledProfiles+i;
 if(!p||(p->flags&A5MaliProfileFixedViewport))return 2;
 float mvp[16]={0};mvp[0]=mvp[5]=2.f/32;mvp[10]=mvp[15]=1;mvp[12]=mvp[13]=-1;
 A5RuntimeDraw d={0};d.profile=p;d.descriptorGPUVA=0x02000000;
 d.source=(A5RuntimeImage){0x03000000,0x4000,64,64,256,80};
 d.destination=(A5RuntimeImage){0x04000000,0x1000,32,32,128,80};
 d.vertexBuffers[1]=(A5RuntimeBuffer){0,192,0,legacy+0xc00};
 d.vertexBuffers[2]=(A5RuntimeBuffer){0,64,0,(const uint8_t*)mvp};
 d.vertexBuffers[3]=(A5RuntimeBuffer){0,16,0,legacy+0xa40};
 d.fragmentBuffers[1]=(A5RuntimeBuffer){0,32,0,legacy+0xa80};
 d.fragmentBuffers[6]=(A5RuntimeBuffer){0,2,0,legacy+0xb00};
 d.viewportWidth=d.viewportHeight=32;d.viewportFar=1;
 d.scissorWidth=d.scissorHeight=32;d.vertexCount=4;d.primitive=A5RuntimeTriangleStrip;
 if(A5MaliEncodeRuntimeDraw(&d,out,sizeof(out)))return 2;
 /* Suite-only relocation into an unused tail of its one mapped test BO.
  * Production encoder correctly forbids image aliases of its descriptor BO. */
 pan_unpack((struct mali_surface_with_stride_packed*)(out+0x620),SURFACE_WITH_STRIDE,s);
 s.pointer=d.descriptorGPUVA+0x3a000;MALI_SURFACE_WITH_STRIDE_pack((struct mali_surface_with_stride_packed*)(out+0x620),&s);
 pan_unpack((struct mali_framebuffer_parameters_packed*)(out+0x320),FRAMEBUFFER_PARAMETERS,fb);
 fb.color_writeback.base=fb.color_load_address=d.descriptorGPUVA+0x3e000;
 MALI_FRAMEBUFFER_PARAMETERS_pack((struct mali_framebuffer_parameters_packed*)(out+0x320),&fb);
 memcpy(out+0x3a000,legacy+0xa000,0x4000);memset(out+0x3e000,0xcd,0x1000);memset(out+0x3f000,0xa7,0x1000);
 f=fopen(argv[2],"wb");if(!f)return 2;
 if(fwrite(out,1,sizeof(out),f)!=sizeof(out)||fclose(f))return 2;
 puts("Encoded genuine dynamic blur VS offscreen32x32, real runtime descriptors and caller ortho MVP; no GPU execution claim");return 0;
}
