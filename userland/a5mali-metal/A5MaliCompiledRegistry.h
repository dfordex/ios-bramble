/* SPDX-License-Identifier: MIT
 * Immutable contracts for private, locally translated QuartzCore programs.
 * Generated data is private. A registered shader is not a general Metal GPU.
 */
#ifndef A5_MALI_COMPILED_REGISTRY_H
#define A5_MALI_COMPILED_REGISTRY_H
#include <stddef.h>
#include <stdint.h>
#ifdef __OBJC__
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
NS_ASSUME_NONNULL_BEGIN
#define A5_MALI_NULLABLE _Nullable
#else
#define A5_MALI_NULLABLE
#endif

enum { A5MaliStageVertex = 1, A5MaliStageFragment = 2 };
enum { A5MaliResourceBuffer = 1, A5MaliResourceTexture = 2,
       A5MaliResourceSampler = 3, A5MaliResourceInputAttachment = 4 };
enum { A5MaliResourceRead = 1, A5MaliResourceWrite = 2,
       A5MaliResourceStorage = 4, A5MaliResourceImmutableSampler = 8,
       A5MaliResourcePadUniformTail = 16 };
enum { A5MaliPushBindOffset = 1, A5MaliPushColorWriteRule = 2 };
enum { A5MaliProfileFixedViewport = 1, A5MaliProfileNearestSampler = 2,
       A5MaliProfileNormalizedSampler = 4, A5MaliProfileIndependentTargets = 8,
       A5MaliProfileSourceOverBlend = 16, A5MaliProfileNotExecutable = 32,
       A5MaliProfileCoverageAdd = 64, A5MaliProfileStrokeSourceOver = 128,
       A5MaliProfileInlineSourceOver = 256,
       /* Root-compiled stages, admitted by their reflected runtime ABI rather
        * than a constant/module fingerprint. These flags do not authorize a
        * new resource layout; the runtime validates it independently. */
       A5MaliProfileDynamicStages = 512,
       A5MaliProfileDynamicColorVarying = 1024,
       A5MaliProfileFramebufferFetch = 2048,
       A5MaliProfileFragmentPosition = 4096 };
enum { A5MaliDynamicProfileID = 65536 };

typedef struct {
    const uint8_t *bytes;
    uint32_t byteCount, firstTag, workRegisters, tlsBytes, wlsBytes;
    const char *sha256;
} A5MaliCompiledShader;

typedef struct {
    const char *name;
    uint32_t dataType, byteCount;
    uint8_t raw[3];
} A5MaliCompiledFunctionConstant;

typedef struct {
    /* bindingIndex is the actual SPIR-V descriptor binding. Uniform words
     * use nativeIndex=bindingIndex+1. Storage records occupy stage UBO0 at
     * sysvalOffset, and contain GPUVA:u64, bytes:u32, reserved:u32. */
    uint32_t stage, kind, metalIndex, bindingIndex, nativeIndex;
    uint32_t flags, windowOffset, uniformBytes, sysvalOffset, pushOffset;
} A5MaliCompiledResource;

typedef struct {
    uint32_t stage, kind, metalIndex, offset, bytes, value;
} A5MaliCompiledPushField;

typedef struct {
    uint32_t index, format, offset, bufferIndex;
} A5MaliCompiledVertexAttribute;
typedef struct {
    uint32_t index, stride, stepFunction, stepRate;
} A5MaliCompiledVertexLayout;

typedef struct {
    uint32_t passID, logicalTarget;
    A5MaliCompiledShader vertex, fragment;
} A5MaliCompiledPass;

typedef struct {
    uint32_t writeMask, blendEnabled, rgbOperation, alphaOperation;
    uint32_t sourceRGB, destinationRGB, sourceAlpha, destinationAlpha;
} A5MaliCompiledAttachmentState;
typedef struct {
    A5MaliCompiledAttachmentState attachments[8];
} A5MaliCompiledAttachmentContract;

/* Immutable sampler states decoded by the AIR translator. Address modes use
 * the A5RuntimeSampler enum; these are not application Metal sampler slots. */
typedef struct {
    uint32_t nativeIndex, minFilter, magFilter, mipFilter;
    uint32_t sAddressMode, tAddressMode, rAddressMode, normalizedCoordinates;
    float lodMinClamp, lodMaxClamp;
} A5MaliCompiledSampler;

typedef struct A5MaliCompiledProfile {
    uint32_t profileID;
    const char *name, *vertexName, *fragmentName;
    uint32_t colorFormats[8]; /* actual Metal pixel-format numbers */
    uint32_t flags, viewportWidth, viewportHeight;
    const A5MaliCompiledPass *passes;
    uint32_t passCount;
    const A5MaliCompiledResource *resources;
    uint32_t resourceCount;
    const A5MaliCompiledPushField *pushFields;
    uint32_t pushFieldCount;
    const A5MaliCompiledVertexAttribute *attributes;
    uint32_t attributeCount;
    const A5MaliCompiledVertexLayout *layouts;
    uint32_t layoutCount;
    const A5MaliCompiledAttachmentContract *attachmentContracts;
    uint32_t attachmentContractCount;
    const A5MaliCompiledSampler *immutableSamplers;
    uint32_t immutableSamplerCount;
} A5MaliCompiledProfile;

/* IDs are stable wire identities, not array positions. Absent profiles are
 * unsupported. 100..108 blur, 200..208 misc native passes, 300..302 path
 * coverage remaps; 400..403 are host-only original MRT metadata.
 * A remapped test is never selected for an original MRT. */
#ifdef __cplusplus
extern "C" {
#endif
const A5MaliCompiledProfile * A5_MALI_NULLABLE A5MaliCompiledProfiles(size_t *count);
const A5MaliCompiledProfile * A5_MALI_NULLABLE A5MaliCompiledProfileForID(uint32_t profileID);
const A5MaliCompiledFunctionConstant * A5_MALI_NULLABLE
A5MaliCompiledConstantsForProfile(uint32_t profileID, size_t *count);
/* Exact vertex constants are separate from the fragment table above. */
const A5MaliCompiledFunctionConstant * A5_MALI_NULLABLE
A5MaliCompiledVertexConstantsForProfile(uint32_t profileID, size_t *count);

#ifdef __OBJC__
@class A5MaliMetalFunction;
/* Requires exact authenticated function instances from one library/device.
 * Constants, unsupported blend/depth/sample state and changed layouts fail. */
const A5MaliCompiledProfile * _Nullable A5MaliSelectCompiledProfile(
    MTLRenderPipelineDescriptor * _Nullable descriptor,
    NSError * _Nullable * _Nullable error);
NS_ASSUME_NONNULL_END
#endif
#ifdef __cplusplus
}
#endif
#undef A5_MALI_NULLABLE
#endif
