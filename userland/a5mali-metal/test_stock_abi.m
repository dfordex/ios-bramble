/* SPDX-License-Identifier: MIT
 * Synthetic Objective-C runtime layouts test the private-ivar access and
 * ownership helper. This executable intentionally does not link Metal.
 */
#define A5_MALI_STOCK_ABI_TEST 1
#import "StockMetalPlugin/A5MaliStockABI.h"
#include <assert.h>
#include <stdio.h>

@interface A5MaliTestStockFeatureQueries : NSObject {
    BOOL _familySupportsArgumentBuffersTier2;
}
- (BOOL)familySupportsArgumentBuffersTier2;
@end
@implementation A5MaliTestStockFeatureQueries
- (BOOL)familySupportsArgumentBuffersTier2
{
    return _familySupportsArgumentBuffersTier2;
}
@end

@interface A5MaliTestStockDevice : NSObject {
    A5MaliStockLimits _limits;
    id _featureQueries;
}
- (const A5MaliStockLimits *)directLimits;
- (id)directFeatureQueries;
@end
@implementation A5MaliTestStockDevice
- (const A5MaliStockLimits *)directLimits { return &_limits; }
- (id)directFeatureQueries { return _featureQueries; }
@end

int main(void)
{
    @autoreleasepool {
        assert(A5MaliStockLayoutMatches());
        assert(!A5MaliStockLimitsForDevice([NSObject new]));
        A5MaliTestStockDevice *device = [A5MaliTestStockDevice new];
        assert(A5MaliStockLimitsForDevice(device) == [device directLimits]);
        A5MaliStockLimits limits = {0};
        limits.maxColorAttachments = 1;
        limits.maxTextureWidth2D = 1080;
        limits.maxBufferLength = UINT64_C(0x100000);
        assert(A5MaliWriteStockLimits(device, &limits));
        assert([device directLimits]->maxTextureWidth2D == 1080);
        assert([device directLimits]->maxBufferLength == UINT64_C(0x100000));
        assert(!A5MaliWriteStockLimits(device, NULL));
        assert(A5MaliInstallConservativeFeatureQueries(device));
        assert(![[device directFeatureQueries] familySupportsArgumentBuffersTier2]);
        __weak id first = [device directFeatureQueries];
        assert(first);
        assert(A5MaliInstallConservativeFeatureQueries(device));
        assert(!first);
        __weak id second;
        @autoreleasepool { second = [device directFeatureQueries]; }
        assert(second);
        device = nil;
        assert(!second);
        puts("stock ABI layout and feature ownership: passed (synthetic runtime)");
    }
    return 0;
}
