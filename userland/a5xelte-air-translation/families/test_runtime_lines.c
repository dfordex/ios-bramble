/* SPDX-License-Identifier: MIT
 * Real private shader programs, released v4 packing and production emitter.
 * These are descriptor/bounds tests, never evidence of GPU execution. */
#include "runtime_misc_encode.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "A5MaliCompiledRegistryData.inc"
extern void A5MaliTestDynamicFormat43(const A5MaliCompiledProfile *,unsigned,unsigned);
static const A5MaliCompiledProfile *profile(unsigned id){
 for(unsigned i=0;i<sizeof(kA5MaliCompiledProfiles)/sizeof(kA5MaliCompiledProfiles[0]);i++)
  if(kA5MaliCompiledProfiles[i].profileID==id)return kA5MaliCompiledProfiles+i;
 assert(!"required real profile missing");return NULL;
}
static void input_arena_bounds(A5MaliCompiledProfile p){
 static uint8_t uniforms[2][31][4096],vertices[A5RuntimeMiscMaxVertices*68],jobs[A5RuntimeJobBytes];
 A5MaliCompiledVertexLayout layout=*p.layouts;p.layouts=&layout;
 A5RuntimeMiscDraw m={0};m.draw.profile=&p;m.draw.descriptorGPUVA=0x02000000;
 m.draw.vertexCount=1024;m.draw.primitive=A5RuntimeLine;
 m.draw.viewportWidth=m.draw.scissorWidth=32;m.draw.viewportHeight=m.draw.scissorHeight=32;
 m.draw.viewportFar=1;m.colorAttachments[0]=(A5RuntimeImage){0x04000000,4096,32,32,128,80};
 for(unsigned i=0;i<p.resourceCount;i++){
  const A5MaliCompiledResource*r=p.resources+i;
  if(r->kind==A5MaliResourceBuffer)(r->stage==1?m.draw.vertexBuffers:m.draw.fragmentBuffers)[r->metalIndex]=
   (A5RuntimeBuffer){0,r->uniformBytes,0,uniforms[r->stage-1][r->metalIndex]};
  else if(r->kind==A5MaliResourceTexture)m.fragmentTextures[r->metalIndex]=(A5RuntimeImage){0x06000000,4096,32,32,128,80};
  else if(r->kind==A5MaliResourceSampler)m.fragmentSamplers[r->metalIndex]=
   (A5RuntimeSampler){.valid=1,.normalizedCoordinates=1,.maxAnisotropy=1};
 }
 m.draw.vertexBuffers[1]=(A5RuntimeBuffer){0,sizeof(vertices),0,vertices};
 assert(layout.stride==48&&A5MaliEncodeRuntimeMiscPass(&m,jobs,sizeof(jobs))==A5RuntimeOK);
 m.draw.vertexCount=1600;
 assert(A5MaliRuntimeMiscInlineCapacity(1600)==0xc000);
 assert(A5MaliEncodeRuntimeMiscPass(&m,jobs,sizeof(jobs))==A5RuntimeBounds);
 for(unsigned i=0;i<sizeof(jobs);i++)assert(!jobs[i]);
 m.draw.vertexBuffers[1].cpuBytes=NULL;m.draw.vertexBuffers[1].gpuVA=0x08000000;
 assert(A5MaliEncodeRuntimeMiscPass(&m,jobs,sizeof(jobs))==A5RuntimeOK);
 m.draw.vertexBuffers[1].cpuBytes=vertices;m.draw.vertexBuffers[1].gpuVA=0;
 m.draw.vertexCount=1024;
 /* A larger legal interleaved stride does not make the 64KiB snapshot
  * arena grow into the GPU's output planes. Require the real upload route. */
 layout.stride=68;assert(A5MaliRuntimeVertexSpan(&p,1024)>0x10000);
 assert(A5MaliEncodeRuntimeMiscPass(&m,jobs,sizeof(jobs))==A5RuntimeBounds);
 for(unsigned i=0;i<sizeof(jobs);i++)assert(!jobs[i]);
 m.draw.vertexBuffers[1].cpuBytes=NULL;m.draw.vertexBuffers[1].gpuVA=0x08000000;
 assert(A5MaliEncodeRuntimeMiscPass(&m,jobs,sizeof(jobs))==A5RuntimeOK);
}
int main(void){
 unsigned cases=0;
 for(unsigned id=602;id<=606;id++){
  const A5MaliCompiledProfile*p=profile(id);
  assert(A5MaliRuntimeMiscVertexLimit(p)==1600);
  A5MaliTestDynamicFormat43(p,80,0);cases++;
 }
 /* The same genuinely compiled UV shader pair also exercises the dynamic
  * resource route: no fake native program bytes or replacement output. */
 A5MaliCompiledProfile dynamic=*profile(603);
 A5MaliCompiledPass pass=*dynamic.passes;
 pass.passID=dynamic.profileID=A5MaliDynamicProfileID;
 dynamic.passes=&pass;dynamic.flags|=A5MaliProfileDynamicStages;
 assert(A5MaliDynamicRuntimeProfileSupported(&dynamic));
 A5MaliTestDynamicFormat43(&dynamic,80,0);cases++;
 input_arena_bounds(dynamic);
 /* The older emitters' buffers have not changed capacity. */
 assert(A5RuntimeMaxVertices==256);
 for(unsigned id=99;id<=108;id++)assert(A5MaliRuntimeMiscVertexLimit(profile(id))==256);
 assert(A5MaliRuntimeMiscVertexLimit(profile(206))==256);
 puts("PASS 6 real static/dynamic shader pairs: lines/line-strip/triangles, 2..1600 native vertices, nonoverlapping output planes and rejection/zeroing; old blur/home bound256 (no GPU execution)");
 assert(cases==6);return 0;
}
