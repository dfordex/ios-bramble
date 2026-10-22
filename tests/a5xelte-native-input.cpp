// Execute the actual kernel native-client entry points with a strict descriptor.
// readBytes deliberately aborts unless prepared, reproducing the 0192 defect.
#include <cassert>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>
#include "native_abi.h"
using IOReturn=int; using IOByteCount=uint64_t;
enum { kIOReturnSuccess=0,kIOReturnUnsupported=1,kIOReturnBadArgument=2,
 kIOReturnNoMemory=3,kIOReturnNotOpen=4,kIOReturnNotFound=5,
 kIOReturnNoResources=6,kIOReturnNotReady=7,kIOReturnIOError=8,
 kIOReturnUnderrun=9,kIODirectionOut=2,kIOMemoryIncoherentIOStore=10,
 kA5GPUClientMaxResources=4,kA5GPUClientRead=1,kA5GPUClientWrite=2 };
using A5GPUClientHeader=A5NativeHeader;
static int allocations,locks,submissions; static bool failAllocation;
struct IOMemoryDescriptor;
static IOMemoryDescriptor *callerDescriptor;
struct IOMemoryDescriptor {
 std::vector<uint8_t> data;
 int prepares=0,reads=0,completes=0,wires=0,writes=0,stores=0;
 IOReturn prepareResult=0,completeResult=0;
 bool shortRead=false,mutateOnComplete=false;
 explicit IOMemoryDescriptor(const std::vector<uint8_t>&v):data(v){}
 uint64_t getLength(){return data.size();}
 IOReturn prepare(int direction){assert(direction==kIODirectionOut);++prepares;
  if(!prepareResult)++wires; return prepareResult;}
 uint64_t readBytes(uint64_t offset,void*out,uint64_t bytes){
  assert(wires>0); assert(offset+bytes<=data.size()); ++reads;
  uint64_t copied=bytes-(shortRead?1:0); memcpy(out,data.data()+offset,copied);return copied;}
 IOReturn complete(int direction){assert(direction==kIODirectionOut && wires>0);
  ++completes;--wires;
  if(mutateOnComplete)memset(data.data(),0xdd,data.size()); return completeResult;}
 uint64_t writeBytes(uint64_t offset,const void*input,uint64_t bytes){
  assert(!callerDescriptor || !callerDescriptor->wires);
  assert(offset+bytes<=data.size());++writes;memcpy(data.data()+offset,input,bytes);return bytes;}
 IOReturn performOperation(int operation,uint64_t,uint64_t){
  assert(operation==kIOMemoryIncoherentIOStore);++stores;return 0;}
};
using IOBufferMemoryDescriptor=IOMemoryDescriptor;
void* IOMallocData(uint64_t bytes){if(failAllocation)return nullptr;++allocations;return malloc(bytes);}
void IOFreeData(void*p,uint64_t){assert(p && allocations>0);--allocations;free(p);}
void IOLockLock(void*){++locks;} void IOLockUnlock(void*){assert(locks>0);--locks;}
struct IOExternalMethodArguments {
 uint32_t scalarInputCount=0,scalarOutputCount=0;
 const void*structureInput=nullptr;uint64_t structureInputSize=0;
 void*structureOutput=nullptr;uint64_t structureOutputSize=0;
 IOMemoryDescriptor *structureInputDescriptor=nullptr,*structureOutputDescriptor=nullptr;
};
struct A5G3DAS1Context{};
struct A5G3DAS1Completion{uint64_t tilerFence,fragmentFence;};
static bool a5g3d_as1_native_available(){return true;}
static bool a5gpu_valid_header(A5GPUClientHeader*h,uint64_t bytes){
 return h->version==1 && h->size==bytes && !h->reserved0 && !h->reserved1;}
static bool a5gpu_valid_input(IOExternalMethodArguments*a,uint64_t bytes){
 return a && a->structureInput && a->structureInputSize==bytes;}
static bool a5gpu_buffer_token_slot(uint64_t token,uint32_t*slot){
 if(static_cast<uint32_t>(token)!=0x80000001u)return false;*slot=0;return true;}
