/* SPDX-License-Identifier: MIT: actual private shader structural tests. */
#define PAN_ARCH 4
#include "runtime_path_encode.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "genxml/v4_pack.h"
#include "A5MaliCompiledRegistryData.inc"
static uint8_t out[A5RuntimeJobBytes],storage[4096];
static int zero(void){for(unsigned i=0;i<sizeof(out);++i)if(out[i])return 0;return 1;}
int main(void){unsigned cases=0;uint8_t mvp[64]={0},aux[24]={0};
 for(unsigned n=0;n<sizeof(kA5MaliCompiledProfiles)/sizeof(kA5MaliCompiledProfiles[0]);++n){
 const A5MaliCompiledProfile*p=&kA5MaliCompiledProfiles[n];if(p->profileID<300||p->profileID>302)continue;
 A5RuntimePathDraw m={0};m.draw.profile=p;m.draw.descriptorGPUVA=0x12000000;m.draw.viewportWidth=m.draw.viewportHeight=32;m.draw.viewportFar=1;m.draw.scissorWidth=m.draw.scissorHeight=32;m.draw.vertexCount=4;m.draw.primitive=A5RuntimeTriangleStrip;m.draw.blend=p->profileID==302?1:2;
 unsigned t=p->profileID==302?0:2,f=t?55:115;
 m.colorAttachments[t]=(A5RuntimeImage){0x21000000,8192,32,32,t?128:256,f};
 m.draw.vertexBuffers[1]=(A5RuntimeBuffer){0,sizeof(storage),0,storage};m.draw.vertexBuffers[2]=(A5RuntimeBuffer){0,64,0,mvp};m.draw.vertexBuffers[5]=(A5RuntimeBuffer){0,sizeof(aux),0,aux};
 int rc=A5MaliEncodeRuntimePathPass(&m,out,sizeof(out));if(rc)fprintf(stderr,"profile%u rc%d\n",p->profileID,rc);assert(!rc);
 assert(p->passCount==1&&p->passes[0].logicalTarget==t);
 assert(!memcmp(out+0x4000,p->passes[0].vertex.bytes,p->passes[0].vertex.byteCount));assert(!memcmp(out+0x6000,p->passes[0].fragment.bytes,p->passes[0].fragment.byteCount));
 pan_section_unpack(out+0x300,FRAMEBUFFER,PARAMETERS,fb);assert(fb.color_preload_enable&&fb.color_load_address==0x21000000&&fb.color_writeback.base==0x21000000);
 pan_unpack((struct mali_renderer_state_packed*)(out+0x540),RENDERER_STATE,rs);assert(rs.multisample_misc.load_destination&&!rs.properties.force_early_z);
 m.draw.viewportWidth=64;assert(!A5MaliEncodeRuntimePathPass(&m,out,sizeof(out)));float scale;memcpy(&scale,out+0x1000+512,4);assert(scale==32);
 m.draw.blend=0;assert(A5MaliEncodeRuntimePathPass(&m,out,sizeof(out))==A5RuntimeUnsupported&&zero());m.draw.blend=t?2:1;
 m.colorAttachments[t].gpuVA=0x12000000;assert(A5MaliEncodeRuntimePathPass(&m,out,sizeof(out))==A5RuntimeBounds&&zero());m.colorAttachments[t].gpuVA=0x21000000;
 m.draw.vertexBuffers[1]=(A5RuntimeBuffer){0x21000000,4096,0,NULL};assert(A5MaliEncodeRuntimePathPass(&m,out,sizeof(out))==A5RuntimeBounds&&zero());++cases;
 }assert(cases==3);puts("PASS3 actual path programs: single logical target, dynamic viewport, actual code, preload/add/sourceover state, buffer/target alias and wrong blend rejection; no GPU claim");return 0;}
