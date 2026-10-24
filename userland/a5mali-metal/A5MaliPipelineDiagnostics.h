/* SPDX-License-Identifier: MIT */
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

/* Rejection-only receipts have a separate bound from successful startup
 * pipeline logging. This reports metadata and never changes admission. */
FOUNDATION_EXPORT void A5MaliLogPipelineRejection(const char * _Nonnull phase,
    MTLRenderPipelineDescriptor * _Nullable descriptor,MTLPipelineOption options,
    NSString * _Nullable reason);
