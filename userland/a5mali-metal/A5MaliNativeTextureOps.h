/* SPDX-License-Identifier: MIT */
#import "A5MaliMetalTexture.h"
#import "A5MaliNative.h"
#include "../a5xelte-air-translation/families/runtime_encode.h"
NS_ASSUME_NONNULL_BEGIN
/* Translate a logical subresource only after validating the whole kernel map.
 * Padding and other mip levels are never included in the shader image span. */
BOOL A5MaliRuntimeImageForTexture(A5MaliMetalTexture *texture,NSUInteger level,
    A5MaliSurface *surface,const A5NativeSpan *span,uint32_t requiredUsage,
    A5RuntimeImage *image);
BOOL A5MaliEncodeTextureCopy(A5MaliCommandBuffer *commands,
    A5MaliMetalTexture *source,NSUInteger sourceLevel,MTLOrigin sourceOrigin,
    MTLSize size,A5MaliMetalTexture *destination,NSUInteger destinationLevel,
    MTLOrigin destinationOrigin);
BOOL A5MaliEncodeTextureMipmaps(A5MaliCommandBuffer *commands,
    A5MaliMetalTexture *texture);
NS_ASSUME_NONNULL_END