static bool a5g3d_as1_map_buffer(A5G3DAS1Context*,uint32_t,IOBufferMemoryDescriptor*,uint32_t){return true;}
static bool a5g3d_as1_native_span(A5G3DAS1Context*,uint32_t,bool,A5NativeSpan*out){out->bytes=4096;return true;}
static uint32_t a5g3d_as1_submit_native(A5G3DAS1Context*,const A5NativeSubmitRequest&r,
 const uint8_t*input,uint32_t,uint32_t,uint32_t,A5G3DAS1Completion*out){
 assert(!callerDescriptor || !callerDescriptor->wires);
 assert(r.jobBytes==A5NativeJobBytes && input[0]==0x5a && input[r.jobBytes-1]==0x5a);
 ++submissions;out->tilerFence=0;out->fragmentFence=1;return 0;
}
struct A5XELTEGPUUserClient {
 struct ResourceSlot { struct {void*surface=nullptr;}surface;
  bool mapped=false;uint32_t generation=1,usage=3,mappingSlot=0;};
 struct BufferSlot { IOBufferMemoryDescriptor*buffer=nullptr;
  bool mapped=false;uint32_t generation=1,usage=3,bytes=0;};
 bool fClosed=false;A5G3DAS1Context context,*fAS1=&context;
 void*fLock=nullptr;uint32_t fMappingEpoch=1;
 ResourceSlot fSlots[4];BufferSlot fBuffers[4];
 A5XELTEGPUUserClient(){fSlots[0].surface.surface=this;fSlots[0].mapped=true;}
 bool ensureSurfaceMappingLocked(uint32_t,uint32_t){return true;}
 IOReturn nativeTokensLocked(const uint64_t*,const uint64_t*,A5NativeQueryResult*,
  uint32_t,uint32_t,uint32_t,uint32_t*,uint32_t*,uint32_t*);
 IOReturn nativeQuery(IOExternalMethodArguments*);
 IOReturn nativeSubmit(IOExternalMethodArguments*);
 IOReturn nativeBulkWrite(IOExternalMethodArguments*);
};
#include A5_KERNEL_NATIVE_CLIENT
static std::vector<uint8_t> submission(){
 std::vector<uint8_t> v(sizeof(A5NativeSubmitRequest)+A5NativeJobBytes,0x5a);
 A5NativeSubmitRequest r={};r.header={1,sizeof(r),0,0};r.jobBytes=A5NativeJobBytes;
 r.profileID=0;r.mappingEpoch=1;r.writeSurfaces=1;r.surfaces[0]=(1ULL<<32)|1;
 memcpy(v.data(),&r,sizeof(r));return v;
}
static std::vector<uint8_t> bulk(){
 std::vector<uint8_t> v(sizeof(A5NativeBulkWriteRequest)+8192,0xa7);
 A5NativeBulkWriteRequest r={};r.header={1,static_cast<uint32_t>(v.size()),0,0};
 r.handle=(1ULL<<32)|0x80000001u;r.offset=17;r.length=8192;
 memcpy(v.data(),&r,sizeof(r));return v;
}
static void run(bool upload,int fault){
 assert(!allocations && !locks);submissions=0;
 auto bytes=upload?bulk():submission();IOMemoryDescriptor md(bytes);
 IOBufferMemoryDescriptor backing(std::vector<uint8_t>(16384));
 A5XELTEGPUUserClient client;client.fBuffers[0].buffer=&backing;
 client.fBuffers[0].bytes=backing.data.size();
 A5NativeSubmitResult output={};IOExternalMethodArguments args;
 args.structureInputDescriptor=&md;
 if(!upload){args.structureOutput=&output;args.structureOutputSize=sizeof(output);}
 if(fault==1)md.prepareResult=71;
 if(fault==2)md.shortRead=true;
 if(fault==3)md.completeResult=72;
 if(fault==4)md.data[0]=0; // invalid ABI after a successful snapshot
 if(fault==5)md.data.pop_back(); // invalid outer size for submit, invalid length for bulk
 if(fault==6)failAllocation=true;
 if(fault==7)md.mutateOnComplete=true; // GPU/backing must consume owned snapshot
 if(fault==8){args.structureInputDescriptor=nullptr;args.structureInput=bytes.data();
  args.structureInputSize=bytes.size();}
 callerDescriptor=&md;
 int kr=upload?client.nativeBulkWrite(&args):client.nativeSubmit(&args);
 failAllocation=false;callerDescriptor=nullptr;
 int expected=fault==1?71:fault==2?kIOReturnUnderrun:fault==3?72:
  (fault==4 || fault==5)?kIOReturnBadArgument:fault==6?kIOReturnNoMemory:0;
 assert(kr==expected);assert(!allocations && !locks && !md.wires);
 bool entered=fault!=6 && fault!=8 && !(fault==5 && !upload);
 assert(md.prepares==(entered?1:0));
 assert(md.reads==(entered && fault!=1?1:0));
 assert(md.completes==(entered && fault!=1?1:0));
 if(expected){assert(!submissions && !backing.writes && !backing.stores);}
 else if(upload){assert(!submissions && backing.writes==1 && backing.stores==1);
  assert(backing.data[16]==0 && backing.data[17]==0xa7 && backing.data[8208]==0xa7 && backing.data[8209]==0);}
 else {assert(submissions==1 && output.fragmentFence==1 && !backing.writes);}
}
int main(){for(bool upload:{false,true})for(int fault=0;fault<=8;++fault)run(upload,fault);
 puts("PASS: actual nativeSubmit/nativeBulkWrite; 18 lifecycle/failure/snapshot/inline cases");}
