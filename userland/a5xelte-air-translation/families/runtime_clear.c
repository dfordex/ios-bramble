/* SPDX-License-Identifier: MIT
 * Released Mesa26.2.4 pan_clear.c pan_pack_color/pan_pack_raw semantics and
 * pan_desc.c v4 pan_emit_fbd + disabled flat T720 tiler context.
 */
#define PAN_ARCH 4
#include "runtime_clear.h"
#include <math.h>
#include <string.h>
#include "genxml/v4_pack.h"
enum { FB=0x300,POLY=0x1000,BODY=0x1200 };
static unsigned pixel_bytes(unsigned format){return format==80||format==55?4:format==10?1:format==30?2:format==115?8:0;}
static uint32_t unorm(double x){
 float v=(float)(x<0?0:x>1?1:x)*255.0f;uint32_t n=(uint32_t)v;float rem=v-(float)n;
 return n+(rem>.5f||(rem==.5f&&(n&1)));
}
static uint32_t float_bits(float f){uint32_t v;memcpy(&v,&f,4);return v;}
static uint16_t half_bits(double x){_Float16 h=(_Float16)(float)x;uint16_t bits;memcpy(&bits,&h,2);return bits;}
static int encode(const A5RuntimeClear*r,uint8_t*d){
 const A5RuntimeImage*i=&r->destination;unsigned bytes=pixel_bytes(i->metalPixelFormat);
 uint64_t limit=UINT64_C(1)<<40;
 if(!bytes)return A5RuntimeUnsupported;
 if(!r->descriptorGPUVA||(r->descriptorGPUVA&4095)||r->descriptorGPUVA>limit-A5RuntimeJobBytes||
    !i->gpuVA||(i->gpuVA&63)||!i->bytes||i->gpuVA>=limit||i->bytes>limit-i->gpuVA||
    !i->width||i->width>2048||!i->height||i->height>2048||
    i->rowBytes<i->width*bytes||(i->rowBytes&15)||(uint64_t)i->rowBytes*i->height>i->bytes||
    (i->gpuVA<r->descriptorGPUVA+A5RuntimeJobBytes&&r->descriptorGPUVA<i->gpuVA+i->bytes))return A5RuntimeBounds;
 for(unsigned c=0;c<4;++c)if(!isfinite(r->color[c]))return A5RuntimeUnsupported;
 uint32_t words[4];unsigned raw=i->metalPixelFormat==55||i->metalPixelFormat==115;
 if(i->metalPixelFormat==55){uint32_t w=float_bits((float)r->color[0]);for(unsigned c=0;c<4;++c)words[c]=w;}
 else if(i->metalPixelFormat==115){
  words[0]=(uint32_t)half_bits(r->color[0])|((uint32_t)half_bits(r->color[1])<<16);
  words[1]=(uint32_t)half_bits(r->color[2])|((uint32_t)half_bits(r->color[3])<<16);
  words[2]=words[0];words[3]=words[1];
 }else{
  unsigned a=i->metalPixelFormat==80?unorm(r->color[3]):255;
  uint32_t w=unorm(r->color[0])|(unorm(r->color[1])<<8)|(unorm(r->color[2])<<16)|(a<<24);
  for(unsigned c=0;c<4;++c)words[c]=w;
 }
 pan_section_pack(d+FB,FRAMEBUFFER,LOCAL_STORAGE,c){c.wls_instances=MALI_LOCAL_STORAGE_NO_WORKGROUP_MEM;}
 pan_section_pack(d+FB,FRAMEBUFFER,PARAMETERS,c){
  c.bound_max_x=i->width-1;c.bound_max_y=i->height-1;
  c.internal_format=raw?MALI_COLOR_BUFFER_INTERNAL_FORMAT_RAW_VALUE:MALI_COLOR_BUFFER_INTERNAL_FORMAT_R8G8B8A8;
  c.color_writeback_format=i->metalPixelFormat==55?MALI_COLOR_FORMAT_1_32B_CHANNEL:
    i->metalPixelFormat==115?MALI_COLOR_FORMAT_2_32B_CHANNELS:
    i->metalPixelFormat==10?MALI_COLOR_FORMAT_R8:i->metalPixelFormat==30?MALI_COLOR_FORMAT_R8G8:MALI_COLOR_FORMAT_R8G8B8A8;
  c.swizzle=i->metalPixelFormat==80?0x60a:0x688;c.color_block_format=MALI_BLOCK_FORMAT_LINEAR;
  c.color_write_enable=true;c.clean_pixel_write_enable=true;c.color_preload_enable=false;
  c.tie_break_rule=MALI_TIE_BREAK_RULE_MINUS_180_IN_0_OUT;
  c.color_writeback.base=i->gpuVA;c.color_writeback.row_stride=i->rowBytes;
  c.clear_color_0=words[0];c.clear_color_1=words[1];c.clear_color_2=words[2];c.clear_color_3=words[3];
 }
 /* No vertex/tiler jobs: released pan_emit_midgard_tiler(disable=true),
  * flat(nohierarchy) minimumheader+4 and the actual T720 empty-list marker. */
 pan_section_pack(d+FB,FRAMEBUFFER,TILER,c){
  c.hierarchy_mask=MALI_MIDGARD_TILER_USER;c.polygon_list=r->descriptorGPUVA+POLY;
  c.polygon_list_body=r->descriptorGPUVA+BODY;c.polygon_list_size=MALI_MIDGARD_TILER_MINIMUM_HEADER_SIZE+4;
  c.heap_start=r->descriptorGPUVA+POLY;c.heap_end=c.heap_start;
 }
 uint32_t marker=0xa0000000;memcpy(d+BODY,&marker,4);
 pan_pack((struct mali_job_header_packed*)d,JOB_HEADER,c){c.type=MALI_JOB_TYPE_FRAGMENT;c.index=1;c.enable_texture_mapper=true;}
 pan_pack((struct mali_fragment_job_payload_packed*)(d+32),FRAGMENT_JOB_PAYLOAD,c){c.bound_max_x=(i->width-1)/16;c.bound_max_y=(i->height-1)/16;c.framebuffer=r->descriptorGPUVA+FB;}
 return A5RuntimeOK;
}
int A5MaliEncodeRuntimeClear(const A5RuntimeClear*r,void*out,size_t n){
 if(!out||n!=A5RuntimeJobBytes)return A5RuntimeInvalid;memset(out,0,n);
 int rc=r?encode(r,out):A5RuntimeInvalid;if(rc)memset(out,0,n);return rc;
}
