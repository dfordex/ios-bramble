/* Actual public private-buffer allocation under pressure from an idle arena.
 * Only transport/storage is mocked; the factory, lock and retry are real. */
#import "A5MaliRestrictedDevice.h"
#import "A5MaliMetalDeviceResources.h"
#define main arena_fixture_main
#include "test_native_upload_arena.c"
#undef main
@interface A5MaliRestrictedDevice (PoolPressurePrivate)
- (A5MaliDevice *)privateDevice;
@end
@interface A5MaliDevice (PoolPressureClient)
- (A5MaliClient *)client;
@end
int main(void)
{
 reset();
 @autoreleasepool {
  A5MaliRestrictedDevice*d=[[A5MaliRestrictedDevice alloc]initWithTransport:call context:bo
   commandCapabilities:127 operationCapabilities:0xfffff];assert(d);
  A5MaliClient*c=[[d privateDevice]client];c->nativeUploadReuse=1;
  assert(!A5MaliBeginNativeBatch(c));draw(c,127,0x5a);A5MaliFence f;
  assert(!A5MaliEndNativeBatch(c,1,&f)&&c->nativeUploadPool&&creates==1&&!releases);
  NSMutableArray*buffers=[NSMutableArray new];
  for(unsigned i=0;i<4;i++){
   A5MaliPrivateBuffer*b=[d newBufferWithLength:4096 options:MTLResourceStorageModePrivate];
   assert(b);[buffers addObject:b];
  }
  assert(creates==5&&releases==1); /* fourth allocation evicts the terminal arena */
  A5MaliDiscardNativeUploads(c);assert(!c->nativeUploadPool);
 }
 assert(releases==5);reset();
 puts("PASS actual public buffer factory: idle upload pool evicted under four-slot pressure, output capacity restored, no live arena or buffer lost");
 return 0;
}
