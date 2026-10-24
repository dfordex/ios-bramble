/* SPDX-License-Identifier: MIT
 * Independent packed-source oracle against unmodified released Mesa unpack.
 * This validates the future GPU oracle's channel/alpha/row arithmetic, not GPU
 * execution. Production never calls this decoder or converts source pixels.
 */
#include "util/format/u_format.h"
#include <assert.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static double direct(uint16_t p,unsigned c){
 switch(c){case 0:return ((p>>10)&31)/31.;case 1:return ((p>>5)&31)/31.;
  case 2:return (p&31)/31.;default:return (p>>15)&1;}
}
static int clamp(int v,int n){return v<0?0:v>=n?n-1:v;}
int main(void){
 uint16_t values[65536];float rgba[65536*4];
 for(unsigned i=0;i<65536;++i)values[i]=(uint16_t)i;
 util_format_unpack_rgba(PIPE_FORMAT_B5G5R5A1_UNORM,rgba,values,65536);
 for(unsigned i=0;i<65536;++i)for(unsigned c=0;c<4;++c)
  assert(fabs(rgba[i*4+c]-direct((uint16_t)i,c))<1e-7);
 enum {W=542,H=963,ROW=1088};uint8_t*packed=malloc(ROW*H);float*plane=malloc(W*H*4*sizeof(float));
 assert(packed&&plane);memset(packed,0xa5,ROW*H);
 for(unsigned y=0;y<H;++y){for(unsigned x=0;x<W;++x){
  uint16_t p=(uint16_t)((x*97+y*1337)&65535);memcpy(packed+y*ROW+x*2,&p,2);
 }util_format_unpack_rgba(PIPE_FORMAT_B5G5R5A1_UNORM,plane+y*W*4,packed+y*ROW,W);}
 const double coords[][2]={{-.25,.25},{.5,.5},{.75,1.25},{541.25,962.75},{542.5,963.5},{271.375,481.625}};
 for(unsigned i=0;i<sizeof(coords)/sizeof(coords[0]);++i){
  double sx=coords[i][0]-.5,sy=coords[i][1]-.5;int bx=(int)floor(sx),by=(int)floor(sy);
  double fx=sx-bx,fy=sy-by;
  for(unsigned c=0;c<4;++c){double reference=0,actual=0;
   for(int dy=0;dy<2;++dy)for(int dx=0;dx<2;++dx){
    unsigned x=clamp(bx+dx,W),y=clamp(by+dy,H);double weight=(dx?fx:1-fx)*(dy?fy:1-fy);
    uint16_t p;memcpy(&p,packed+y*ROW+x*2,2);
    reference+=plane[(y*W+x)*4+c]*weight;actual+=direct(p,c)*weight;
   }assert(fabs(reference-actual)<1e-7);
  }
 }
 for(unsigned y=0;y<H;++y)for(unsigned x=W*2;x<ROW;++x)assert(packed[y*ROW+x]==0xa5);
 free(plane);free(packed);
 puts("PASS65536 packed BGR5A1 values against released Mesa RGBA unpack; 542x963/1088 row, alpha0/1, fractional linear sampling and edge clamps; no GPU execution claim");
 return 0;
}
