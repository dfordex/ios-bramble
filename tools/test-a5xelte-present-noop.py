#!/usr/bin/env python3
"""Execute the actual framebuffer fallback tail: no-op must preserve shadow."""
import argparse,subprocess
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--kernel-source',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();a.output.mkdir(exist_ok=False)
s=(a.kernel_source/'iokit/Kernel/arm/SweetFramebuffer.cpp').read_text();start=s.index('\tfor (uint32_t layer = 0; layer < SWEET_FB_LAYERS; layer++) {',s.index('a5g3d_frame_present(s,'));start=s.rfind('\n#endif\n\n',0,start)+len('\n#endif\n\n');end=s.index('\n\treturn copied;',start)+len('\n\treturn copied;');body=s[start:end]
preamble=r'''
#include <cassert>
#include <cstdint>
#include <cstdio>
#include <cstring>
#define ARM64_BOARD_CONFIG_A5XELTE 1
#define SWEET_FB_LAYERS 4
static unsigned invalidations,sweet_fb_swaps_logged=16;
static void a5g3d_frame_present_invalidate(){++invalidations;}
static void a5g3d_resource_probe_swap(unsigned){}
template<class...T>static void IOLog(const char*,T...){}
struct Memory{unsigned length;unsigned getLength(){return length;}};
struct SweetSurface{uint32_t id=1,width=16,height=16,pixelFormat=0x42475241,bytesPerRow=64,offset=0,bytesPerElement=4,elementWidth=1,elementHeight=1;Memory*memory;uint32_t*pixels;uintptr_t kernelAddress(){return (uintptr_t)pixels;}void release(){}};
static SweetSurface*surfaces[3];static SweetSurface*sweet_surface_copy(unsigned id){return id<3?surfaces[id]:nullptr;}
#define OSSafeReleaseNULL(p) do{if(p)(p)->release();p=nullptr;}while(0)
static uint32_t get32(const uint8_t*p,unsigned n){uint32_t v;memcpy(&v,p+n,4);return v;}
struct Frame{unsigned fWidth=16,fHeight=16,fOffX=0,fOffY=0,fRowBytes=64;uintptr_t fPixels;SweetSurface*fSurface;bool fPerfLog=true;uint64_t fPerfCPUFrames=0,fPerfCPUBytes=0;
uint64_t presentCPU(const uint8_t*rec,bool*complete){uint32_t mask=get32(rec,0x104);uint64_t copied=0;
'''
main=r'''
}};
int main(){uint32_t panel[256]={},input[256];for(unsigned i=0;i<256;i++)input[i]=0xff000000|i;
 Memory pm{1024},im{1024};SweetSurface physical{},source{};physical.id=1;physical.memory=&pm;physical.pixels=panel;source.id=2;source.memory=&im;source.pixels=input;surfaces[1]=&physical;surfaces[2]=&source;Frame fb;fb.fPixels=(uintptr_t)panel;fb.fSurface=&physical;
 uint8_t rec[512]={};auto put=[&](unsigned at,uint32_t v){memcpy(rec+at,&v,4);};put(0x104,1);put(0x54,1);put(0x64+8,16);put(0x64+12,16);put(0xc4+8,16);put(0xc4+12,16);bool complete=true;
 assert(!fb.presentCPU(rec,&complete)&&!invalidations&&complete); /* framebuffer->itself */
 put(0x54,0);assert(!fb.presentCPU(rec,&complete)&&!invalidations&&complete);
 put(0x54,2);assert(fb.presentCPU(rec,&complete)==1024&&invalidations==1&&complete&&!memcmp(panel,input,1024));
 invalidations=0;im.length=1;assert(!fb.presentCPU(rec,&complete)&&!invalidations&&!complete);
 puts("PASS actual framebuffer fallback: self/empty no-op preserves cache; real CPU mutation invalidates; invalid allocation never copies");}
'''
f=a.output/'test.cpp';f.write_text(preamble+body+main);exe=a.output/'test';subprocess.run(['clang++','-std=c++17','-Wall','-Wextra','-Werror','-fsanitize=address,undefined',str(f),'-o',str(exe)],check=True);subprocess.run([str(exe)],check=True)
