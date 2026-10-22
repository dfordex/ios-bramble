/* SPDX-License-Identifier: MIT */
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, A5MaliShaderForwardResult) {
    A5MaliShaderForwardFailed = 0,
    A5MaliShaderForwardQueued = 1,
    A5MaliShaderForwardAlreadyQueued = 2,
};

/* These immutable descriptions are requests, never executable Metal objects.
 * The caller must already have authenticated the original stock library.
 * Unsupported constant types/options fail rather than dropping their data. */
FOUNDATION_EXPORT NSDictionary * _Nullable A5MaliShaderCompileFunctionPayload(
    NSString *name, MTLFunctionType stage,
    MTLFunctionConstantValues * _Nullable constants, NSError **error);
FOUNDATION_EXPORT NSDictionary * _Nullable A5MaliShaderCompilePipelinePayload(
    MTLRenderPipelineDescriptor *descriptor, NSDictionary *vertex,
    NSDictionary *fragment, NSError **error);

/* Requires a root-owned01777 spool base. Each provider UID owns a0700 child;
 * worker must independently validate UID, schema, source identity and digest.
 * Success means a request was queued (or already exists), not compilation. */
FOUNDATION_EXPORT A5MaliShaderForwardResult A5MaliForwardShaderCompileRequest(
    NSDictionary *payload, NSString * _Nullable * _Nullable requestID,
    NSError **error);

NS_ASSUME_NONNULL_END
