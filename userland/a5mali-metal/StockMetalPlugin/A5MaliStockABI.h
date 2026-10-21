/* SPDX-License-Identifier: MIT */
#ifndef A5_MALI_STOCK_ABI_H
#define A5_MALI_STOCK_ABI_H

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

#ifdef A5_MALI_STOCK_ABI_TEST
#define A5_MALI_STOCK_DEVICE_NAME @"A5MaliTestStockDevice"
#define A5_MALI_STOCK_FEATURES_NAME @"A5MaliTestStockFeatureQueries"
#else
#define A5_MALI_STOCK_DEVICE_NAME @"_MTLDevice"
#define A5_MALI_STOCK_FEATURES_NAME @"MTLDeviceFeatureQueries"
#endif

/* iOS 16.7.16 _MTLDevice._limits Objective-C type metadata. The payload is
 * inline, not a pointer. Resolve its actual placement through the runtime;
 * never assume a subclass's layout from a fixed self-relative offset.
 */
typedef struct {
    uint32_t maxFramebufferStorageBits;
    uint32_t linearTextureArrayAlignmentBytes;
    uint32_t linearTextureArrayAlignmentSlice;
    uint32_t maxTileBuffers;
    uint32_t maxTileTextures;
    uint32_t maxTileSamplers;
    uint32_t maxTileInlineDataSize;
    uint32_t minTilePixels;
    uint32_t maxColorAttachments;
    uint32_t maxVertexAttributes;
    uint32_t maxVertexBuffers;
    uint32_t maxVertexTextures;
    uint32_t maxVertexSamplers;
    uint32_t maxVertexInlineDataSize;
    uint32_t maxInterpolants;
    uint32_t maxFragmentBuffers;
    uint32_t maxFragmentTextures;
    uint32_t maxFragmentSamplers;
    uint32_t maxFragmentInlineDataSize;
    uint32_t maxComputeBuffers;
    uint32_t maxComputeTextures;
    uint32_t maxComputeSamplers;
    uint32_t maxComputeInlineDataSize;
    uint32_t maxComputeLocalMemorySizes;
    uint32_t maxTotalComputeThreadsPerThreadgroup;
    uint32_t maxComputeThreadgroupMemory;
    float maxLineWidth;
    float maxPointSize;
    uint32_t maxVisibilityQueryOffset;
    uint32_t padmaxBufferLength;
    uint32_t minConstantBufferAlignmentBytes;
    uint32_t minBufferNoCopyAlignmentBytes;
    uint32_t maxTextureWidth1D;
    uint32_t maxTextureWidth2D;
    uint32_t maxTextureHeight2D;
    uint32_t maxTextureWidth3D;
    uint32_t maxTextureHeight3D;
    uint32_t maxTextureDepth3D;
    uint32_t maxTextureDimensionCube;
    uint32_t maxTextureLayers;
    uint32_t linearTextureAlignmentBytes;
    uint32_t iosurfaceTextureAlignmentBytes;
    uint32_t iosurfaceReadOnlyTextureAlignmentBytes;
    uint32_t deviceLinearTextureAlignmentBytes;
    uint32_t deviceLinearReadOnlyTextureAlignmentBytes;
    uint32_t maxFunctionConstantIndices;
    uint32_t maxComputeThreadgroupMemoryAlignmentBytes;
    uint32_t maxInterpolatedComponents;
    uint32_t maxTessellationFactor;
    uint32_t maxIndirectBuffers;
    uint32_t maxIndirectTextures;
    uint32_t maxIndirectSamplers;
    uint32_t maxIndirectSamplersPerDevice;
    uint32_t maxFenceInstances;
    uint32_t maxViewportCount;
    uint32_t maxCustomSamplePositions;
    uint32_t maxVertexAmplificationFactor;
    uint32_t maxVertexAmplificationCount;
    uint32_t maxTextureBufferWidth;
    uint32_t maxComputeAttributes;
    uint32_t maxIOCommandsInFlight;
    uint32_t maxPredicatedNestingDepth;
    uint32_t maxConstantBufferArguments;
    uint64_t maxBufferLength;
} A5MaliStockLimits;

_Static_assert(sizeof(A5MaliStockLimits) == 0x108, "iOS 16 Metal limits size");
_Static_assert(offsetof(A5MaliStockLimits, maxBufferLength) == 0x100,
               "iOS 16 Metal maxBufferLength offset");
_Static_assert(offsetof(A5MaliStockLimits, maxTextureWidth2D) == 0x84,
               "iOS 16 Metal texture width offset");

static inline Ivar A5MaliStockDeviceIvar(id device, const char *name)
{
    Class base = NSClassFromString(A5_MALI_STOCK_DEVICE_NAME);
    return base && [device isKindOfClass:base] ?
        class_getInstanceVariable(base, name) : NULL;
}

