/* SPDX-License-Identifier: MIT
 * Structural regression using the caller's real private compiled registry.
 * Does not equate valid descriptors with hardware execution.
 */
#define PAN_ARCH 4
#include "runtime_encode.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include "genxml/v4_pack.h"
#include "A5MaliCompiledRegistryData.inc"
static uint8_t output[A5RuntimeJobBytes],vertex[256*48+64],uniforms[512];
static int zero(void){for(unsigned i=0;i<sizeof(output);++i)if(output[i])return 0;return 1;}
static A5RuntimeDraw request(const A5MaliCompiledProfile*p,unsigned w,unsigned h){
 A5RuntimeDraw d={0};d.profile=p;d.descriptorGPUVA=0x12000000;
 d.source=(A5RuntimeImage){0x20000000,0x800000,128,64,512,80};
 d.destination=(A5RuntimeImage){0x21000000,0x2000000,w,h,w*(p->colorFormats[0]==115?8:4),p->colorFormats[0]};
 d.viewportWidth=1080;d.viewportHeight=1920;d.viewportFar=1;d.vertexCount=4;d.primitive=A5RuntimeTriangleStrip;
 d.scissorX=16;d.scissorY=16;d.scissorWidth=w-16;d.scissorHeight=h-16;
 for(unsigned i=0;i<p->resourceCount;++i){const A5MaliCompiledResource*r=p->resources+i;
  if(r->kind==A5MaliResourceBuffer){A5RuntimeBuffer*b=r->stage==A5MaliStageVertex?&d.vertexBuffers[r->metalIndex]:&d.fragmentBuffers[r->metalIndex];
   *b=(A5RuntimeBuffer){0,sizeof(uniforms),31,uniforms};
  }
 }
 d.vertexBuffers[1]=(A5RuntimeBuffer){0,sizeof(vertex),17,vertex};return d;
}
static void compare_legacy(const char*path){
 uint8_t*legacy=malloc(A5RuntimeJobBytes);assert(legacy);FILE*f=fopen(path,"rb");assert(f);
 assert(fread(legacy,1,A5RuntimeJobBytes,f)==A5RuntimeJobBytes&&fgetc(f)==EOF);fclose(f);
 const A5MaliCompiledProfile*p=NULL;
 for(unsigned i=0;i<sizeof(kA5MaliCompiledProfiles)/sizeof(kA5MaliCompiledProfiles[0]);++i)
  if(kA5MaliCompiledProfiles[i].profileID==100)p=kA5MaliCompiledProfiles+i;
 assert(p);A5RuntimeDraw d=request(p,32,32);d.scissorX=d.scissorY=0;d.scissorWidth=d.scissorHeight=32;
 d.source.width=d.source.height=64;d.source.rowBytes=256;
 d.vertexBuffers[1]=(A5RuntimeBuffer){0,192,0,legacy+0xc00};
 d.vertexBuffers[2]=(A5RuntimeBuffer){0,64,0,legacy+0xa00};
 d.vertexBuffers[3]=(A5RuntimeBuffer){0,16,0,legacy+0xa40};
 d.fragmentBuffers[1]=(A5RuntimeBuffer){0,32,0,legacy+0xa80};
 d.fragmentBuffers[6]=(A5RuntimeBuffer){0,2,0,legacy+0xb00};
 assert(A5MaliEncodeRuntimeDraw(&d,output,sizeof(output))==A5RuntimeOK);
 for(unsigned i=0;i<4;++i){unsigned table=i<2?0x700:0x740,slot=i+1;
  pan_unpack((struct mali_uniform_buffer_packed*)(output+table+slot*8),UNIFORM_BUFFER,a);
  const unsigned off[4]={0xa00,0xa40,0xa80,0xb00},len[4]={64,16,32,2};
  assert(!memcmp(output+a.pointer-d.descriptorGPUVA,legacy+off[i],len[i]));
 }
 pan_unpack((struct mali_renderer_state_packed*)(output+0x500),RENDERER_STATE,vs);
 pan_unpack((struct mali_renderer_state_packed*)(legacy+0x500),RENDERER_STATE,oldvs);
 pan_unpack((struct mali_renderer_state_packed*)(output+0x540),RENDERER_STATE,fs);
 pan_unpack((struct mali_renderer_state_packed*)(legacy+0x540),RENDERER_STATE,oldfs);
 assert(vs.shader.attribute_count==oldvs.shader.attribute_count&&vs.shader.varying_count==oldvs.shader.varying_count);
 assert(fs.shader.varying_count==oldfs.shader.varying_count&&fs.properties.work_register_count==oldfs.properties.work_register_count);
 if(p->flags&A5MaliProfileFixedViewport)
  assert(!memcmp(output+0x2000,legacy+0x2000,p->passes[0].vertex.byteCount));
 else assert(!memcmp(output+0x2000,p->passes[0].vertex.bytes,p->passes[0].vertex.byteCount));
 assert(!memcmp(output+0x4000,legacy+0x3000,p->passes[0].fragment.byteCount));
 free(legacy);puts("PASS runtime vs device-passed32x32 payload: unchanged actual FS, MVP/texmat/filter/EDR and varying ABI; authenticated VS; dynamic addresses (no GPU claim)");
}
int main(int argc,char**argv){
 for(unsigned i=0;i<sizeof(vertex);++i)vertex[i]=(uint8_t)(i*7+3);
 for(unsigned i=0;i<sizeof(uniforms);++i)uniforms[i]=(uint8_t)(i*13+9);
 unsigned passed=0;
 for(unsigned i=0;i<sizeof(kA5MaliCompiledProfiles)/sizeof(kA5MaliCompiledProfiles[0]);++i){
  const A5MaliCompiledProfile*p=kA5MaliCompiledProfiles+i;if(p->profileID<99||p->profileID>108)continue;
  A5RuntimeDraw d=p->colorFormats[0]==115?request(p,64,128):request(p,1080,1920);
  int rc=A5MaliEncodeRuntimeDraw(&d,output,sizeof(output));if(rc){fprintf(stderr,"profile%u rc%d\n",p->profileID,rc);return 1;}
  pan_unpack((struct mali_framebuffer_parameters_packed*)(output+0x320),FRAMEBUFFER_PARAMETERS,fb);
  assert(fb.bound_max_x==d.destination.width-1&&fb.bound_max_y==d.destination.height-1&&fb.color_writeback.base==d.destination.gpuVA);
  pan_unpack((struct mali_attribute_buffer_packed*)(output+0x840),ATTRIBUTE_BUFFER,vb);
  assert(vb.pointer>=d.descriptorGPUVA+0xc000&&vb.pointer+192<=d.descriptorGPUVA+0x10000);
  assert(!memcmp(output+vb.pointer-d.descriptorGPUVA,vertex+17,192));
  pan_unpack((struct mali_uniform_buffer_packed*)(output+0x708),UNIFORM_BUFFER,ubo);
  assert(!memcmp(output+ubo.pointer-d.descriptorGPUVA,uniforms+31,64));
  pan_unpack((struct mali_tiler_context_packed*)(output+0x3c0),TILER_CONTEXT,t);
  assert(t.polygon_list_size==(d.destination.width==1080?0xa00:0x400)&&t.polygon_list_body==d.descriptorGPUVA+0x10200);
  d.vertexCount=256;assert(A5MaliEncodeRuntimeDraw(&d,output,sizeof(output))==A5RuntimeOK);
  d.vertexCount=4;d.blend=A5RuntimeBlendPremultipliedSourceOver;
  if(d.destination.metalPixelFormat==80){
   assert(A5MaliEncodeRuntimeDraw(&d,output,sizeof(output))==A5RuntimeOK);
   pan_unpack((struct mali_renderer_state_packed*)(output+0x540),RENDERER_STATE,rs);
   assert(rs.multisample_misc.load_destination);
   assert(rs.blend_equation.rgb.a==MALI_BLEND_OPERAND_A_SRC&&rs.blend_equation.rgb.b==MALI_BLEND_OPERAND_B_DEST&&rs.blend_equation.rgb.c==MALI_BLEND_OPERAND_C_SRC_ALPHA&&rs.blend_equation.rgb.invert_c);
   assert(rs.blend_equation.alpha.a==rs.blend_equation.rgb.a&&rs.blend_equation.alpha.b==rs.blend_equation.rgb.b&&rs.blend_equation.alpha.c==rs.blend_equation.rgb.c&&rs.blend_equation.alpha.invert_c);
  }else assert(A5MaliEncodeRuntimeDraw(&d,output,sizeof(output))==A5RuntimeUnsupported&&zero());
  d=request(p,64,128);assert(A5MaliEncodeRuntimeDraw(&d,output,sizeof(output))==A5RuntimeOK);
  d.viewportWidth=64;
  if(p->flags&A5MaliProfileFixedViewport)
   assert(A5MaliEncodeRuntimeDraw(&d,output,sizeof(output))==A5RuntimeUnsupported&&zero());
  else {
   /* Offscreen target requested by real QuartzCore, then nonzero origin and
    * depth range: inspect the exact UBO descriptors and all six scalar values. */
   d=request(p,776,24);d.viewportWidth=776;d.viewportHeight=24;
   assert(A5MaliEncodeRuntimeDraw(&d,output,sizeof(output))==A5RuntimeOK);
   pan_unpack((struct mali_uniform_buffer_packed*)(output+0x700),UNIFORM_BUFFER,sys);
   pan_unpack((struct mali_uniform_buffer_packed*)(output+0x740),UNIFORM_BUFFER,fsys);
   assert(sys.pointer==d.descriptorGPUVA+0x1000&&sys.entries==36);
   assert(fsys.pointer==d.descriptorGPUVA+0x1400&&sys.pointer+sys.entries*16<=fsys.pointer);
   float sc[3],of[3];memcpy(sc,output+0x1200,12);memcpy(of,output+0x1210,12);
   assert(sc[0]==388&&sc[1]==12&&sc[2]==.5f&&of[0]==388&&of[1]==12&&of[2]==.5f);
   d.viewportX=8;d.viewportY=4;d.viewportWidth=320;d.viewportHeight=16;d.viewportNear=.25;d.viewportFar=.75;
   assert(A5MaliEncodeRuntimeDraw(&d,output,sizeof(output))==A5RuntimeOK);
   memcpy(sc,output+0x1200,12);memcpy(of,output+0x1210,12);
   assert(sc[0]==160&&sc[1]==8&&sc[2]==.25f&&of[0]==168&&of[1]==12&&of[2]==.5f);
   d=request(p,1080,1920);assert(A5MaliEncodeRuntimeDraw(&d,output,sizeof(output))==A5RuntimeOK);
   memcpy(sc,output+0x1200,12);memcpy(of,output+0x1210,12);
   assert(sc[0]==540&&sc[1]==960&&sc[2]==.5f&&of[0]==540&&of[1]==960&&of[2]==.5f);
   d.viewportWidth=NAN;assert(A5MaliEncodeRuntimeDraw(&d,output,sizeof(output))==A5RuntimeUnsupported&&zero());
  }
  d=request(p,64,128);d.source.gpuVA=d.destination.gpuVA;
  assert(A5MaliEncodeRuntimeDraw(&d,output,sizeof(output))==A5RuntimeBounds&&zero());
  d=request(p,64,128);d.vertexBuffers[1].bytes=100;
  assert(A5MaliEncodeRuntimeDraw(&d,output,sizeof(output))==A5RuntimeBounds&&zero());
  d=request(p,64,128);d.vertexBuffers[1]=(A5RuntimeBuffer){0x23000000,65536,17,NULL};
  assert(A5MaliEncodeRuntimeDraw(&d,output,sizeof(output))==A5RuntimeOK);
  pan_unpack((struct mali_attribute_buffer_packed*)(output+0x840),ATTRIBUTE_BUFFER,privatevb);
  pan_unpack((struct mali_attribute_packed*)(output+0x800),ATTRIBUTE,privateattr);
  assert(privatevb.pointer==0x23000000&&privateattr.offset==17);
  ++passed;
 }
 if(argc==2)compare_legacy(argv[1]);
 assert(passed==10);printf("PASS %u actual compiled blur profiles: dynamic dimensions, CPU snapshots/private VA, source-over, offscreen/fullview viewport sysvals, bounds/invalid-viewport rejections (no GPU claim)\n",passed);
 return 0;
}
