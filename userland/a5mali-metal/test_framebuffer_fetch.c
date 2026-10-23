/* SPDX-License-Identifier: MIT
 * Actual published code -> actual dynamic profile -> native descriptor emitter.
 * Synthetic addresses/buffers validate contracts only; no GPU executes here.
 */
#include "../a5xelte-air-translation/families/runtime_misc_encode.h"
#include "genxml/v4_pack.h"
#include <assert.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
static uint64_t word64(const uint8_t *p){uint64_t v;memcpy(&v,p,8);return v;}
static int zero(const uint8_t*p,size_t n){for(size_t i=0;i<n;i++)if(p[i])return 0;return 1;}
int A5MaliTestFramebufferFetchProfile(const A5MaliCompiledProfile *p,int blend);
int A5MaliTestFramebufferFetchProfile(const A5MaliCompiledProfile *p,int blend)
{
 unsigned checks=0;
#define CHECK(x) do { assert(x); checks++; } while(0)
 CHECK(p&&p->profileID==A5MaliDynamicProfileID&&A5MaliDynamicRuntimeProfileSupported(p));
 CHECK((p->flags&(A5MaliProfileFramebufferFetch|A5MaliProfileFragmentPosition))==
        (A5MaliProfileFramebufferFetch|A5MaliProfileFragmentPosition));
 CHECK(p->passes[0].fragment.byteCount==4672&&p->passes[0].fragment.firstTag==8);
 CHECK(p->immutableSamplerCount==1&&p->immutableSamplers[0].nativeIndex==1);
 unsigned char vertices[288]={0},matrix[64]={0},uv[16]={0},fragment1[168]={0},fragment2[4]={0};
 unsigned char half[2]={0x00,0x3c};
 A5RuntimeMiscDraw m={0};m.draw.profile=p;m.draw.vertexCount=6;
 m.draw.primitive=A5RuntimeTriangle;m.draw.descriptorGPUVA=0x10000000;
 m.draw.blend=blend?A5RuntimeBlendPremultipliedSourceOver:A5RuntimeBlendCopy;
 m.draw.viewportWidth=m.draw.viewportHeight=32;m.draw.viewportFar=1;
 m.draw.scissorWidth=m.draw.scissorHeight=32;
 m.draw.vertexBuffers[1]=(A5RuntimeBuffer){0,sizeof(vertices),0,vertices};
 m.draw.vertexBuffers[2]=(A5RuntimeBuffer){0,sizeof(matrix),0,matrix};
 m.draw.vertexBuffers[3]=(A5RuntimeBuffer){0,sizeof(uv),0,uv};
 m.draw.fragmentBuffers[1]=(A5RuntimeBuffer){0,sizeof(fragment1),0,fragment1};
 m.draw.fragmentBuffers[2]=(A5RuntimeBuffer){0,sizeof(fragment2),0,fragment2};
 m.draw.fragmentBuffers[5]=(A5RuntimeBuffer){0,sizeof(half),0,half};
 m.colorAttachments[0]=(A5RuntimeImage){0x13000000,4096,32,32,128,80};
 m.fragmentTextures[3]=(A5RuntimeImage){0x14000000,4096,32,32,128,80};
 m.fragmentTextures[9]=(A5RuntimeImage){0x15000000,2048,256,1,2048,115};
 m.fragmentSamplers[0]=(A5RuntimeSampler){.valid=1,.normalizedCoordinates=1,.maxAnisotropy=1};
 uint8_t *d=malloc(A5RuntimeJobBytes);CHECK(d);
 CHECK(A5MaliEncodeRuntimeMiscPass(&m,d,A5RuntimeJobBytes)==A5RuntimeOK);
 CHECK(!memcmp(d+0x8000,p->passes[0].fragment.bytes,4672));
 struct MALI_RENDERER_STATE rs;MALI_RENDERER_STATE_unpack((const struct mali_renderer_state_packed*)(d+0x540),&rs);
 CHECK(rs.shader.shader==m.draw.descriptorGPUVA+0x8000+8);
 CHECK(rs.shader.texture_count==2&&rs.shader.sampler_count==2&&rs.shader.varying_count==3);
 CHECK(rs.properties.uniform_buffer_count==6&&rs.properties.work_register_count==14&&rs.multisample_misc.load_destination);
 CHECK(rs.blend_equation.rgb.b==(blend?MALI_BLEND_OPERAND_B_DEST:MALI_BLEND_OPERAND_B_SRC));
 struct MALI_ATTRIBUTE a;MALI_ATTRIBUTE_unpack((const struct mali_attribute_packed*)(d+0xc00+16),&a);
 CHECK(a.buffer_index==2&&a.format==((MALI_RGBA32F<<12)|0x688));
 struct MALI_ATTRIBUTE_BUFFER ab;MALI_ATTRIBUTE_BUFFER_unpack((const struct mali_attribute_buffer_packed*)(d+0xc80+32),&ab);
 /* Special and type overlap in the packed ABI; unpacked type is37,
  * not the zero used when constructing a special descriptor. */
 CHECK(ab.special==MALI_ATTRIBUTE_SPECIAL_FRAG_COORD&&ab.pointer==0&&ab.stride==0&&ab.size==0);
 struct MALI_DRAW draw;MALI_DRAW_unpack((const struct mali_draw_packed*)(d+0x140),&draw);
 CHECK(draw.textures==m.draw.descriptorGPUVA+0x4100&&draw.samplers==m.draw.descriptorGPUVA+0x4140);
 CHECK(word64(d+0x4100)==m.draw.descriptorGPUVA+0x4000);
 CHECK(word64(d+0x4108)==m.draw.descriptorGPUVA+0x4040);
 struct MALI_TEXTURE tex;MALI_TEXTURE_unpack((const struct mali_texture_packed*)(d+0x4040),&tex);
 CHECK(tex.width==256&&tex.height==1&&tex.format==((MALI_RGBA16F<<12)|0x688));
 struct MALI_SURFACE_WITH_STRIDE surface;MALI_SURFACE_WITH_STRIDE_unpack((const struct mali_surface_with_stride_packed*)(d+0x4060),&surface);
 CHECK(surface.pointer==0x15000000&&surface.row_stride==2048);
 struct MALI_SAMPLER sampler;MALI_SAMPLER_unpack((const struct mali_sampler_packed*)(d+0x4140+MALI_SAMPLER_LENGTH),&sampler);
 CHECK(sampler.normalized_coordinates&&sampler.minify_nearest&&sampler.magnify_nearest);
 CHECK(sampler.wrap_mode_s==MALI_WRAP_MODE_REPEAT&&sampler.wrap_mode_t==MALI_WRAP_MODE_REPEAT&&sampler.wrap_mode_r==MALI_WRAP_MODE_REPEAT);
 CHECK(sampler.maximum_lod==0.25f);
 struct MALI_UNIFORM_BUFFER u;MALI_UNIFORM_BUFFER_unpack((const struct mali_uniform_buffer_packed*)(d+0x740+5*8),&u);
 CHECK(u.pointer>=m.draw.descriptorGPUVA+0x20000&&u.pointer-m.draw.descriptorGPUVA<A5RuntimeJobBytes-16);
 const uint8_t *tail=d+(size_t)(u.pointer-m.draw.descriptorGPUVA);
 CHECK(tail[0]==half[0]&&tail[1]==half[1]&&zero(tail+2,14));
 CHECK(u.entries==1);
 /* Incomplete source, invalid sampler semantics and missing logical bytes
  * must fail and leave no partially executable descriptor payload. */
 m.fragmentTextures[9].bytes=2047;
 CHECK(A5MaliEncodeRuntimeMiscPass(&m,d,A5RuntimeJobBytes)!=A5RuntimeOK&&zero(d,A5RuntimeJobBytes));
 m.fragmentTextures[9].bytes=2048;m.draw.fragmentBuffers[5].bytes=1;
 CHECK(A5MaliEncodeRuntimeMiscPass(&m,d,A5RuntimeJobBytes)!=A5RuntimeOK&&zero(d,A5RuntimeJobBytes));
 m.draw.fragmentBuffers[5].bytes=2;
 A5MaliCompiledProfile bad=*p;A5MaliCompiledSampler states[4];
 memcpy(states,p->immutableSamplers,p->immutableSamplerCount*sizeof(*states));bad.immutableSamplers=states;
 states[0].sAddressMode=A5RuntimeSamplerClampEdge;
 CHECK(!A5MaliDynamicRuntimeProfileSupported(&bad));m.draw.profile=&bad;
 CHECK(A5MaliEncodeRuntimeMiscPass(&m,d,A5RuntimeJobBytes)!=A5RuntimeOK&&zero(d,A5RuntimeJobBytes));
 bad=*p;bad.flags&=~A5MaliProfileFramebufferFetch;
 CHECK(!A5MaliDynamicRuntimeProfileSupported(&bad));
 free(d);printf("PASS actual fetch emitter: %u grouped checks, blend=%d (no GPU execution)\n",checks,blend);
 return 1;
}