static inline BOOL A5MaliStockLayoutMatches(void)
{
    Class base = NSClassFromString(A5_MALI_STOCK_DEVICE_NAME);
    Ivar ivar = base ? class_getInstanceVariable(base, "_limits") : NULL;
    const char *type = ivar ? ivar_getTypeEncoding(ivar) : NULL;
    if (!type || type[0] != '{') return NO;
    NSUInteger size = 0, alignment = 0;
    NSGetSizeAndAlignment(type, &size, &alignment);
    return size == sizeof(A5MaliStockLimits) &&
        alignment == _Alignof(A5MaliStockLimits);
}

/* A different OS layout fails initialization instead of corrupting adjacent
 * queues or feature state. NSGetSizeAndAlignment reads runtime type metadata.
 */
static inline A5MaliStockLimits *A5MaliStockLimitsForDevice(id device)
{
    Ivar ivar = A5MaliStockDeviceIvar(device, "_limits");
    const char *type = ivar ? ivar_getTypeEncoding(ivar) : NULL;
    if (!type || type[0] != '{') return NULL;
    NSUInteger size = 0, alignment = 0;
    NSGetSizeAndAlignment(type, &size, &alignment);
    ptrdiff_t offset = ivar_getOffset(ivar);
    if (size != sizeof(A5MaliStockLimits) ||
        alignment != _Alignof(A5MaliStockLimits) || offset < 0 ||
        (size_t)offset > class_getInstanceSize(object_getClass(device)) ||
        size > class_getInstanceSize(object_getClass(device)) - (size_t)offset)
        return NULL;
    return (A5MaliStockLimits *)((uint8_t *)(__bridge void *)device + offset);
}

static inline BOOL A5MaliWriteStockLimits(id device,
                                         const A5MaliStockLimits *limits)
{
    A5MaliStockLimits *storage = A5MaliStockLimitsForDevice(device);
    if (!storage || !limits) return NO;
    memcpy(storage, limits, sizeof(*limits));
    return YES;
}

/* The non-underscore stock base implements explicit false supports* methods
 * and BOOL familySupports* getters. NSObject -init preserves the zeroed
 * family flags. Its initWithDevice: is abstract (returns nil), while the
 * underscore subclass computes Apple-profile feature tables; neither is
 * appropriate for the conservative Mali profile. Require inherited NSObject
 * -init to avoid invoking an unexamined initializer on another OS version.
 */
static inline id A5MaliNewConservativeStockFeatureQueries(void)
{
    Class featureClass = NSClassFromString(A5_MALI_STOCK_FEATURES_NAME);
    Class root = [NSObject class];
    if (!featureClass || class_getSuperclass(featureClass) != root ||
        class_getMethodImplementation(featureClass, @selector(init)) !=
        class_getMethodImplementation(root, @selector(init)))
        return nil;
    id queries = [[featureClass alloc] init];
    SEL test = NSSelectorFromString(@"familySupportsArgumentBuffersTier2");
    Method method = class_getInstanceMethod(featureClass, test);
    char returnType[8] = {0};
    if (method) method_getReturnType(method, returnType, sizeof(returnType));
    if (!queries || !method || strcmp(returnType, @encode(BOOL)) != 0)
        return nil;
    return queries;
}

/* _MTLDevice explicitly releases this object during dealloc. A retained
 * bridge transfers one ownership reference into the checked object slot even
 * without ARC ownership layout (object_setIvar cannot guarantee retention).
 */
static inline BOOL A5MaliInstallStockFeatureQueries(id device, id queries)
{
    Ivar ivar = A5MaliStockDeviceIvar(device, "_featureQueries");
    const char *type = ivar ? ivar_getTypeEncoding(ivar) : NULL;
    Class featureClass = NSClassFromString(A5_MALI_STOCK_FEATURES_NAME);
    if (!queries || !featureClass || ![queries isKindOfClass:featureClass] ||
        !type || type[0] != '@') return NO;
    ptrdiff_t offset = ivar_getOffset(ivar);
    size_t total = class_getInstanceSize(object_getClass(device));
    if (offset < 0 || (size_t)offset > total ||
        sizeof(id) > total - (size_t)offset) return NO;
    uint8_t *slot = (uint8_t *)(__bridge void *)device + offset;
    CFTypeRef previous = NULL;
    memcpy(&previous, slot, sizeof(previous));
    CFTypeRef retained = CFBridgingRetain(queries);
    memcpy(slot, &retained, sizeof(retained));
    if (previous) CFRelease(previous);
    return object_getIvar(device, ivar) == queries;
}

static inline BOOL A5MaliInstallConservativeFeatureQueries(id device)
{
    id queries = A5MaliNewConservativeStockFeatureQueries();
    return queries && A5MaliInstallStockFeatureQueries(device, queries);
}

/* _supportedGPUFamilies is a C++ vector pointer. The stock deallocator checks
 * NULL before destructing it. With supportsFamily:/supportsFeatureSet: both
 * overridden to NO, leaving that slot NULL avoids claiming an Apple family.
 * Do not call base initGPUFamilySupport for this profile.
 */
#undef A5_MALI_STOCK_DEVICE_NAME
#undef A5_MALI_STOCK_FEATURES_NAME
#endif
