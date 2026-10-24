/* SPDX-License-Identifier: MIT
 * Production DS4 runtime descriptor input. No oracle/output pixels enter here.
 * Private compiled code comes only from the authenticated external registry.
 */
#define PAN_ARCH 4
#include "runtime_encode.h"
#include "genxml/v4_pack.h"
#include "A5MaliCompiledRegistryData.inc"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static uint8_t out[A5RuntimeJobBytes];
int main(int argc,char **argv){
 if(argc!=3)return 2;
 unsigned width=(unsigned)strtoul(argv[2],NULL,10)/8;
 if(width!=2&&width!=4)return 2;
 const A5MaliCompiledProfile *p=NULL;
 for(unsigned i=0;i<sizeof(kA5MaliCompiledProfiles)/sizeof(*kA5MaliCompiledProfiles);++i)
  if(kA5MaliCompiledProfiles[i].profileID==99)p=kA5MaliCompiledProfiles+i;
 if(!p||(p->flags&A5MaliProfileFixedViewport)||p->passes[0].fragment.byteCount!=3472)return 2;
 A5RuntimeDraw d={0};d.profile=p;d.descriptorGPUVA=0x02000000;
 d.source=(A5RuntimeImage){0x03000000,0x4000,64,64,256,80};
 d.destination=(A5RuntimeImage){0x04000000,0x1000,32,32,128,80};
 float mvp[16]={0};mvp[0]=mvp[5]=2.f/32;mvp[10]=mvp[15]=1;mvp[12]=mvp[13]=-1;
 float texmat[4]={1.f/64,1.f/64,0,0},vertices[4][12]={{0}};
 for(unsigned i=0;i<4;++i){
  vertices[i][0]=(i&1)?32:0;vertices[i][1]=(i&2)?32:0;vertices[i][3]=1;
  vertices[i][4]=(i&1)?62.25f:-1.75f;vertices[i][5]=(i&2)?64.25f:.25f;
 }
 uint8_t filter[72]={0};
 const float offsets[8]={-.5f/64,-.5f/64,.5f/64,-.5f/64,-.5f/64,.5f/64,.5f/64,.5f/64};
 const uint16_t weights[4]={0x3000,0x3000,0x3400,0x3800},edr=0x3800;
 memcpy(filter,offsets,sizeof(offsets));memcpy(filter+64,weights,sizeof(weights));
 d.vertexBuffers[1]=(A5RuntimeBuffer){0,sizeof(vertices),0,(uint8_t*)vertices};
 d.vertexBuffers[2]=(A5RuntimeBuffer){0,sizeof(mvp),0,(uint8_t*)mvp};
 d.vertexBuffers[3]=(A5RuntimeBuffer){0,sizeof(texmat),0,(uint8_t*)texmat};
 d.fragmentBuffers[1]=(A5RuntimeBuffer){0,sizeof(filter),0,filter};
 d.fragmentBuffers[6]=(A5RuntimeBuffer){0,sizeof(edr),0,(const uint8_t*)&edr};
 d.sourceSampler=(A5RuntimeBlurSampler){.valid=1,.minFilter=1,.magFilter=1,
  .normalizedCoordinates=1,.maxAnisotropy=1};
 d.viewportWidth=d.viewportHeight=32;d.viewportFar=1;d.scissorWidth=d.scissorHeight=32;
 d.vertexCount=4;d.primitive=A5RuntimeTriangle;d.indexCount=6;d.indexSize=width;
 uint8_t indices[24]={0};const uint32_t sequence[6]={2,0,1,2,1,3};
 for(unsigned i=0;i<6;++i)memcpy(indices+i*width,sequence+i,width);
 d.indexBuffer=(A5RuntimeBuffer){0,6*width,0,indices};
 if(A5MaliEncodeRuntimeDraw(&d,out,sizeof(out)))return 2;
 assert(!memcmp(out+0x4000,p->passes[0].fragment.bytes,p->passes[0].fragment.byteCount));
 pan_unpack((struct mali_sampler_packed*)(out+0x680),SAMPLER,sampler);
 assert(!sampler.minify_nearest&&!sampler.magnify_nearest&&sampler.normalized_coordinates);
 /* Only fixture relocation: production forbids images inside descriptor BO. */
 pan_unpack((struct mali_primitive_packed*)(out+0x128),PRIMITIVE,primitive);
 assert(primitive.indices==d.descriptorGPUVA+0x3a000);
 memcpy(out+0x39c00,out+0x3a000,6*width);primitive.indices=d.descriptorGPUVA+0x39c00;
 MALI_PRIMITIVE_pack((struct mali_primitive_packed*)(out+0x128),&primitive);
 pan_unpack((struct mali_surface_with_stride_packed*)(out+0x620),SURFACE_WITH_STRIDE,source);
 source.pointer=d.descriptorGPUVA+0x3a000;
 MALI_SURFACE_WITH_STRIDE_pack((struct mali_surface_with_stride_packed*)(out+0x620),&source);
 pan_unpack((struct mali_framebuffer_parameters_packed*)(out+0x320),FRAMEBUFFER_PARAMETERS,fb);
 fb.color_writeback.base=d.descriptorGPUVA+0x3e000;
 MALI_FRAMEBUFFER_PARAMETERS_pack((struct mali_framebuffer_parameters_packed*)(out+0x320),&fb);
 for(unsigned y=0;y<64;++y)for(unsigned x=0;x<64;++x){
  unsigned at=0x3a000+(y*64+x)*4,blue=(x/7)&1,green=(y/7)&1;
  out[at]=255*blue;out[at+1]=255*green;out[at+2]=255*(blue^green);out[at+3]=255;
 }
 memset(out+0x3e000,0xcd,0x1000);memset(out+0x3f000,0xa7,0x1000);
 FILE *f=fopen(argv[1],"wb");if(!f)return 2;
 if(fwrite(out,1,sizeof(out),f)!=sizeof(out)||fclose(f))return 2;
 puts("Prepared unchanged genuine DS4 four-weight linear indexed runtime job; physical pixels pending");return 0;
}
