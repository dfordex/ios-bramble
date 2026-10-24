/* Host-only test of the actual kernel logical allocator/protected-set helper. */
#include "A5XELTEGPUResourceSlots.h"
#include "A5XELTEGPUUserClient.h"
#include <cassert>
#include <cstdint>
struct TestSlot {struct {void *surface;} surface;};
int main(){
 static_assert(kA5GPUClientMaxResources==128,"logical handles");
 static_assert(kA5GPUPhysicalSurfaceSlots==4,"physical GPU windows remain bounded");
 TestSlot slots[kA5GPULogicalSurfaceCapacity]={};
 for(uint32_t i=0;i<128;i++){
  assert(a5gpu_resource_free_index(slots)==i);
  slots[i].surface.surface=reinterpret_cast<void*>(uintptr_t(i+1));
 }
 assert(a5gpu_resource_free_index(slots)==128); /* genuine full quota */
 slots[32].surface.surface=nullptr;assert(a5gpu_resource_free_index(slots)==32);
 slots[32].surface.surface=reinterpret_cast<void*>(uintptr_t(33));
 slots[127].surface.surface=nullptr;assert(a5gpu_resource_free_index(slots)==127);
 const uint32_t boundaries[]={0,31,32,63,64,127};
 for(uint32_t first:boundaries){
  A5GPUProtectedResources set={};assert(a5gpu_protect_resource(&set,first));
  assert(set.count==1&&a5gpu_protect_resource(&set,first)&&set.count==1);
  for(uint32_t i=0;i<128;i++)assert(a5gpu_resource_is_protected(set,i)==(i==first));
 }
 A5GPUProtectedResources set={};
 const uint32_t protectedIndices[]={0,32,64,127};
 for(uint32_t i: protectedIndices)assert(a5gpu_protect_resource(&set,i));
 assert(!a5gpu_protect_resource(&set,31)&&!a5gpu_protect_resource(&set,128));
 assert(!a5gpu_resource_is_protected(set,31)&&!a5gpu_protect_resource(nullptr,0));
 set.count=5;assert(!a5gpu_protect_resource(&set,0)&&a5gpu_resource_is_protected(set,31));
}
