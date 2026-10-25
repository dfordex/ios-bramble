#!/usr/bin/env python3
"""Exercise actual backing validation/Map4/Query token code with no GPU MMIO."""
from pathlib import Path
import argparse,subprocess,tempfile
p=argparse.ArgumentParser(description=__doc__);p.add_argument('kernel',type=Path);a=p.parse_args();arm=a.kernel/'iokit/Kernel/arm'
def function(s,signature):
 start=s.index(signature);b=s.index('{',start);depth=1;i=b+1
 while depth:
  depth+=(s[i]=='{')-(s[i]=='}');i+=1
 return s[start:i]+'\n'
s=(arm/'A5XELTEGPUAS1.cpp').read_text();r=(arm/'A5XELTEGPUResources.h').read_text();h=r[r.index('static inline uint32_t a5g3d_resource_format_bytes'):r.index('/* A retained IOSurface.')]
helpers='\n'.join(function(s,sig)for sig in ['static bool\na5g3d_as1_surface_valid(','static bool\na5g3d_as1_pages_valid(','bool\na5g3d_as1_surface_backing_valid('])
mapcode=function((arm/'A5XELTEGPUUserClient.cpp').read_text(),'IOReturn\nA5XELTEGPUUserClient::mapSurface(')
tokens=function((arm/'A5XELTENativeClient.inc').read_text(),'IOReturn A5XELTEGPUUserClient::nativeTokensLocked(')
stub=r'''
#include <cstdint>
#include <cassert>
#include <cstring>
template<class...T>static void IOLog(const char*,T...){ }
using IOReturn=int;using IOByteCount=uint64_t;
enum {kAS1Page=4096,kAS1Window=0x2000000,kIOMemoryMapperNone=0,kIOReturnSuccess=0,kIOReturnBadArgument=1,kIOReturnUnsupported=2,kIOReturnNoResources=3,kIOReturnNotOpen=4,kIOReturnNoMemory=5,kIOReturnNotFound=6,kIOReturnNotReady=7,kA5GPUClientMaxResources=128,kA5GPUClientRead=1,kA5GPUClientWrite=2};
struct Memory {virtual ~Memory()=default;uint64_t length=2351104,physical=0x81000000;int badPage=-1;
 uint64_t getLength(){return length;}uint64_t getPhysicalSegment(uint64_t off,IOByteCount*span,int){*span=length-off;return badPage==int(off/4096)?0:physical+off;}};
struct IOBufferMemoryDescriptor:Memory{};
#define OSDynamicCast(type,pointer) dynamic_cast<type*>(pointer)
struct SweetSurface {Memory*memory;uint32_t offset=0,planeCount=0,elementWidth=1,elementHeight=1,pixelFormat=0x42475241,bytesPerElement=4,width=1200,height=489,bytesPerRow=4800;uint64_t allocSize=2351104;};
struct A5GPUClientHeader{uint32_t version=1,size=0,reserved0=0,reserved1=0;};
struct A5GPUClientMapRequest{A5GPUClientHeader header;uint64_t handle;};
struct A5GPUClientMapResult{A5GPUClientHeader header;uint64_t mappingToken;uint32_t mappedBytes,flags;};
struct IOExternalMethodArguments{void*structureInput;uint64_t structureInputSize;void*structureOutput;uint64_t structureOutputSize;};
static bool a5gpu_valid_input(IOExternalMethodArguments*a,uint64_t n){return a&&a->structureInput&&a->structureInputSize==n;}
static bool a5gpu_valid_header(A5GPUClientHeader*h,uint64_t n){return h->version==1&&h->size==n&&!h->reserved0&&!h->reserved1;}
static int lockDepth,creates,mappings;static bool failCreate;
static void IOLockLock(void*){assert(!lockDepth++);}static void IOLockUnlock(void*){assert(--lockDepth==0);}
struct A5G3DAS1Context{};static A5G3DAS1Context context;
static A5G3DAS1Context*a5g3d_as1_create(){creates++;return failCreate?nullptr:&context;}
struct A5NativeSpan{uint64_t token=0,gpuVA=0;uint32_t bytes=0,width=0,height=0,rowBytes=0,pixelFormat=0,usage=0;};
struct A5NativeQueryResult{A5NativeSpan surfaces[4],buffers[4];};
static bool a5gpu_buffer_token_slot(uint64_t,uint32_t*){return false;}
static bool a5g3d_as1_native_span(A5G3DAS1Context*,uint32_t slot,bool,A5NativeSpan*out){out->gpuVA=0x10000000+slot*0x2000000;return true;}
static bool a5g3d_as1_map_buffer(A5G3DAS1Context*,uint32_t,IOBufferMemoryDescriptor*,uint32_t){return true;}
struct A5XELTEGPUUserClient {
 struct ResourceSlot{struct {SweetSurface*surface=nullptr;}surface;bool mapped=false;uint32_t generation=1,usage=3,mappingSlot=0;}fSlots[128];
 struct BufferSlot{IOBufferMemoryDescriptor*buffer=nullptr;bool mapped=false;uint32_t generation=1,usage=3,bytes=0;}fBuffers[4];
 bool fClosed=false;void*fLock=nullptr;A5G3DAS1Context*fAS1=nullptr;uint32_t fMappingEpoch=1;
 bool ensureSurfaceMappingLocked(uint32_t slot,const A5GPUProtectedResources&protectedSlots){assert(lockDepth==1&&fAS1&&a5gpu_resource_is_protected(protectedSlots,slot));mappings++;fSlots[slot].mapped=true;return true;}
 IOReturn mapSurface(IOExternalMethodArguments*);
 IOReturn nativeTokensLocked(const uint64_t*,const uint64_t*,A5NativeQueryResult*,uint32_t,uint32_t,uint32_t,uint32_t*,uint32_t*,uint32_t*);
};
'''
main=r'''
int main(){IOBufferMemoryDescriptor memory;SweetSurface surface{&memory};uint32_t bytes=0;
 assert(a5g3d_as1_surface_backing_valid(&surface,&bytes)&&bytes==2351104);
 memory.badPage=572;assert(!a5g3d_as1_surface_backing_valid(&surface,&bytes));memory.badPage=-1;
 memory.physical=0x67000000;assert(!a5g3d_as1_surface_backing_valid(&surface,&bytes));memory.physical=0x81000000;
 surface.allocSize=2347199;assert(!a5g3d_as1_surface_backing_valid(&surface,&bytes));surface.allocSize=2351104;
 A5XELTEGPUUserClient client;client.fSlots[114].surface.surface=&surface;
 A5GPUClientMapRequest request{{1,sizeof(request),0,0},(1ULL<<32)|115};A5GPUClientMapResult result{};
 IOExternalMethodArguments args{&request,sizeof(request),&result,sizeof(result)};
 assert(client.mapSurface(&args)==0&&result.mappedBytes==2351104&&result.mappingToken==request.handle);
 assert(!creates&&!mappings&&!client.fAS1&&!client.fSlots[114].mapped); // busy GPU never touched
 request.handle=(2ULL<<32)|115;assert(client.mapSurface(&args)==kIOReturnNoResources);request.handle=(1ULL<<32)|115;
 uint64_t surfaces[4]={request.handle,0,0,0},buffers[4]={};A5NativeQueryResult query{};
 IOLockLock(nullptr);assert(client.nativeTokensLocked(surfaces,buffers,&query,0,0,0,nullptr,nullptr,nullptr)==0);IOLockUnlock(nullptr);
 assert(creates==1&&mappings==1&&client.fSlots[114].mapped&&query.surfaces[0].gpuVA);
 A5XELTEGPUUserClient noMemory;failCreate=true;IOLockLock(nullptr);assert(noMemory.nativeTokensLocked(surfaces,buffers,&query,0,0,0,nullptr,nullptr,nullptr)==kIOReturnNoMemory);IOLockUnlock(nullptr);failCreate=false;
 A5XELTEGPUUserClient closed;closed.fClosed=true;assert(closed.mapSurface(&args)==kIOReturnNoResources);assert(!lockDepth);
}
'''
with tempfile.TemporaryDirectory(prefix='a5-lazy-map-',dir='/private/tmp')as tmp:
 d=Path(tmp);(d/'test.cpp').write_text('#include <cstdint>\n'+h+'\n'+(arm/'A5XELTEGPUResourceSlots.h').read_text()+'\n'+stub+helpers+mapcode+tokens+main)
 subprocess.run(['clang++','-std=c++17','-Wall','-Wextra','-Werror','-fsanitize=address,undefined',str(d/'test.cpp'),'-o',str(d/'test')],check=True);subprocess.run([str(d/'test')],check=True)
print('PASS actual pinned backing, busy-GPU-independent Map4, stale/closed/invalid pages, first Query mapping and allocation failure (host ASan/UBSan)')
