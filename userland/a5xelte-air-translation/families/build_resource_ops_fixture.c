/* SPDX-License-Identifier: MIT
 * GPU test inputs/oracles only. The production emitter never sees expected
 * pixels. Each payload has one real resource job and independent byte oracle.
 */
#define PAN_ARCH 4
#include "runtime_resource_ops.h"
#include "genxml/v4_pack.h"
#include "mip_linear_reference.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define BASE UINT64_C(0x02000000)
#define SOURCE 0x4000u
#define DEST 0x28000u
static unsigned size_for(unsigned f){switch(f){case 10:return 1;case 30:case 43:case 23:case 25:return 2;case 55:case 80:return 4;case 105:case 115:return 8;default:return 0;}}
static unsigned align16(unsigned n){return(n+15)&~15u;}
static int write_file(const char*p,const void*d,size_t n){FILE*f=fopen(p,"wb");return f&&fwrite(d,1,n,f)==n&&!fclose(f);}
static void source_pixel(unsigned char*p,unsigned n,unsigned x,unsigned y){
 /* Raw copies deliberately include sign/exponent/high integer bits; use
  * nontrivial byte patterns, not float-limited integer values. */
 for(unsigned c=0;c<n;c++)p[c]=(unsigned char)(x*73+y*113+c*47+((x>>3)*19));
}
int main(int argc,char**argv){
 /* format,type,width,height,partial,mip,payload,expected */
 if(argc!=9)return 2;unsigned fmt=atoi(argv[1]),type=atoi(argv[2]),w=atoi(argv[3]),h=atoi(argv[4]),partial=atoi(argv[5]),mip=atoi(argv[6]),n=size_for(fmt);
 if(!n||!w||!h||w>4096||h>4096||partial>1||mip>1)return 2;
 unsigned dw=mip?(w>1?w/2:1):w,dh=mip?(h>1?h/2:1):h;
 unsigned sr=align16(w*n),dr=align16(dw*n),sn=sr*h,dn=dr*dh;
 if(SOURCE+sn>0x10000||DEST+dn>0x38000)return 2;
 uint8_t*d=calloc(1,A5RuntimeJobBytes),*expected=malloc(dn),*src=malloc(sn);if(!d||!expected||!src)return 2;
 memset(src,0x7d,sn);memset(expected,0xa5,dn);
 for(unsigned y=0;y<h;y++)for(unsigned x=0;x<w;x++)source_pixel(src+y*sr+x*n,n,x,y);
 A5RuntimeResourceOp r={.descriptorGPUVA=BASE,.operation=mip?A5ResourceGenerateMip:A5ResourceCopy,
 .source={UINT64_C(0x04000000),sn,w,h,sr,fmt},.destination={UINT64_C(0x06000000),dn,dw,dh,dr,fmt},.sourceType=type,.destinationType=type,
 .sourceX=partial?3:0,.sourceY=(partial&&h>1)?1:0,.destinationX=partial?5:0,.destinationY=(partial&&h>1)?1:0,
 .width=partial?dw-9:dw,.height=partial&&h>2?dh-2:dh};
 if(A5MaliEncodeRuntimeResourceOp(&r,d,A5RuntimeJobBytes)){fprintf(stderr,"resource fixture encode rejected\n");return 2;}
 /* Fixture-only rebase into holes unused by the genuine descriptor. Runtime
  * correctly rejects arbitrary source/destination aliases of its job BO. */
 pan_unpack((struct mali_surface_with_stride_packed*)(d+0x620),SURFACE_WITH_STRIDE,source);
 source.pointer=BASE+SOURCE;MALI_SURFACE_WITH_STRIDE_pack((struct mali_surface_with_stride_packed*)(d+0x620),&source);
 pan_unpack((struct mali_framebuffer_parameters_packed*)(d+0x320),FRAMEBUFFER_PARAMETERS,fb);
 fb.color_writeback.base=BASE+DEST;fb.color_load_address=0;fb.color_load_row_stride=0;fb.color_load_surface_stride=0;
 fb.clear_color_0=fb.clear_color_1=fb.clear_color_2=fb.clear_color_3=0;
 MALI_FRAMEBUFFER_PARAMETERS_pack((struct mali_framebuffer_parameters_packed*)(d+0x320),&fb);
 if(partial){pan_unpack((struct mali_surface_with_stride_packed*)(d+0x19a0),SURFACE_WITH_STRIDE,preload);
 preload.pointer=BASE+DEST;MALI_SURFACE_WITH_STRIDE_pack((struct mali_surface_with_stride_packed*)(d+0x19a0),&preload);}
 memcpy(d+SOURCE,src,sn);memset(d+DEST,0xa5,dn);
 if(!mip){for(unsigned y=0;y<r.height;y++)memcpy(expected+(r.destinationY+y)*dr+r.destinationX*n,src+(r.sourceY+y)*sr+r.sourceX*n,r.width*n);}
 else{for(unsigned y=0;y<dh;y++)for(unsigned x=0;x<dw;x++)for(unsigned c=0;c<4;c++){
  expected[y*dr+x*4+c]=a5_mip_linear_channel(src,sr,w,h,dw,dh,x,y,c);
 }}
 int ok=write_file(argv[7],d,A5RuntimeJobBytes)&&write_file(argv[8],expected,dn);
 printf("format=%u type=%u width=%u height=%u source_offset=%u source_bytes=%u output_offset=%u output_bytes=%u row_bytes=%u mip=%u partial=%u\n",fmt,type,w,h,SOURCE,sn,DEST,dn,dr,mip,partial);
 free(d);free(src);free(expected);return !ok;
}
