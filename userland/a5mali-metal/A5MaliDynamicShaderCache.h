/* SPDX-License-Identifier: MIT */
#import "A5MaliCompiledRegistry.h"
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
/* Immutable root-published single-stage code and its reflected ABI. Loading
 * verifies origin/identity/storage bounds; it does NOT admit a render pipeline.
 * The function/pipeline must retain this owner while using its C pointers. */
@interface A5MaliDynamicShaderCacheEntry : NSObject
@property(nonatomic, readonly) const A5MaliCompiledShader *shader;
@property(nonatomic, readonly) const A5MaliCompiledResource *resources;
@property(nonatomic, readonly) uint32_t resourceCount;
@property(nonatomic, readonly) const A5MaliCompiledPushField *pushFields;
@property(nonatomic, readonly) uint32_t pushFieldCount;
@property(nonatomic, readonly) const A5MaliCompiledVertexAttribute *attributes;
@property(nonatomic, readonly) uint32_t attributeCount;
@property(nonatomic, readonly) const A5MaliCompiledVertexLayout *layouts;
@property(nonatomic, readonly) uint32_t layoutCount;
@property(nonatomic, readonly) uint32_t stage;
@property(nonatomic, readonly, copy) NSString *requestID;
@property(nonatomic, readonly, copy) NSString *functionName;
@property(nonatomic, readonly, copy) NSDictionary *functionPayload;
@property(nonatomic, readonly, copy) NSDictionary *nativeABI;
@property(nonatomic, readonly, copy) NSDictionary *reflection;
@end

/* requestID is the canonical existing function request ID, including the
 * current provider UID. No profile IDs or native module hashes are allowlisted.
 * ENOENT means publication pending; other errors are terminal cache failures. */
FOUNDATION_EXPORT A5MaliDynamicShaderCacheEntry *_Nullable A5MaliLoadDynamicShaderStage(
    NSString *requestID, NSDictionary *functionPayload, NSError **error);
NS_ASSUME_NONNULL_END
