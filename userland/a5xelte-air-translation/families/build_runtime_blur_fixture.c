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
/* The legacy fixture's *destination* is BGRA; its independent source pattern
 * is stored as RGBA and declared as RGBA in its texture descriptor. Reusing
 * those bytes as the real runtime's MetalBGRA8 image requires input conversion. */
static int legacy_source_is_rgba(const uint8_t*d){
 pan_unpack((const struct mali_texture_packed*)(d+0x600),TEXTURE,t);
 pan_unpack((const struct mali_surface_with_stride_packed*)(d+0x620),SURFACE_WITH_STRIDE,s);
 return t.width==64&&t.height==64&&t.array_size==1&&t.levels==1&&
  t.format==((MALI_RGBA8_UNORM<<12)|0x688)&&t.swizzle==0x688&&
  t.dimension==MALI_TEXTURE_DIMENSION_2D&&t.texel_ordering==MALI_TEXTURE_LAYOUT_LINEAR&&
  s.pointer==0x0200a000&&s.row_stride==256&&s.surface_stride==0x4000;
}
static void rgba_source_to_bgra(uint8_t*dst,const uint8_t*src){
 /* Test-input preparation only: no expected/output framebuffer is generated. */
 for(unsigned i=0;i<64*64;++i){
  dst[4*i]=src[4*i+2];dst[4*i+1]=src[4*i+1];
  dst[4*i+2]=src[4*i];dst[4*i+3]=src[4*i+3];
 }
}

