/* SPDX-License-Identifier: MIT */
#import "A5MaliDiscoveryAudit.h"
#include <assert.h>
#ifdef A5_MALI_CHECK_CURRENT
#import "A5MaliRestrictedDevice.h"
#endif

@interface A5FakeDevice : NSObject
- (instancetype)initWithAcceleratorPort:(unsigned int)service;
- (id)newCommandQueue;
@end

@implementation A5FakeDevice
- (instancetype)initWithAcceleratorPort:(unsigned int)service
{
    (void)service;
    return [super init];
}
- (id)newCommandQueue { return nil; }
@end

int main(void)
{
    uint32_t nilClass = A5MaliAuditMetalProviderClass(Nil);
    assert(nilClass & A5MaliDiscoveryMissingClass);
    assert(nilClass & A5MaliDiscoveryMissingMetalSPI);

    uint32_t fake = A5MaliAuditMetalProviderClass(A5FakeDevice.class);
    assert(!(fake & A5MaliDiscoveryMissingInitializer));
    assert(!(fake & A5MaliDiscoveryMissingQueue));
    assert(fake & A5MaliDiscoveryMissingBase);
    assert(fake & A5MaliDiscoveryMissingMetal);
    assert(fake & A5MaliDiscoveryMissingMetalSPI);
    assert(fake & A5MaliDiscoveryMissingRenderPath);
    assert(fake & A5MaliDiscoveryMissingResources);
#ifdef A5_MALI_CHECK_CURRENT
    uint32_t current = A5MaliAuditMetalProviderClass(
        A5MaliRestrictedDevice.class);
    assert(current & A5MaliDiscoveryMissingMetal);
    assert(current & A5MaliDiscoveryMissingMetalSPI);
#endif
    return 0;
}
