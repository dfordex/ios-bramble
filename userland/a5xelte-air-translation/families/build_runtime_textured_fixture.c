/* SPDX-License-Identifier: MIT
 * Narrow 604 colour-varying and 605 RG-luma/alpha GPU oracles. This builds
 * genuine runtime jobs; the independent Python oracle never enters a shader.
 */
#define PAN_ARCH 4
#include "runtime_misc_encode.h"
#include "genxml/v4_pack.h"
#include "A5MaliCompiledRegistryData.inc"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>

enum { BASE=0x02000000, SOURCE=0x3a000, OUTPUT=0x3e000, GUARD=0x3f000 };
static uint8_t bytes[A5RuntimeJobBytes];
static const A5MaliCompiledProfile *profile(unsigned id){
 for(unsigned i=0;i<sizeof(kA5MaliCompiledProfiles)/sizeof(kA5MaliCompiledProfiles[0]);++i)
  if(kA5MaliCompiledProfiles[i].profileID==id)return kA5MaliCompiledProfiles+i;
 return NULL;
}
static void make_vertices(uint8_t v[192]){
 memset(v,0,192);
 for(unsigned i=0;i<4;++i){
  /* Original Metal coordinates: y=0 is top. The runtime supplies the real
   * negative-height Vulkan boundary transform; the caller's matrix does not
   * substitute an independently flipped image. */
  const float x=(float)(i&1)*32.f,y=(float)(i>>1)*32.f;
  const float position[4]={x,y,0,1},uv[2]={x/32.f,y/32.f};
  const uint16_t color[4]={0x3800,0x3400,0x3c00,0x3800}; /* .5,.25,1,.5 */
  memcpy(v+i*48,position,16);memcpy(v+i*48+16,uv,8);
  memcpy(v+i*48+32,color,8);
 }
}
static void check_descriptors(unsigned id,unsigned format,unsigned row,int blend){
 const unsigned rg=MALI_CHANNEL_R|(MALI_CHANNEL_G<<3)|(MALI_CHANNEL_0<<6)|(MALI_CHANNEL_1<<9);
 pan_unpack((const struct mali_texture_packed*)(bytes+0x600),TEXTURE,texture);
 pan_unpack((const struct mali_surface_with_stride_packed*)(bytes+0x620),SURFACE_WITH_STRIDE,surface);
 assert(texture.width==32&&texture.height==32&&texture.levels==1&&texture.array_size==1);
 assert(texture.dimension==MALI_TEXTURE_DIMENSION_2D&&texture.texel_ordering==MALI_TEXTURE_LAYOUT_LINEAR);
 const unsigned alpha=MALI_CHANNEL_0|(MALI_CHANNEL_0<<3)|(MALI_CHANNEL_0<<6)|(MALI_CHANNEL_R<<9);
 assert(texture.format==((format<<12)|(id==604?0x60a:id==606?alpha:rg))&&texture.swizzle==0x688);
 assert(surface.pointer==BASE+SOURCE&&surface.row_stride==(int)row&&surface.surface_stride==row*32);
 pan_unpack((const struct mali_renderer_state_packed*)(bytes+0x540),RENDERER_STATE,fs);
 assert(fs.shader.varying_count==(id==604?2u:1u)&&fs.shader.texture_count==1&&fs.shader.sampler_count==1);
 assert(fs.multisample_misc.load_destination==(bool)blend);
 if(id==606){
  pan_unpack((const struct mali_uniform_buffer_packed*)(bytes+0x740+3*8),UNIFORM_BUFFER,clamp);
  assert(clamp.entries==8&&clamp.pointer>=BASE+0x20000&&clamp.pointer+128<=BASE+0x30000);
  const float expected[4]={8.5f/32,4.5f/32,23.5f/32,27.5f/32};
  assert(!memcmp(bytes+(unsigned)(clamp.pointer-BASE)+112,expected,sizeof(expected)));
 }
 pan_unpack((const struct mali_attribute_packed*)(bytes+0xc00),ATTRIBUTE,uv);
 assert(uv.format==((MALI_RG32F<<12)|rg)&&uv.buffer_index==0);
 if(id==604){
  pan_unpack((const struct mali_attribute_packed*)(bytes+0xc08),ATTRIBUTE,color);
  pan_unpack((const struct mali_attribute_buffer_packed*)(bytes+0xc90),ATTRIBUTE_BUFFER,colorBuffer);
  assert(color.format==((MALI_RGBA32F<<12)|0x688)&&color.buffer_index==1);
  assert(colorBuffer.pointer==BASE+0x33000&&colorBuffer.stride==16&&colorBuffer.size==64);
 }
 pan_unpack((const struct mali_sampler_packed*)(bytes+0x6a0),SAMPLER,sampler);
 assert(sampler.normalized_coordinates&&sampler.minify_nearest&&sampler.magnify_nearest);
 assert(sampler.wrap_mode_s==MALI_WRAP_MODE_CLAMP_TO_EDGE&&sampler.wrap_mode_t==MALI_WRAP_MODE_CLAMP_TO_EDGE);
 pan_unpack((const struct mali_framebuffer_parameters_packed*)(bytes+0x320),FRAMEBUFFER_PARAMETERS,fb);
 assert(fb.color_writeback.base==BASE+OUTPUT&&fb.color_writeback.row_stride==128);
 assert(fb.bound_max_x==31&&fb.bound_max_y==31&&!fb.color_preload_enable);
 pan_unpack((const struct mali_surface_with_stride_packed*)(bytes+0x19a0),SURFACE_WITH_STRIDE,preload);
 assert(preload.pointer==BASE+OUTPUT&&preload.row_stride==128);
}
int main(int argc,char **argv){
 if(argc!=3&&argc!=4)return 2;unsigned id=(unsigned)strtoul(argv[1],NULL,10);
 if(id!=604&&id!=605&&id!=606)return 2;
 int blend=argc==4&&!strcmp(argv[3],"blend");if(argc==4&&(!blend||id!=606))return 2;
 const A5MaliCompiledProfile*p=profile(id);if(!p)return 2;
 float matrix[16]={0};matrix[0]=2.f/32;matrix[5]=-2.f/32;
 matrix[10]=matrix[15]=1;matrix[12]=-1;matrix[13]=1;
 const float uvTransform[4]={1,1,0,0},bias[2]={0,0};uint8_t vertices[192];make_vertices(vertices);
 A5RuntimeMiscDraw m={0};m.draw.profile=p;m.draw.descriptorGPUVA=BASE;
 m.draw.vertexBuffers[1]=(A5RuntimeBuffer){0,sizeof(vertices),0,vertices};
 m.draw.vertexBuffers[2]=(A5RuntimeBuffer){0,sizeof(matrix),0,(const uint8_t*)matrix};
 m.draw.vertexBuffers[3]=(A5RuntimeBuffer){0,sizeof(uvTransform),0,(const uint8_t*)uvTransform};
 m.draw.fragmentBuffers[2]=(A5RuntimeBuffer){0,sizeof(bias),0,(const uint8_t*)bias};
 uint8_t fragment1[128]={0};
 const float clamp[4]={8.5f/32,4.5f/32,23.5f/32,27.5f/32};
 memcpy(fragment1+112,clamp,sizeof(clamp));
 if(id==606)m.draw.fragmentBuffers[1]=(A5RuntimeBuffer){0,sizeof(fragment1),0,fragment1};
 m.colorAttachments[0]=(A5RuntimeImage){0x04000000,4096,32,32,128,80};
 const unsigned row=id==604?128:id==606?32:64;
 m.fragmentTextures[3]=(A5RuntimeImage){0x03000000,row*32,32,32,row,id==604?80u:id==606?1u:30u};
 m.fragmentSamplers[0]=(A5RuntimeSampler){.valid=1,.normalizedCoordinates=1,.maxAnisotropy=1};
 m.draw.vertexCount=4;m.draw.primitive=A5RuntimeTriangleStrip;m.draw.blend=blend?A5RuntimeBlendPremultipliedSourceOver:A5RuntimeBlendCopy;
 m.draw.scissorWidth=m.draw.scissorHeight=32;m.draw.viewportWidth=m.draw.viewportHeight=32;m.draw.viewportFar=1;
 if(id==606){
  m.draw.fragmentBuffers[1].bytes=127;
  assert(A5MaliEncodeRuntimeMiscPass(&m,bytes,sizeof(bytes))==A5RuntimeBounds);
  m.draw.fragmentBuffers[1].bytes=128;
 }
 if(A5MaliEncodeRuntimeMiscPass(&m,bytes,sizeof(bytes)))return 2;
 /* Sole suite-only relocation: production jobs intentionally reject source
  * and destination aliases of the descriptor BO. Private test maps one BO. */
 pan_unpack((const struct mali_surface_with_stride_packed*)(bytes+0x620),SURFACE_WITH_STRIDE,s);
 s.pointer=BASE+SOURCE;MALI_SURFACE_WITH_STRIDE_pack((struct mali_surface_with_stride_packed*)(bytes+0x620),&s);
 pan_unpack((const struct mali_framebuffer_parameters_packed*)(bytes+0x320),FRAMEBUFFER_PARAMETERS,fb);
 fb.color_writeback.base=BASE+OUTPUT;
 fb.color_preload_enable=false;fb.color_load_address=0;fb.color_load_row_stride=0;fb.color_load_surface_stride=0;
 fb.clear_color_0=fb.clear_color_1=fb.clear_color_2=fb.clear_color_3=0;
 MALI_FRAMEBUFFER_PARAMETERS_pack((struct mali_framebuffer_parameters_packed*)(bytes+0x320),&fb);
 pan_unpack((const struct mali_surface_with_stride_packed*)(bytes+0x19a0),SURFACE_WITH_STRIDE,pre);
 pre.pointer=BASE+OUTPUT;MALI_SURFACE_WITH_STRIDE_pack((struct mali_surface_with_stride_packed*)(bytes+0x19a0),&pre);
 memset(bytes+0x39000,0xa7,0x1000);memset(bytes+SOURCE,0x5b,0x4000);
 for(unsigned y=0;y<32;++y)for(unsigned x=0;x<32;++x){
  uint8_t r=((x/7)&1)?255:0,g=((y/5)&1)?255:0;
  if(id==604){uint8_t*b=bytes+SOURCE+y*row+x*4;b[0]=((x/11+y/3)&1)?255:0;b[1]=g;b[2]=r;b[3]=255;}
  else if(id==605){bytes[SOURCE+y*row+x*2]=r;bytes[SOURCE+y*row+x*2+1]=g;}
  else bytes[SOURCE+y*row+x]=(uint8_t)(x*5+y*7+13);
 }
 memset(bytes+OUTPUT,0xcd,4096);memset(bytes+GUARD,0xa7,4096);
 if(blend)for(unsigned i=0;i<4096;i+=4){
  bytes[OUTPUT+i]=32;bytes[OUTPUT+i+1]=64;bytes[OUTPUT+i+2]=96;bytes[OUTPUT+i+3]=128;
 }
 check_descriptors(id,id==604?MALI_RGBA8_UNORM:id==606?MALI_R8_UNORM:MALI_RG8_UNORM,row,blend);
 FILE*f=fopen(argv[2],"wb");if(!f)return 2;int ok=fwrite(bytes,1,sizeof(bytes),f)==sizeof(bytes)&&!fclose(f);
 if(ok)printf("Runtime%u genuine shaders, normalized nearest source, UV/colour descriptor contracts and relocation: PASS (not GPU execution)\n",id);
 return !ok;
}