int main(int argc,char**argv){
 if(argc<3||argc>5)return 2;
 int linear=argc==5&&!strcmp(argv[4],"--linear");if(argc==5&&!linear)return 2;FILE*f=fopen(argv[1],"rb");if(!f)return 2;
 if(fread(legacy,1,sizeof(legacy),f)!=sizeof(legacy)||fgetc(f)!=EOF)return 2;fclose(f);
 if(!legacy_source_is_rgba(legacy)){fputs("legacy source must be exact RGBA8 linear64x64 contract\n",stderr);return 2;}
 const A5MaliCompiledProfile*p=NULL;
 for(unsigned i=0;i<sizeof(kA5MaliCompiledProfiles)/sizeof(kA5MaliCompiledProfiles[0]);++i)
  if(kA5MaliCompiledProfiles[i].profileID==100)p=kA5MaliCompiledProfiles+i;
 if(!p||(p->flags&A5MaliProfileFixedViewport))return 2;
 float mvp[16]={0};mvp[0]=mvp[5]=2.f/32;mvp[10]=mvp[15]=1;mvp[12]=mvp[13]=-1;
 A5RuntimeDraw d={0};d.profile=p;d.descriptorGPUVA=0x02000000;
 d.source=(A5RuntimeImage){0x03000000,0x4000,64,64,256,80};
 d.destination=(A5RuntimeImage){0x04000000,0x1000,32,32,128,80};
 uint8_t vertices[192];memcpy(vertices,legacy+0xc00,sizeof(vertices));
 if(linear){
  /* Same positions and indexed topology; fractional source coordinates cross
   * the left and bottom clamp boundaries and stripe interiors. No expected
   * framebuffer values enter this input preparation. */
  for(unsigned i=0;i<4;++i){float uv[2]={(i&1)?62.25f:-1.75f,(i&2)?64.25f:.25f};
   memcpy(vertices+i*48+16,uv,sizeof(uv));}
  d.sourceSampler=(A5RuntimeBlurSampler){.valid=1,.minFilter=1,.magFilter=1,
   .normalizedCoordinates=1,.maxAnisotropy=1};
 }
 d.vertexBuffers[1]=(A5RuntimeBuffer){0,192,0,vertices};
 d.vertexBuffers[2]=(A5RuntimeBuffer){0,64,0,(const uint8_t*)mvp};
 d.vertexBuffers[3]=(A5RuntimeBuffer){0,16,0,legacy+0xa40};
 d.fragmentBuffers[1]=(A5RuntimeBuffer){0,32,0,legacy+0xa80};
 d.fragmentBuffers[6]=(A5RuntimeBuffer){0,2,0,legacy+0xb00};
 d.viewportWidth=d.viewportHeight=32;d.viewportFar=1;
 d.scissorWidth=d.scissorHeight=32;d.vertexCount=4;d.primitive=A5RuntimeTriangleStrip;
 uint8_t indexBytes[32]={0};unsigned indexWidth=0;
 if(argc>=4){
  unsigned bits=(unsigned)strtoul(argv[3],NULL,10);if(bits!=16&&bits!=32)return 2;
  indexWidth=bits/8;const uint32_t indices[]={2,0,1,2,1,3};
  memset(indexBytes,0xa6,sizeof(indexBytes));
  for(unsigned i=0;i<6;i++)memcpy(indexBytes+(i+2)*indexWidth,indices+i,indexWidth);
  d.indexBuffer=(A5RuntimeBuffer){0,sizeof(indexBytes),2*indexWidth,indexBytes};
  d.indexCount=6;d.indexSize=indexWidth;d.primitive=A5RuntimeTriangle;
 }
 if(A5MaliEncodeRuntimeDraw(&d,out,sizeof(out)))return 2;
 if(indexWidth){
  /* The test BO's source image occupies3a000..3e000; move only this tiny
   * fixture's genuine index stream below it before inserting source pixels.
   * Production uses the separately validated descriptor index arena. */
  pan_unpack((struct mali_primitive_packed*)(out+0x128),PRIMITIVE,primitive);
  if(primitive.indices<d.descriptorGPUVA ||
     primitive.indices-d.descriptorGPUVA>sizeof(out)-6*indexWidth)return 2;
  memcpy(out+0x39c00,out+(primitive.indices-d.descriptorGPUVA),6*indexWidth);
  if(memcmp(out+0x39c00,indexBytes+2*indexWidth,6*indexWidth))return 2;
  primitive.indices=d.descriptorGPUVA+0x39c00;
  MALI_PRIMITIVE_pack((struct mali_primitive_packed*)(out+0x128),&primitive);
 }
 /* Suite-only relocation into an unused tail of its one mapped test BO.
  * Production encoder correctly forbids image aliases of its descriptor BO. */
 pan_unpack((struct mali_surface_with_stride_packed*)(out+0x620),SURFACE_WITH_STRIDE,s);
 s.pointer=d.descriptorGPUVA+0x3a000;MALI_SURFACE_WITH_STRIDE_pack((struct mali_surface_with_stride_packed*)(out+0x620),&s);
 pan_unpack((struct mali_framebuffer_parameters_packed*)(out+0x320),FRAMEBUFFER_PARAMETERS,fb);
 fb.color_writeback.base=d.descriptorGPUVA+0x3e000;
 /* The SFBD clear values alias load addresses in the generated packer.
  * No direct hardware preload remains; explicitly zero both interpretations. */
 fb.color_preload_enable=false;fb.color_load_address=0;fb.color_load_row_stride=0;fb.color_load_surface_stride=0;
 fb.clear_color_0=fb.clear_color_1=fb.clear_color_2=fb.clear_color_3=0;
 MALI_FRAMEBUFFER_PARAMETERS_pack((struct mali_framebuffer_parameters_packed*)(out+0x320),&fb);
 pan_unpack((struct mali_surface_with_stride_packed*)(out+0x19a0),SURFACE_WITH_STRIDE,preload);
 preload.pointer=d.descriptorGPUVA+0x3e000;MALI_SURFACE_WITH_STRIDE_pack((struct mali_surface_with_stride_packed*)(out+0x19a0),&preload);
 rgba_source_to_bgra(out+0x3a000,legacy+0xa000);memset(out+0x3e000,0xcd,0x1000);memset(out+0x3f000,0xa7,0x1000);
 f=fopen(argv[2],"wb");if(!f)return 2;
 if(fwrite(out,1,sizeof(out),f)!=sizeof(out)||fclose(f))return 2;
 printf("Encoded genuine dynamic blur VS offscreen32x32, index width=%u; real runtime descriptors and caller ortho MVP; linear=%u; no GPU execution claim\n",indexWidth,linear);return 0;
}
