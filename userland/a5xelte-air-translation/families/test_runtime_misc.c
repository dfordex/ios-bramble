/* SPDX-License-Identifier: MIT
 * Uses real caller-supplied compiled programs and device-passed payload inputs.
 * This tests descriptor/binding equivalence, not on-device execution.
 */
#define PAN_ARCH 4
#include "runtime_misc_encode.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "genxml/v4_pack.h"
#include "A5MaliCompiledRegistryData.inc"
static uint8_t out[A5RuntimeJobBytes],legacy[A5RuntimeJobBytes];
static unsigned bytes(unsigned f){return f==115?8:f==10?1:f==30?2:4;}
static int zero(void){for(unsigned i=0;i<sizeof(out);++i)if(out[i])return 0;return 1;}
int main(int argc,char**argv){
 unsigned cases=0;
 for(unsigned pi=0;pi<sizeof(kA5MaliCompiledProfiles)/sizeof(kA5MaliCompiledProfiles[0]);++pi){
  const A5MaliCompiledProfile*p=kA5MaliCompiledProfiles+pi;if(p->profileID<200||p->profileID>208)continue;
  int home=p->profileID==206,clear=p->profileID==207;
  for(unsigned pass=0;pass<p->passCount;++pass){
   char name[128];snprintf(name,sizeof(name),"%s_rt%u",p->name,p->passes[pass].logicalTarget);
   const char*path=NULL;for(int i=1;i+1<argc;i+=2)if(!strcmp(argv[i],name))path=argv[i+1];assert(path);
   FILE*f=fopen(path,"rb");assert(f);assert(fread(legacy,1,sizeof(legacy),f)==sizeof(legacy)&&fgetc(f)==EOF);fclose(f);
   A5RuntimeMiscDraw m={0};m.draw.profile=p;m.draw.descriptorGPUVA=0x12000000;m.passIndex=pass;
   m.draw.viewportWidth=m.draw.viewportHeight=32;m.draw.viewportFar=1;m.draw.vertexCount=4;
   m.draw.primitive=A5RuntimeTriangleStrip;m.draw.scissorWidth=m.draw.scissorHeight=32;
   for(unsigned i=0;i<p->passCount;++i){unsigned t=p->passes[i].logicalTarget;
    m.colorAttachments[t]=(A5RuntimeImage){0x21000000+(uint64_t)t*0x1000000,0x800000,32,32,32*bytes(p->colorFormats[t]),p->colorFormats[t]};
   }
   m.draw.vertexBuffers[1]=(A5RuntimeBuffer){0,home?192u:clear?16u:24u,0,legacy+(home?0x3000:0x2000)};
   m.draw.vertexBuffers[2]=(A5RuntimeBuffer){0,64,0,legacy+0x1800};
   m.draw.vertexBuffers[3]=(A5RuntimeBuffer){0,16,0,legacy+0x1900};
   m.draw.fragmentBuffers[1]=(A5RuntimeBuffer){0,home?12u:8u,0,legacy+0x1a00};
   m.draw.fragmentBuffers[9]=(A5RuntimeBuffer){0,1024,0,legacy+0x20000};
   m.fragmentTextures[3]=(A5RuntimeImage){0x24000000,0x800000,32,32,128,80};
   m.fragmentTextures[4]=(A5RuntimeImage){0x25000000,4096,2,1,16,80};
   int rc=A5MaliEncodeRuntimeMiscPass(&m,out,sizeof(out));if(rc){fprintf(stderr,"%s rc%d\n",name,rc);return 1;}
   assert(!memcmp(out+0x6000,legacy+0x6000,p->passes[pass].vertex.byteCount));
   assert(!memcmp(out+0x8000,legacy+0x8000,p->passes[pass].fragment.byteCount));
   pan_unpack((struct mali_renderer_state_packed*)(out+0x500),RENDERER_STATE,vs);
   pan_unpack((struct mali_renderer_state_packed*)(legacy+0x500),RENDERER_STATE,oldvs);
   pan_unpack((struct mali_renderer_state_packed*)(out+0x540),RENDERER_STATE,fs);
   pan_unpack((struct mali_renderer_state_packed*)(legacy+0x540),RENDERER_STATE,oldfs);
   assert(vs.shader.attribute_count==oldvs.shader.attribute_count&&vs.shader.varying_count==oldvs.shader.varying_count);
   assert(fs.shader.varying_count==oldfs.shader.varying_count&&fs.shader.texture_count==oldfs.shader.texture_count);
   if(!home){
    pan_unpack((struct mali_attribute_packed*)(out+0x800+17*8),ATTRIBUTE,inst);
    assert(inst.buffer_index==2);
    uint64_t storage;memcpy(&storage,out+0x1000+96,8);
    assert(storage>=m.draw.descriptorGPUVA+0x20000&&storage<m.draw.descriptorGPUVA+0x30000);
    assert(!memcmp(out+storage-m.draw.descriptorGPUVA,legacy+0x2000,clear?16:24));
   }
   m.draw.viewportWidth=64;assert(A5MaliEncodeRuntimeMiscPass(&m,out,sizeof(out))==A5RuntimeOK);
   float scale;memcpy(&scale,out+0x1000+512,4);assert(scale==32);
   m.draw.vertexCount=256;if(home)m.draw.vertexBuffers[1].bytes=256*48;assert(A5MaliEncodeRuntimeMiscPass(&m,out,sizeof(out))==A5RuntimeOK);
   m.draw.vertexCount=4;if(home)m.draw.vertexBuffers[1].bytes=192;
   if(!home&&!clear){
    m.draw.fragmentBuffers[9].bytes=0x20000;
    assert(A5MaliEncodeRuntimeMiscPass(&m,out,sizeof(out))==A5RuntimeBounds&&zero());
    m.draw.fragmentBuffers[9]=(A5RuntimeBuffer){0x26000000,0x20000,0,NULL};
    assert(A5MaliEncodeRuntimeMiscPass(&m,out,sizeof(out))==A5RuntimeOK);
    uint64_t address;memcpy(&address,out+0x1400+144,8);assert(address==0x26000000);
   }
   if(p->flags&A5MaliProfileSourceOverBlend){
    m.draw.blend=A5RuntimeBlendPremultipliedSourceOver;
    assert(A5MaliEncodeRuntimeMiscPass(&m,out,sizeof(out))==A5RuntimeOK);
    pan_unpack((struct mali_renderer_state_packed*)(out+0x540),RENDERER_STATE,blend);
    assert(blend.multisample_misc.load_destination&&blend.blend_equation.rgb.b==MALI_BLEND_OPERAND_B_DEST&&blend.blend_equation.rgb.invert_c);
    m.draw.blend=A5RuntimeBlendCopy;
   }
   if(home){m.fragmentTextures[4].gpuVA=0;assert(A5MaliEncodeRuntimeMiscPass(&m,out,sizeof(out))==A5RuntimeUnsupported&&zero());}
   else{m.colorAttachments[1]=m.colorAttachments[0];assert(A5MaliEncodeRuntimeMiscPass(&m,out,sizeof(out))!=A5RuntimeOK&&zero());}
   ++cases;
  }
 }
 assert(cases==9);printf("PASS %u actual misc passes: unchanged shader/varying ABI, real buffer snapshots/SSBO VA, dynamic viewport, two textures, large-SSBO GPU upload requirement and alias rejection (no GPU claim)\n",cases);
 return 0;
}
