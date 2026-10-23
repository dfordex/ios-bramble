/* SPDX-License-Identifier: MIT
 * Host-only checks for the two separately compiled iOS fragment variants.
 * Native shader inputs remain private and are supplied as command arguments.
 */
#define PAN_ARCH 4
#include "runtime_misc_encode.h"
#include "genxml/v4_pack.h"
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#if defined(__has_include)
#if __has_include("A5MaliCompiledRegistryData.inc")
#include "A5MaliCompiledRegistryData.inc"
#define A5_REAL_REGISTRY 1
#endif
#endif

static const char *const vs_hash="e0c51d2171b28c891677cdb1f1c98032bee0f03bb64af694a8321d711159fc96";
static const char *const fs_hash[2]={
 "90d93347ca8bb50eef500ac2296e71dfb8298a58bd24d903f913295560798424",
 "48bccbbdd2b788137ff228c7677e87a574ccfcd29f324a7bc44015bc15f3e2ce"
};
static uint8_t d[A5RuntimeJobBytes];
static uint8_t vertices[4*48],matrix[64],transform[16],bias[8];
static uint8_t*read_shader(const char *path,unsigned n){
 FILE*f=fopen(path,"rb");assert(f);uint8_t*b=malloc(n);assert(b);
 assert(fread(b,1,n,f)==n&&fgetc(f)==EOF);fclose(f);return b;
}
static int zeroed(void){for(unsigned i=0;i<sizeof(d);++i)if(d[i])return 0;return 1;}
static void run(unsigned id,const uint8_t*vs,const uint8_t*fs){
 unsigned t=id-604,fs_bytes=t?896:1120,fs_regs=t?5:6;
 A5MaliCompiledPass pass={id,0,
  {vs,2192,5,8,0,0,vs_hash},
  {fs,fs_bytes,5,fs_regs,0,0,fs_hash[t]}};
 A5MaliCompiledResource resources[]={
  {1,1,2,0,1,1,0,64,0,0},{1,1,3,1,2,1,0,16,0,4},
  {2,1,2,3,4,1,0,8,0,68},{2,2,3,5,0,1,0,0,0,0},
  {2,3,0,5,0,1,0,0,0,0}};
 A5MaliCompiledPushField push[]={
  {1,1,2,0,4,0},{1,1,3,4,4,0},{2,1,2,68,4,0},
  {2,2,0,72,4,0x2222}};
 A5MaliCompiledVertexAttribute attrs[]={
  {0,31,0,1},{1,29,16,1},{2,29,24,1},{3,27,32,1}};
 A5MaliCompiledVertexLayout layout={1,48,1,1};
 A5MaliCompiledAttachmentContract attachment[2]={0};
 for(unsigned c=0;c<2;++c)for(unsigned i=0;i<8;++i){
  attachment[c].attachments[i].writeMask=15;
  attachment[c].attachments[i].sourceRGB=1;
  attachment[c].attachments[i].sourceAlpha=1;
 }
 attachment[1].attachments[0].blendEnabled=1;
 attachment[1].attachments[0].destinationRGB=5;
 attachment[1].attachments[0].destinationAlpha=5;
 A5MaliCompiledProfile p={0};p.profileID=id;p.flags=A5MaliProfileSourceOverBlend;
 p.vertexName="fixed_vert_lph_spc";p.fragmentName="fixed_frag_lph_cph";
 p.colorFormats[0]=80;p.passes=&pass;p.passCount=1;
 p.resources=resources;p.resourceCount=5;p.pushFields=push;p.pushFieldCount=4;
 p.attributes=attrs;p.attributeCount=4;p.layouts=&layout;p.layoutCount=1;
 p.attachmentContracts=attachment;p.attachmentContractCount=2;
 A5RuntimeMiscDraw m={0};m.draw.profile=&p;m.draw.descriptorGPUVA=0x12000000;
 m.draw.vertexCount=4;m.draw.primitive=A5RuntimeTriangleStrip;
 m.draw.viewportWidth=m.draw.viewportHeight=32;m.draw.viewportFar=1;
 m.draw.scissorWidth=m.draw.scissorHeight=32;
 m.draw.vertexBuffers[1]=(A5RuntimeBuffer){0,sizeof(vertices),0,vertices};
 m.draw.vertexBuffers[2]=(A5RuntimeBuffer){0,sizeof(matrix),0,matrix};
 m.draw.vertexBuffers[3]=(A5RuntimeBuffer){0,sizeof(transform),0,transform};
 m.draw.fragmentBuffers[2]=(A5RuntimeBuffer){0,sizeof(bias),0,bias};
 m.colorAttachments[0]=(A5RuntimeImage){0x22000000,4096,32,32,128,80};
 m.fragmentSamplers[0]=(A5RuntimeSampler){1,A5RuntimeSamplerLinear,
  A5RuntimeSamplerNearest,A5RuntimeSamplerMipNone,
  A5RuntimeSamplerClampEdge,A5RuntimeSamplerClampEdge,
  A5RuntimeSamplerClampEdge,1,1,0,0,1000};
 const unsigned formats[]={80,30,10,1},bpp[]={4,2,1,1};
 for(unsigned i=0;i<4;++i){
  unsigned stride=16*bpp[i];
  m.fragmentTextures[3]=(A5RuntimeImage){0x23000000,stride*16,16,16,stride,formats[i]};
  assert(A5MaliEncodeRuntimeMiscPass(&m,d,sizeof(d))==A5RuntimeOK);
  assert(!memcmp(d+0x6000,vs,2192)&&!memcmp(d+0x8000,fs,fs_bytes));
  pan_unpack((struct mali_texture_packed*)(d+0x600),TEXTURE,tex);
  pan_unpack((struct mali_surface_with_stride_packed*)(d+0x620),SURFACE_WITH_STRIDE,surf);
  unsigned native=i==0?MALI_RGBA8_UNORM:i==1?MALI_RG8_UNORM:MALI_R8_UNORM;
  unsigned sw=i==0?0x60a:
   i==3?(MALI_CHANNEL_0|(MALI_CHANNEL_0<<3)|(MALI_CHANNEL_0<<6)|(MALI_CHANNEL_R<<9)):
   i==1?(MALI_CHANNEL_R|(MALI_CHANNEL_G<<3)|(MALI_CHANNEL_0<<6)|(MALI_CHANNEL_1<<9)):
        (MALI_CHANNEL_R|(MALI_CHANNEL_0<<3)|(MALI_CHANNEL_0<<6)|(MALI_CHANNEL_1<<9));
  assert(tex.format==((native<<12)|sw)&&surf.row_stride==stride&&
         surf.pointer==m.fragmentTextures[3].gpuVA);
  if(formats[i]==1){
   /* ReleasedPanfrost v4 A8=R8_UNORM/000R, not R001. Decode the actual
    * emitter bits and evaluate all possible stored alpha byte values. */
   assert((tex.format&0xfff)==(MALI_CHANNEL_0|(MALI_CHANNEL_0<<3)|
     (MALI_CHANNEL_0<<6)|(MALI_CHANNEL_R<<9)));
   for(unsigned a=0;a<256;++a){
    float channels[6]={a/255.0f,0,0,0,0,1},rgba[4];
    for(unsigned c=0;c<4;++c)rgba[c]=channels[((tex.format&0xfff)>>(3*c))&7];
    assert(rgba[0]==0&&rgba[1]==0&&rgba[2]==0&&rgba[3]==a/255.0f);
   }
  }
  pan_unpack((struct mali_renderer_state_packed*)(d+0x540),RENDERER_STATE,rs);
  assert(rs.shader.texture_count==1&&rs.shader.sampler_count==1&&
         rs.shader.varying_count==(t?1:2)&&rs.properties.work_register_count==fs_regs);
  pan_unpack((struct mali_attribute_packed*)(d+0xc00),ATTRIBUTE,uv);
  assert((uv.format>>12)==MALI_RG32F);
  if(!t){
   pan_unpack((struct mali_attribute_packed*)(d+0xc08),ATTRIBUTE,color);
   pan_unpack((struct mali_attribute_buffer_packed*)(d+0xc90),ATTRIBUTE_BUFFER,colbuf);
   assert((color.format>>12)==MALI_RGBA32F&&color.buffer_index==1&&
          colbuf.pointer==m.draw.descriptorGPUVA+0x33000&&colbuf.stride==16);
  }
  m.draw.blend=A5RuntimeBlendPremultipliedSourceOver;
  assert(A5MaliEncodeRuntimeMiscPass(&m,d,sizeof(d))==A5RuntimeOK);
  pan_unpack((struct mali_renderer_state_packed*)(d+0x540),RENDERER_STATE,blend);
  assert(blend.multisample_misc.load_destination&&blend.blend_equation.rgb.invert_c);
  m.draw.blend=A5RuntimeBlendCopy;
 }
#ifdef A5_REAL_REGISTRY
 const A5MaliCompiledProfile*real=NULL;
 for(size_t i=0;i<sizeof(kA5MaliCompiledProfiles)/sizeof(kA5MaliCompiledProfiles[0]);++i)
  if(kA5MaliCompiledProfiles[i].profileID==id)real=&kA5MaliCompiledProfiles[i];
 assert(real);m.draw.profile=real;
 assert(A5MaliEncodeRuntimeMiscPass(&m,d,sizeof(d))==A5RuntimeOK);
 m.draw.profile=&p;
#endif
 m.fragmentSamplers[0].sAddressMode=A5RuntimeSamplerRepeat;
 assert(A5MaliEncodeRuntimeMiscPass(&m,d,sizeof(d))==A5RuntimeUnsupported&&zeroed());
 m.fragmentSamplers[0].sAddressMode=A5RuntimeSamplerClampEdge;
 m.fragmentTextures[3].metalPixelFormat=115;
 assert(A5MaliEncodeRuntimeMiscPass(&m,d,sizeof(d))==A5RuntimeUnsupported&&zeroed());
 m.fragmentTextures[3].metalPixelFormat=80;
 pass.fragment.sha256="wrong";
 assert(A5MaliEncodeRuntimeMiscPass(&m,d,sizeof(d))==A5RuntimeUnsupported&&zeroed());
}
int main(int argc,char**argv){
 assert(argc==4);
 uint8_t*vs=read_shader(argv[1],2192);
 uint8_t*fs604=read_shader(argv[2],1120),*fs605=read_shader(argv[3],896);
 run(604,vs,fs604);run(605,vs,fs605);
 free(vs);free(fs604);free(fs605);
 puts("PASS generic604/605 native texture descriptors, varying ABI, formats and strict rejects; device pixels unverified");
}
