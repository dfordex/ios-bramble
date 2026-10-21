/* SPDX-License-Identifier: MIT
 * RAM-only genuine Mac Metal reference: no phone connection or disk image.
 */
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <stdio.h>
#include <stdlib.h>
int main(int argc,char**argv){@autoreleasepool{
 if(argc!=2)return 2;id<MTLDevice>d=MTLCreateSystemDefaultDevice();if(!d){fputs("NO_METAL_DEVICE\n",stderr);return 3;}
 printf("device=%s\n",d.name.UTF8String);id<MTLCommandQueue>q=[d newCommandQueue];if(!q)return 4;
 unsigned shapes[][2]={{3,1},{97,3},{776,24},{65,5},{64,32},{1,3}};
 for(unsigned c=0;c<6;c++){
 unsigned w=shapes[c][0],h=shapes[c][1],levels=1;for(unsigned x=w>h?w:h;x>1;x>>=1)levels++;
 MTLTextureDescriptor*desc=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:w height:h mipmapped:YES];desc.storageMode=MTLStorageModeShared;desc.usage=MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite;
 id<MTLTexture>t=[d newTextureWithDescriptor:desc];if(!t)return 5;
 unsigned char*in=malloc(w*h*4);for(unsigned y=0;y<h;y++)for(unsigned x=0;x<w;x++)for(unsigned k=0;k<4;k++)in[(y*w+x)*4+k]=(unsigned char)(x*73+y*113+k*47+((x>>3)*19));
 if(c==0){for(unsigned x=0;x<3;x++)for(unsigned k=0;k<4;k++)in[x*4+k]=x==1?255:0;}
 [t replaceRegion:MTLRegionMake2D(0,0,w,h) mipmapLevel:0 withBytes:in bytesPerRow:w*4];
 NSString*src=[NSString stringWithFormat:@"%s/%ux%u-level0.bin",argv[1],w,h];[[NSData dataWithBytes:in length:w*h*4]writeToFile:src atomically:YES];free(in);
 id<MTLCommandBuffer>cb=[q commandBuffer];id<MTLBlitCommandEncoder>b=[cb blitCommandEncoder];[b generateMipmapsForTexture:t];[b endEncoding];[cb commit];[cb waitUntilCompleted];
 if(cb.status!=MTLCommandBufferStatusCompleted){fprintf(stderr,"MTL status=%lu error=%s\n",(unsigned long)cb.status,cb.error.description.UTF8String);return 6;}
 for(unsigned l=1;l<levels;l++){unsigned lw=w>>l,lh=h>>l;if(!lw)lw=1;if(!lh)lh=1;unsigned char*out=calloc(lw*lh,4);[t getBytes:out bytesPerRow:lw*4 fromRegion:MTLRegionMake2D(0,0,lw,lh) mipmapLevel:l];
 NSString*name=[NSString stringWithFormat:@"%s/%ux%u-level%u.bin",argv[1],w,h,l];[[NSData dataWithBytes:out length:lw*lh*4]writeToFile:name atomically:YES];printf("shape=%ux%u level=%u size=%ux%u first=%u,%u,%u,%u\n",w,h,l,lw,lh,out[0],out[1],out[2],out[3]);free(out);}
 }
 return 0;
}}
