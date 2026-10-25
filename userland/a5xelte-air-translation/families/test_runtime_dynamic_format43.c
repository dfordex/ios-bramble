/* SPDX-License-Identifier: MIT
 * Descriptor/bounds half of test_dynamic_format43.m, using released v4 structs.
 */
#define PAN_ARCH 4
#include "runtime_misc_encode.h"
#include "test_runtime_preload.h"
#include "../../a5mali-metal/A5MaliRenderState.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
void A5MaliTestDynamicFormat43(const A5MaliCompiledProfile *,unsigned,unsigned);
void A5MaliCheckPackedVertexUpload(const uint8_t *,const uint8_t *,unsigned,uint32_t);
static void check_lines_and_large_vertices(A5RuntimeMiscDraw original){
 static uint8_t jobs[A5RuntimeJobBytes];
 static const unsigned counts[]={2,164,176,186,196,256,257,312,330,1023,1024,1204,1279,1280,1281,1535,1536,1599,1600};
 const A5MaliCompiledProfile*p=original.draw.profile;
 unsigned limit=A5MaliRuntimeMiscVertexLimit(p);assert(limit==1600);
 for(unsigned topology=0;topology<4;topology++)for(unsigned ci=0;ci<sizeof(counts)/sizeof(counts[0]);ci++){
  unsigned count=counts[ci];if(count>limit)continue;
  unsigned primitive=topology==0?A5RuntimeLine:topology==1?A5RuntimeLineStrip:
   topology==2?A5RuntimeTriangle:A5RuntimeTriangleStrip;
  if((topology==0&&count%2)||(topology==2&&(count<3||count%3))||(topology==3&&count<3))continue;
  A5RuntimeMiscDraw m=original;m.draw.vertexCount=count;m.draw.primitive=primitive;
  unsigned span=A5MaliRuntimeVertexSpan(p,count);assert(span);
  /* Real mapped external input also covers layouts whose 1024 records
   * exceed the descriptor's input snapshot arena. Output planes stay local. */
  m.draw.vertexBuffers[1]=(A5RuntimeBuffer){0x08000000,span,0,NULL};
  assert(A5MaliEncodeRuntimeMiscPass(&m,jobs,sizeof(jobs))==A5RuntimeOK);
  pan_unpack((const struct mali_primitive_packed*)(jobs+0x128),PRIMITIVE,prim);
  pan_unpack((const struct mali_primitive_size_packed*)(jobs+0x1b8),PRIMITIVE_SIZE,size);
  pan_unpack((const struct mali_draw_packed*)(jobs+0x140),DRAW,draw);
  pan_unpack((const struct mali_invocation_packed*)(jobs+0x20),INVOCATION,invoke);
  pan_unpack((const struct mali_renderer_state_packed*)(jobs+0x500),RENDERER_STATE,vs);
  pan_unpack((const struct mali_renderer_state_packed*)(jobs+0x540),RENDERER_STATE,fs);
  assert(prim.draw_mode==(topology==0?MALI_DRAW_MODE_LINES:topology==1?MALI_DRAW_MODE_LINE_STRIP:
   topology==2?MALI_DRAW_MODE_TRIANGLES:MALI_DRAW_MODE_TRIANGLE_STRIP));
  assert(prim.index_count==count&&prim.index_type==MALI_INDEX_TYPE_NONE&&!prim.indices);
  assert(draw.flat_shading_vertex==(topology<2)&&size.fixed_sized==1&&invoke.invocations==count-1);
  uint64_t starts[5]={0},ends[5]={0};assert(vs.shader.varying_count<=5);
  for(unsigned i=0;i<vs.shader.varying_count;i++){
   pan_unpack((const struct mali_attribute_buffer_packed*)(jobs+0xa80+16*i),ATTRIBUTE_BUFFER,plane);
   starts[i]=plane.pointer;ends[i]=plane.pointer+plane.size;
   assert(plane.pointer>=m.draw.descriptorGPUVA+(count>1280?0x2c000:0x30000)&&plane.size==count*plane.stride&&
    ends[i]<=m.draw.descriptorGPUVA+sizeof(jobs));
   for(unsigned j=0;j<i;j++)assert(ends[i]<=starts[j]||ends[j]<=starts[i]);
  }
  assert(draw.position==starts[0]);
  for(unsigned i=0;i<fs.shader.varying_count;i++){
   pan_unpack((const struct mali_attribute_buffer_packed*)(jobs+0xc80+16*i),ATTRIBUTE_BUFFER,plane);
   if(plane.special==MALI_ATTRIBUTE_SPECIAL_FRAG_COORD)continue;
   unsigned matches=0;for(unsigned j=2;j<vs.shader.varying_count;j++)
    matches+=plane.pointer==starts[j]&&plane.pointer+plane.size==ends[j];
   assert(matches==1);
  }
  /* The encoder has emitted addresses, not CPU-generated output pixels. */
  for(unsigned i=0x30000;i<sizeof(jobs);i++)assert(!jobs[i]);
 }
 A5RuntimeMiscDraw m=original;m.draw.vertexCount=limit+1;m.draw.primitive=A5RuntimeLineStrip;
 m.draw.vertexBuffers[1]=(A5RuntimeBuffer){0x08000000,(limit+1)*2048,0,NULL};
 assert(!A5MaliRuntimeVertexSpan(p,limit+1));
 assert(A5MaliEncodeRuntimeMiscPass(&m,jobs,sizeof(jobs))==A5RuntimeUnsupported);
 for(unsigned i=0;i<sizeof(jobs);i++)assert(!jobs[i]);
 m.draw.vertexCount=165;m.draw.primitive=A5RuntimeLine;
 assert(A5MaliEncodeRuntimeMiscPass(&m,jobs,sizeof(jobs))==A5RuntimeUnsupported);
 m.draw.vertexCount=1;m.draw.primitive=A5RuntimeLineStrip;
 assert(A5MaliEncodeRuntimeMiscPass(&m,jobs,sizeof(jobs))==A5RuntimeUnsupported);
 m.draw.vertexCount=164;m.draw.primitive=99;
 assert(A5MaliEncodeRuntimeMiscPass(&m,jobs,sizeof(jobs))==A5RuntimeUnsupported);
}
void A5MaliCheckPackedVertexUpload(const uint8_t *jobs,const uint8_t *expected,unsigned n,uint32_t jobVA){
 pan_unpack((const struct mali_attribute_buffer_packed*)(jobs+0x900),ATTRIBUTE_BUFFER,buffer);
 pan_unpack((const struct mali_attribute_packed*)(jobs+0x800),ATTRIBUTE,position);
 pan_unpack((const struct mali_attribute_packed*)(jobs+0x808),ATTRIBUTE,color);
 assert(buffer.stride==16&&color.offset==position.offset+8);
 assert(position.format==((MALI_RG32F<<12)|(MALI_CHANNEL_R|(MALI_CHANNEL_G<<3)|(MALI_CHANNEL_0<<6)|(MALI_CHANNEL_1<<9))));
 assert(color.format==((MALI_RGBA16F<<12)|0x688));
 assert(buffer.size==n+position.offset&&buffer.pointer>=jobVA);
 uint64_t offset=buffer.pointer-jobVA+position.offset;
 assert(offset<=A5RuntimeJobBytes&&n<=A5RuntimeJobBytes-offset&&!memcmp(jobs+offset,expected,n));
}
void A5MaliTestDynamicFormat43(const A5MaliCompiledProfile*p,unsigned format,unsigned blend){
 static uint8_t uniforms[2][31][4096],vertices[8192],jobs[A5RuntimeJobBytes],baseline[A5RuntimeJobBytes];
 A5RuntimeMiscDraw m={0};m.draw.profile=p;m.draw.descriptorGPUVA=0x02000000;
 m.draw.vertexCount=4;m.draw.primitive=A5RuntimeTriangleStrip;m.draw.blend=blend;
 m.draw.viewportWidth=m.draw.scissorWidth=17;m.draw.viewportHeight=m.draw.scissorHeight=9;m.draw.viewportFar=1;
 unsigned row=format==43?48:80;
 m.colorAttachments[0]=(A5RuntimeImage){0x04000000,row*9,17,9,row,format};
 for(unsigned i=0;i<p->resourceCount;i++){
  const A5MaliCompiledResource*r=p->resources+i;
  if(r->kind==A5MaliResourceBuffer)(r->stage==1?m.draw.vertexBuffers:m.draw.fragmentBuffers)[r->metalIndex]=(A5RuntimeBuffer){0,r->uniformBytes,0,uniforms[r->stage-1][r->metalIndex]};
  else if(r->kind==A5MaliResourceTexture)m.fragmentTextures[r->metalIndex]=(A5RuntimeImage){0x06000000+0x100000*r->nativeIndex,p->profileID==606?1024:4096,32,32,p->profileID==606?32:128,p->profileID==606?1:80};
  else if(r->kind==A5MaliResourceSampler&&!(r->flags&A5MaliResourceImmutableSampler))m.fragmentSamplers[r->metalIndex]=(A5RuntimeSampler){.valid=1,.normalizedCoordinates=1,.maxAnisotropy=1};
 }
 unsigned vertexBytes=A5MaliRuntimeVertexSpan(p,4);assert(vertexBytes&&vertexBytes<=sizeof(vertices));
 m.draw.vertexBuffers[1]=(A5RuntimeBuffer){0,vertexBytes,0,vertices};
 assert(A5MaliEncodeRuntimeMiscPass(&m,jobs,sizeof(jobs))==A5RuntimeOK);
 assert(!memcmp(jobs+0x6000,p->passes[0].vertex.bytes,p->passes[0].vertex.byteCount));
 assert(!memcmp(jobs+0x8000,p->passes[0].fragment.bytes,p->passes[0].fragment.byteCount));
 pan_unpack((const struct mali_attribute_packed*)(jobs+0x800),ATTRIBUTE,position);
 unsigned rg=MALI_CHANNEL_R|(MALI_CHANNEL_G<<3)|(MALI_CHANNEL_0<<6)|(MALI_CHANNEL_1<<9);
 assert(position.format==((p->attributes[0].format==29?MALI_RG32F:MALI_RGBA32F)<<12|
        (p->attributes[0].format==29?rg:0x688)));
 if(p->profileID==A5MaliDynamicProfileID){
  /* Sparse Metal color index3 must become the correct compact native slot,
   * with the original half4 byte offset, independent of absent unused UVs. */
  unsigned compact=!!(p->flags&A5MaliProfileVertexColorOnly),dual=!!(p->flags&A5MaliProfileVertexTwoUV);
  unsigned noColor=!!(p->flags&A5MaliProfileVertexNoColor);
  unsigned colorSlot=compact?1:dual?3:2;
  unsigned offsets[4]={0};
  for(unsigned i=0;i<p->attributeCount;i++)offsets[p->attributes[i].index]=p->attributes[i].offset;
  if(!noColor){
   pan_unpack((const struct mali_attribute_packed*)(jobs+0x800+8*colorSlot),ATTRIBUTE,color);
   assert(color.buffer_index==position.buffer_index&&color.offset==position.offset-offsets[0]+offsets[3]);
   assert(color.format==((MALI_RGBA16F<<12)|0x688));
  }
  if(!compact){
   pan_unpack((const struct mali_attribute_packed*)(jobs+0x808),ATTRIBUTE,uv0);
   assert(uv0.offset==position.offset-offsets[0]+offsets[1]&&uv0.format==((MALI_RG32F<<12)|rg));
  }
  if(dual){
   pan_unpack((const struct mali_attribute_packed*)(jobs+0x810),ATTRIBUTE,uv1);
   assert(uv1.offset==position.offset-offsets[0]+offsets[2]&&uv1.format==((MALI_RG32F<<12)|rg));
  }
  pan_unpack((const struct mali_attribute_buffer_packed*)(jobs+0x900),ATTRIBUTE_BUFFER,vertexBuffer);
  assert(vertexBuffer.stride==p->layouts[0].stride);
  if(p->flags&A5MaliProfileFragmentNoTextures){
   pan_unpack((const struct mali_draw_packed*)(jobs+0x140),DRAW,draw);
   pan_unpack((const struct mali_renderer_state_packed*)(jobs+0x540),RENDERER_STATE,fragment);
   assert(!draw.textures&&!draw.samplers&&draw.varyings&&draw.varying_buffers);
   assert(!fragment.shader.texture_count&&!fragment.shader.sampler_count&&fragment.shader.varying_count);
   A5MaliCompiledProfile bad=*p;bad.flags&=~A5MaliProfileFragmentNoTextures;
   assert(!A5MaliDynamicRuntimeProfileSupported(&bad));
   bad=*p;bad.flags|=A5MaliProfileFragmentColorOnly;
   assert(!A5MaliDynamicRuntimeProfileSupported(&bad));
  }
 }
 check_preload(jobs,m.draw.descriptorGPUVA,m.colorAttachments);
 pan_section_unpack(jobs+0x300,FRAMEBUFFER,PARAMETERS,fb);
 assert(fb.internal_format==(format==43?MALI_COLOR_BUFFER_INTERNAL_FORMAT_R5G5B5A1:MALI_COLOR_BUFFER_INTERNAL_FORMAT_R8G8B8A8));
 assert(fb.color_writeback_format==(format==43?MALI_COLOR_FORMAT_R5G5B5A1:MALI_COLOR_FORMAT_R8G8B8A8));
 assert(fb.swizzle==0x60a&&fb.color_writeback.row_stride==row&&fb.color_writeback.base==0x04000000);
 pan_unpack((const struct mali_texture_packed*)(jobs+A5PreloadTexture),TEXTURE,pre);
 assert(pre.format==(((format==43?MALI_RGB5_A1_UNORM:MALI_RGBA8_UNORM)<<12)|0x60a));
 assert(pre.width==17&&pre.height==9&&pre.texel_ordering==MALI_TEXTURE_LAYOUT_LINEAR);
 pan_unpack((const struct mali_renderer_state_packed*)(jobs+0x540),RENDERER_STATE,rs);
 assert(rs.stencil_mask_misc.dither_disable);
 unsigned load=blend==A5RuntimeBlendState?
  A5MaliLowerRenderState(&p->attachmentContracts[1].attachments[0]).loadDestination:!!blend;
 assert(rs.multisample_misc.load_destination==!!(load||(p->flags&(A5MaliProfileFramebufferFetch|A5MaliProfileShaderBlend))));
 memcpy(baseline,jobs,sizeof(jobs));
 m.draw.vertexBuffers[1].bytes--;
 assert(A5MaliEncodeRuntimeMiscPass(&m,jobs,sizeof(jobs))==A5RuntimeBounds);
 m.draw.vertexBuffers[1].bytes++;
 /* Exact byte span and native 16-byte row alignment are separate gates. */
 m.colorAttachments[0].bytes--;
 assert(A5MaliEncodeRuntimeMiscPass(&m,jobs,sizeof(jobs))==A5RuntimeBounds);
 for(unsigned i=0;i<sizeof(jobs);i++)assert(!jobs[i]);
 m.colorAttachments[0].bytes++;m.colorAttachments[0].rowBytes=format==43?32:64;
 assert(A5MaliEncodeRuntimeMiscPass(&m,jobs,sizeof(jobs))==A5RuntimeBounds);
 m.colorAttachments[0].rowBytes=row-1;
 assert(A5MaliEncodeRuntimeMiscPass(&m,jobs,sizeof(jobs))==A5RuntimeBounds);
 m.colorAttachments[0].rowBytes=row;
 assert(A5MaliEncodeRuntimeMiscPass(&m,jobs,sizeof(jobs))==A5RuntimeOK&&!memcmp(jobs,baseline,sizeof(jobs)));
 check_lines_and_large_vertices(m);
 /* Target43 support must not expose dynamic_images' unrelated R8 fallback. */
 for(unsigned i=0;i<31;i++)if(m.fragmentTextures[i].gpuVA){
  unsigned original=m.fragmentTextures[i].metalPixelFormat;
  m.fragmentTextures[i].metalPixelFormat=43;
  assert(A5MaliEncodeRuntimeMiscPass(&m,jobs,sizeof(jobs))!=A5RuntimeOK);
  m.fragmentTextures[i].metalPixelFormat=original;
 }
 A5MaliCompiledProfile unsupported=*p;unsupported.colorFormats[0]=71;
 m.draw.profile=&unsupported;m.colorAttachments[0].metalPixelFormat=71;
 assert(A5MaliEncodeRuntimeMiscPass(&m,jobs,sizeof(jobs))==A5RuntimeUnsupported);
}
