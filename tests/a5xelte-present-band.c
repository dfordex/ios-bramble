/* Independent source/panel model and released Mesa v4 descriptor decoding. */
#define PAN_ARCH 4
#include "genxml/v4_pack.h"
#include A5_PRESENT_BAND_HEADER
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
static void apply(const uint8_t *source,unsigned stride,uint8_t *panel,unsigned width,A5PresentBand b){
 for(unsigned y=b.first;y<b.end;y++)memcpy(panel+(size_t)y*width*4,source+(size_t)y*stride,width*4);
}
static void bounds(A5PresentBand b,unsigned width,unsigned height){
 uint32_t viewport[8]={0},fragment[16]={0};
 assert(a5present_scissor(viewport,fragment,width,height,b));
 pan_unpack((const struct mali_viewport_packed*)viewport,VIEWPORT,v);
 pan_unpack((const struct mali_fragment_job_payload_packed*)(fragment+8),FRAGMENT_JOB_PAYLOAD,f);
 assert(v.scissor_minimum_x==0&&v.scissor_minimum_y==b.first);
 assert(v.scissor_maximum_x==width-1&&v.scissor_maximum_y==b.end-1);
 assert(f.bound_min_x==0&&f.bound_min_y==b.first/16);
 assert(f.bound_max_x==(width-1)/16&&f.bound_max_y==(b.end-1)/16);
}
int main(void){
 enum{W=1080,H=1920,STRIDE=4352,BYTES=W*H*4};
 uint8_t *source=calloc(H,STRIDE),*shadow=malloc(BYTES),*panel=malloc(BYTES);
 assert(source&&shadow&&panel);memset(panel,0xa5,BYTES);A5PresentBand b;
 assert(a5present_band(source,H*STRIDE,STRIDE,shadow,BYTES,W,H,false,&b));
 assert(!b.first&&b.end==H);bounds(b,W,H);apply(source,STRIDE,panel,W,b);
 a5present_remember(source,STRIDE,shadow,W,b);
 for(unsigned iteration=0;iteration<80;iteration++){
  assert(a5present_band(source,H*STRIDE,STRIDE,shadow,BYTES,W,H,true,&b)&&!b.end);
  unsigned y=iteration==0?0:iteration==1?H-1:(iteration*137)%H,x=(iteration*73)%W;
  source[y*STRIDE+x*4+(iteration%4)]^=0x7b;
  if(iteration%7==0)source[((y+23)%H)*STRIDE+17]^=0x83;
  assert(a5present_band(source,H*STRIDE,STRIDE,shadow,BYTES,W,H,true,&b));bounds(b,W,H);
  assert(b.first<=y&&b.end>y);apply(source,STRIDE,panel,W,b);
  a5present_remember(source,STRIDE,shadow,W,b);
  for(unsigned row=0;row<H;row++)assert(!memcmp(panel+(size_t)row*W*4,source+(size_t)row*STRIDE,W*4));
 }
 /* Source row padding never changes active pixels. Invalidation forces full copy. */
 source[W*4]^=1;
 assert(a5present_band(source,H*STRIDE,STRIDE,shadow,BYTES,W,H,true,&b)&&!b.end);
 assert(a5present_band(source,H*STRIDE,STRIDE,shadow,BYTES,W,H,false,&b)&&b.end==H);
 assert(!a5present_band(source,16,STRIDE,shadow,BYTES,W,H,true,&b));
 assert(!a5present_band(source,H*STRIDE,STRIDE,shadow,16,W,H,true,&b));
 uint32_t v[8],f[16];
 assert(!a5present_scissor(v,f,W,H,(A5PresentBand){1,16}));
 assert(!a5present_scissor(v,f,W,H,(A5PresentBand){0,H+16}));
 assert(!a5present_scissor(v,f,W,H,(A5PresentBand){0,0}));
 /* A changed final row retains an unaligned panel edge without a spill. */
 bounds((A5PresentBand){48,65},37,65);
 free(source);free(shadow);free(panel);
 puts("PASS exact bands: 80 transitions, full pixel equality, alpha, padding, invalidation, bounds and released v4 scissor/tile decode; no physical GPU claim");
}
