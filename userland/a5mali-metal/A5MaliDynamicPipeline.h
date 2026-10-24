/* SPDX-License-Identifier: MIT */
#import "A5MaliRestrictedDevice.h"
#import "A5MaliCompiledRegistry.h"
NS_ASSUME_NONNULL_BEGIN
/* Retains both root-published stages while all C profile pointers are in use. */
@interface A5MaliDynamicPipelineEntry : NSObject
@property(nonatomic,readonly) const A5MaliCompiledProfile *profile;
@end
FOUNDATION_EXPORT A5MaliDynamicPipelineEntry * _Nullable A5MaliComposeDynamicPipeline(
    MTLRenderPipelineDescriptor *descriptor,NSError **error);
/* Adapt implemented vertex-fetch and fixed-function source-over state while
 * keeping the original shader authentication and all other descriptor gates. */
FOUNDATION_EXPORT A5MaliDynamicPipelineEntry * _Nullable A5MaliAdaptCompiledPipeline(
    MTLRenderPipelineDescriptor *descriptor,BOOL *suppliesInactiveColor1,NSError **error);
/* Shared exact Metal state/layout validator used by static and dynamic routes. */
FOUNDATION_EXPORT NSString * _Nullable A5MaliCompiledDescriptorMismatch(
    const A5MaliCompiledProfile *profile,MTLRenderPipelineDescriptor *descriptor);
NS_ASSUME_NONNULL_END
