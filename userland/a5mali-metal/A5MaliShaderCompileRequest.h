/* SPDX-License-Identifier: MIT */
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, A5MaliShaderForwardResult) {
    A5MaliShaderForwardFailed = 0,
    A5MaliShaderForwardQueued = 1,
    A5MaliShaderForwardAlreadyQueued = 2,
    A5MaliShaderForwardBusy = 3, /* lock/quota pressure: retry same identity; no request published */
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

/* Compute the same validated UID-bound identity without opening the spool.
 * An immutable published cache entry must not wait for queue maintenance. */
FOUNDATION_EXPORT NSString * _Nullable A5MaliShaderCompileRequestID(
    NSDictionary *payload, NSError **error);

/* Requires a root-owned01777 spool base. Each provider UID owns a0700 child;
 * worker must independently validate UID, schema, source identity and digest.
 * Queued/AlreadyQueued mean durable publication, not compilation. Busy returns
 * the validated request ID and requires retry; it never waits for a UID lock. */
FOUNDATION_EXPORT A5MaliShaderForwardResult A5MaliForwardShaderCompileRequest(
    NSDictionary *payload, NSString * _Nullable * _Nullable requestID,
    NSError **error);

NS_ASSUME_NONNULL_END
