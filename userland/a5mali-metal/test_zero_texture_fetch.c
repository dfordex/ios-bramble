/* SPDX-License-Identifier: MIT
 * Real published zero-input fetch code and native descriptor contracts.
 * Synthetic addresses exercise the production emitter, not GPU pixels.
 */
#include "../a5xelte-air-translation/families/runtime_misc_encode.h"
#include "genxml/v4_pack.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static int zero(const uint8_t *p,size_t n){for(size_t i=0;i<n;i++)if(p[i])return 0;return 1;}
void A5MaliCheckZeroFetchNative(const uint8_t *jobs);
void A5MaliCheckZeroFetchNative(const uint8_t *jobs){
 struct MALI_DRAW draw;MALI_DRAW_unpack((const struct mali_draw_packed*)(jobs+0x140),&draw);
 assert(!draw.textures&&!draw.samplers&&!draw.varyings&&!draw.varying_buffers);
 struct MALI_RENDERER_STATE rs;MALI_RENDERER_STATE_unpack((const struct mali_renderer_state_packed*)(jobs+0x540),&rs);
 assert(!rs.shader.texture_count&&!rs.shader.sampler_count&&!rs.shader.varying_count&&rs.multisample_misc.load_destination);
}
int A5MaliTestZeroTextureFetch(const A5MaliCompiledProfile *p,int blend);
int A5MaliTestZeroTextureFetch(const A5MaliCompiledProfile *p,int blend){
 unsigned checks=0;
#define CHECK(x) do { assert(x);checks++; } while(0)
 CHECK(p&&A5MaliDynamicRuntimeProfileSupported(p));
 CHECK((p->flags&(A5MaliProfileFramebufferFetch|A5MaliProfileFragmentNoInputs))==
       (A5MaliProfileFramebufferFetch|A5MaliProfileFragmentNoInputs));
 CHECK(!(p->flags&(A5MaliProfileDynamicColorVarying|A5MaliProfileFragmentPosition)));
 CHECK(p->passes[0].fragment.byteCount==2448&&p->passes[0].fragment.firstTag==8);
 CHECK(!p->immutableSamplerCount);
 uint8_t vertices[288]={0},vs[31][4096]={{0}},fs[31][4096]={{0}};
 A5RuntimeMiscDraw m={0};m.draw.profile=p;m.draw.vertexCount=6;
 m.draw.primitive=A5RuntimeTriangle;m.draw.descriptorGPUVA=0x10000000;
 m.draw.blend=blend?A5RuntimeBlendPremultipliedSourceOver:A5RuntimeBlendCopy;
 m.draw.viewportWidth=m.draw.viewportHeight=32;m.draw.viewportFar=1;
 m.draw.scissorWidth=m.draw.scissorHeight=32;
 m.draw.vertexBuffers[1]=(A5RuntimeBuffer){0,sizeof(vertices),0,vertices};
 unsigned fragmentSlot=31;
 for(unsigned i=0;i<p->resourceCount;i++){
  const A5MaliCompiledResource *r=p->resources+i;
  CHECK(r->kind!=A5MaliResourceTexture&&r->kind!=A5MaliResourceSampler);
  if(r->kind!=A5MaliResourceBuffer)continue;
  CHECK(r->metalIndex<31&&r->uniformBytes<=4096);
  A5RuntimeBuffer b={0,4096,0,r->stage==1?vs[r->metalIndex]:fs[r->metalIndex]};
  (r->stage==1?m.draw.vertexBuffers:m.draw.fragmentBuffers)[r->metalIndex]=b;
  if(r->stage==2)fragmentSlot=r->metalIndex;
 }
 CHECK(fragmentSlot<31);
 m.colorAttachments[0]=(A5RuntimeImage){0x13000000,4096,32,32,128,80};
 uint8_t *d=malloc(A5RuntimeJobBytes);CHECK(d);
 CHECK(A5MaliEncodeRuntimeMiscPass(&m,d,A5RuntimeJobBytes)==A5RuntimeOK);
 CHECK(!memcmp(d+0x8000,p->passes[0].fragment.bytes,2448));
 struct MALI_RENDERER_STATE rs;MALI_RENDERER_STATE_unpack((const struct mali_renderer_state_packed*)(d+0x540),&rs);
 CHECK(rs.shader.shader==m.draw.descriptorGPUVA+0x8000+8);
 CHECK(!rs.shader.texture_count&&!rs.shader.sampler_count&&!rs.shader.varying_count);
 CHECK(rs.properties.uniform_buffer_count==3&&rs.properties.work_register_count==8&&rs.multisample_misc.load_destination);
 struct MALI_DRAW draw;MALI_DRAW_unpack((const struct mali_draw_packed*)(d+0x140),&draw);
 CHECK(!draw.textures&&!draw.samplers&&!draw.varyings&&!draw.varying_buffers);
 CHECK(zero(d+0xc00,0x100)&&zero(d+0x4000,0x200));
 struct MALI_RENDERER_STATE vertex;MALI_RENDERER_STATE_unpack((const struct mali_renderer_state_packed*)(d+0x500),&vertex);
 CHECK(vertex.shader.varying_count==((p->flags&A5MaliProfileVertexColorOnly)?3u:4u));
 CHECK(vertex.shader.attribute_count==((p->flags&A5MaliProfileVertexColorOnly)?2u:3u)); /* The actual QC VS exports are retained. */
 m.draw.fragmentBuffers[fragmentSlot].bytes=0;
 CHECK(A5MaliEncodeRuntimeMiscPass(&m,d,A5RuntimeJobBytes)!=A5RuntimeOK&&zero(d,A5RuntimeJobBytes));
 m.draw.fragmentBuffers[fragmentSlot].bytes=4096;
 m.colorAttachments[0].gpuVA=m.draw.descriptorGPUVA;
 CHECK(A5MaliEncodeRuntimeMiscPass(&m,d,A5RuntimeJobBytes)!=A5RuntimeOK&&zero(d,A5RuntimeJobBytes));
 m.colorAttachments[0].gpuVA=0x13000000;
 const unsigned invalidFlags[]={A5MaliProfileFramebufferFetch,A5MaliProfileFragmentNoInputs,
  A5MaliProfileDynamicColorVarying,A5MaliProfileFragmentPosition};
 for(unsigned i=0;i<4;i++){
  A5MaliCompiledProfile bad=*p;bad.flags^=invalidFlags[i];m.draw.profile=&bad;
  CHECK(!A5MaliDynamicRuntimeProfileSupported(&bad));
  CHECK(A5MaliEncodeRuntimeMiscPass(&m,d,A5RuntimeJobBytes)!=A5RuntimeOK&&zero(d,A5RuntimeJobBytes));
 }
 A5MaliCompiledProfile bad=*p;A5MaliCompiledResource resources[17];
 memcpy(resources,p->resources,p->resourceCount*sizeof(*resources));
 resources[p->resourceCount]=(A5MaliCompiledResource){2,A5MaliResourceTexture,3,7,0,A5MaliResourceRead,0,0,0,0};
 bad.resources=resources;bad.resourceCount++;m.draw.profile=&bad;
 CHECK(!A5MaliDynamicRuntimeProfileSupported(&bad));
 CHECK(A5MaliEncodeRuntimeMiscPass(&m,d,A5RuntimeJobBytes)!=A5RuntimeOK&&zero(d,A5RuntimeJobBytes));
 free(d);printf("PASS actual zero-texture fetch emitter: %u grouped checks blend=%d (no GPU execution)\n",checks,blend);return 1;
}
