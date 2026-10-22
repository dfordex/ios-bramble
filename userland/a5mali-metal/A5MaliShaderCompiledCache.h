/* SPDX-License-Identifier: MIT */
#import <Foundation/Foundation.h>
#import "A5MaliCompiledRegistry.h"

NS_ASSUME_NONNULL_BEGIN

/* Owns the loaded native byte copies and the replaced one-pass profile. The
 * render pipeline must retain this entry as long as entry.profile is used.
 * All resource/layout/state ABI remains the authenticated expected profile;
 * a compiler receipt never grants a new executable ABI. */
@interface A5MaliShaderCompiledCacheEntry : NSObject
@property(nonatomic,readonly) const A5MaliCompiledProfile *profile;
@property(nonatomic,readonly,copy) NSString *requestID;
@end

/* Only exact authenticated profiles602/603 are accepted in this route.
 * nil/error.code=ENOENT means not published yet; other errors reject a cache.
 * The caller must first select the profile against the full actual descriptor,
 * then pass the canonical pipeline request ID (not a function-only request).
 */
FOUNDATION_EXPORT A5MaliShaderCompiledCacheEntry * _Nullable A5MaliLoadShaderCompiledCache(
    NSString *requestID, const A5MaliCompiledProfile *expected, NSError **error);

NS_ASSUME_NONNULL_END
