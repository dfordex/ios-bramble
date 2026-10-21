/* SPDX-License-Identifier: MIT
 * Exact stock QuartzCore shader-library identity and authenticated native
 * family registry. No metallib or translated shader bytes are distributed.
 */
#import "A5MaliRestrictedDevice.h"
#import "A5MaliCompiledRegistry.h"
#import <CommonCrypto/CommonDigest.h>
#include <string.h>

/* SHA-256 of iOS 16.7.16 QuartzCore.framework/default.metallib from the
 * locally staged IPSW. This identifies the whole source library; a function
 * label, pathname, or a synthetic MTLFunction cannot authenticate it. */
static const uint8_t kQuartzCoreMetallibSHA256[CC_SHA256_DIGEST_LENGTH] = {
    0x11, 0xc7, 0x4c, 0xc4, 0x2c, 0xe5, 0x13, 0x7b,
    0x73, 0xd4, 0x4d, 0x42, 0x7f, 0x75, 0x76, 0x4f,
    0x88, 0x66, 0x56, 0xd4, 0xdd, 0xb3, 0x74, 0x42,
    0x2d, 0x56, 0xb6, 0x09, 0xed, 0x27, 0x62, 0xd9,
};

#if defined(A5_MALI_REQUIRE_COMPILED_REGISTRY) && !__has_include("A5MaliCompiledRegistryData.inc")
#error "The requested private compiled family registry is missing"
#endif
#if __has_include("A5MaliCompiledRegistryData.inc")
#include "A5MaliCompiledRegistryData.inc"
#define A5_MALI_HAS_COMPILED_REGISTRY 1
#endif

static BOOL compiledShaderValid(const A5MaliCompiledShader *shader)
{
    if (!shader->bytes || !shader->byteCount || shader->byteCount > 0x10000 ||
        shader->firstTag < 1 || shader->firstTag > 15 ||
        !shader->workRegisters || shader->workRegisters > 16 ||
        shader->tlsBytes > 64 || shader->wlsBytes ||
        !shader->sha256 || strlen(shader->sha256) != 64) return NO;
    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(shader->bytes, shader->byteCount, digest);
    static const char hex[] = "0123456789abcdef";
    for (unsigned i = 0; i < sizeof(digest); ++i)
        if (shader->sha256[2*i] != hex[digest[i] >> 4] ||
            shader->sha256[2*i+1] != hex[digest[i] & 15]) return NO;
    return YES;
}

const A5MaliCompiledProfile *A5MaliCompiledProfiles(size_t *count)
{
    if (count) *count = 0;
#ifdef A5_MALI_HAS_COMPILED_REGISTRY
    static BOOL authenticated;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        authenticated = YES;
        for (size_t i = 0; i < sizeof(kA5MaliCompiledProfiles) / sizeof(kA5MaliCompiledProfiles[0]); ++i) {
            const A5MaliCompiledProfile *p = &kA5MaliCompiledProfiles[i];
            if (!p->profileID || !p->name || !p->vertexName || !p->fragmentName ||
                !p->passes || !p->passCount || p->passCount > 2 ||
                p->resourceCount > 16 || p->attributeCount > 31 || p->layoutCount > 31 ||
                p->pushFieldCount > 32) { authenticated = NO; break; }
            for (uint32_t j = 0; j < p->passCount; ++j)
                if (!compiledShaderValid(&p->passes[j].vertex) ||
                    !compiledShaderValid(&p->passes[j].fragment)) authenticated = NO;
        }
    });
    if (!authenticated) return NULL;
    if (count) *count = sizeof(kA5MaliCompiledProfiles) / sizeof(kA5MaliCompiledProfiles[0]);
    return kA5MaliCompiledProfiles;
#else
    (void)compiledShaderValid;
    return NULL;
#endif
}

const A5MaliCompiledProfile *A5MaliCompiledProfileForID(uint32_t profileID)
{
    size_t count = 0;
    const A5MaliCompiledProfile *profiles = A5MaliCompiledProfiles(&count);
    for (size_t i = 0; i < count; ++i)
        if (profiles[i].profileID == profileID) return &profiles[i];
    return NULL;
}

static NSError *libraryError(NSString *reason)
{
    return [NSError errorWithDomain:@"com.orhunnx.a5xelte.mali"
        code:kIOReturnUnsupported
        userInfo:@{NSLocalizedDescriptionKey: reason}];
}

/* Typed getters observed in the staged iOS 16.7.16 descriptor. These are
 * optional on a host SDK; never infer a private ivar offset from its layout. */
@interface MTLFunctionDescriptor (A5MaliDescriptorValidation)
- (NSUInteger)pipelineOptions;
- (nullable NSDictionary *)pluginData;
- (nullable NSArray *)privateFunctions;
@end

@interface A5MaliMetalLibrary () {
    A5MaliRestrictedDevice *_device;
}
- (instancetype)initWithDevice:(A5MaliRestrictedDevice *)device
                          data:(NSData *)data;
@end

@interface A5MaliMetalFunction () {
    A5MaliMetalLibrary *_library;
    NSString *_name;
    MTLFunctionType _functionType;
}
- (instancetype)initWithLibrary:(A5MaliMetalLibrary *)library
                           name:(NSString *)name
                           type:(MTLFunctionType)type;
@end

@implementation A5MaliRestrictedDevice (ExactQuartzCoreLibrary)

- (A5MaliMetalLibrary *)newDefaultLibraryWithBundle:(NSBundle *)bundle
                                               error:(NSError * _Nullable * _Nullable)error
{
    NSURL *url = [bundle URLForResource:@"default" withExtension:@"metallib"];
    return [self newLibraryWithURL:url error:error];
}

- (A5MaliMetalLibrary *)newLibraryWithURL:(NSURL *)url
                                     error:(NSError * _Nullable * _Nullable)error
{
    if (!url.isFileURL) {
        if (error) *error = libraryError(@"only a local metallib is supported");
        return nil;
    }
    NSNumber *fileSize = nil;
    if (![url getResourceValue:&fileSize forKey:NSURLFileSizeKey error:NULL] ||
        fileSize.unsignedLongLongValue != 1014944) {
        if (error) *error = libraryError(@"QuartzCore metallib size differs");
        return nil;
    }
    NSData *data = [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe
                                          error:NULL];
    A5MaliMetalLibrary *library =
        [[A5MaliMetalLibrary alloc] initWithDevice:self data:data];
    if (!library && error)
        *error = libraryError(@"unsupported or changed QuartzCore metallib");
    return library;
}

- (A5MaliMetalLibrary *)newLibraryWithData:(dispatch_data_t)data
                                      error:(NSError * _Nullable * _Nullable)error
{
    if (!data || dispatch_data_get_size(data) != 1014944) {
        if (error) *error = libraryError(@"QuartzCore metallib size differs");
        return nil;
    }
    const void *bytes = NULL;
    size_t length = 0;
    dispatch_data_t mapped = dispatch_data_create_map(data, &bytes, &length);
    NSData *copy = bytes && length == 1014944 ?
        [NSData dataWithBytes:bytes length:length] : nil;
    A5MaliMetalLibrary *library =
        [[A5MaliMetalLibrary alloc] initWithDevice:self data:copy];
    (void)mapped;
    if (!library && error)
        *error = libraryError(@"unsupported or changed QuartzCore metallib");
    return library;
}

@end

@implementation A5MaliMetalLibrary

- (instancetype)initWithDevice:(A5MaliRestrictedDevice *)device
                          data:(NSData *)data
{
    if (!device || data.length != 1014944 ||
        memcmp(data.bytes, "MTLB", 4)) return nil;
    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    if (memcmp(digest, kQuartzCoreMetallibSHA256, sizeof(digest))) return nil;
    if ((self = [super init])) _device = device;
    return self;
}

- (A5MaliRestrictedDevice *)device { return _device; }
- (NSArray<NSString *> *)functionNames
{
    NSMutableArray<NSString *> *names = [NSMutableArray arrayWithArray:
        @[@"read_surf_vert", @"read_surf_frag"]];
    size_t count = 0;
    const A5MaliCompiledProfile *profiles = A5MaliCompiledProfiles(&count);
    for (size_t i = 0; i < count; ++i)
        for (unsigned stage = 0; stage < 2; ++stage) {
            NSString *name = [NSString stringWithUTF8String:stage ?
                profiles[i].fragmentName : profiles[i].vertexName];
            if (![names containsObject:name]) [names addObject:name];
        }
    return names;
}
- (A5MaliMetalFunction *)newFunctionWithName:(NSString *)name
{
    MTLFunctionType type;
    if ([name isEqualToString:@"read_surf_vert"])
        type = MTLFunctionTypeVertex;
    else if ([name isEqualToString:@"read_surf_frag"])
        type = MTLFunctionTypeFragment;
    else {
        BOOL found = NO;
        size_t count = 0;
        const A5MaliCompiledProfile *profiles = A5MaliCompiledProfiles(&count);
        for (size_t i = 0; i < count; ++i) {
            if ([name isEqualToString:[NSString stringWithUTF8String:profiles[i].vertexName]]) {
                type = MTLFunctionTypeVertex; found = YES; break;
            }
            if ([name isEqualToString:[NSString stringWithUTF8String:profiles[i].fragmentName]]) {
                type = MTLFunctionTypeFragment; found = YES; break;
            }
        }
        if (!found) return nil;
    }
    return [[A5MaliMetalFunction alloc] initWithLibrary:self name:name type:type];
}

- (A5MaliMetalFunction *)newFunctionWithDescriptor:(MTLFunctionDescriptor *)descriptor
                                            error:(NSError * _Nullable * _Nullable)error
{
    if (error) *error = nil;
    if (![descriptor isMemberOfClass:[MTLFunctionDescriptor class]]) {
        if (error) *error = libraryError(@"a plain function descriptor is required");
        return nil;
    }
    /* QuartzCore uses this selector for both ordinary and specialized shaders.
     * Only authenticated, unspecialized translations in the private registry
     * (plus the original read_surf pair) exist.
     * In particular, an empty constants object is not evidence that all of a
     * shader's specialization defaults match our translated program. */
    MTLFunctionDescriptor *snapshot = [descriptor copy];
    if (snapshot.constantValues || snapshot.specializedName || snapshot.options ||
        snapshot.binaryArchives.count ||
        ([snapshot respondsToSelector:@selector(pipelineOptions)] &&
         snapshot.pipelineOptions) ||
        ([snapshot respondsToSelector:@selector(pluginData)] &&
         snapshot.pluginData) ||
        ([snapshot respondsToSelector:@selector(privateFunctions)] &&
         snapshot.privateFunctions.count)) {
        if (error) *error = libraryError(@"function specialization and archives are unsupported");
        return nil;
    }
    A5MaliMetalFunction *function = [self newFunctionWithName:snapshot.name];
    if (!function && error)
        *error = libraryError(@"function is outside the authenticated compiled library profiles");
    return function;
}

- (A5MaliMetalFunction *)newFunctionWithName:(NSString *)name
                           constantValues:(MTLFunctionConstantValues *)constants
                                    error:(NSError **)error
{
    if (constants) {
        if (error) *error = libraryError(@"no compiled AIR function-constant variant matches");
        return nil;
    }
    A5MaliMetalFunction *function = [self newFunctionWithName:name];
    if (error) *error = function ? nil : libraryError(@"function is not compiled");
    return function;
}

@end

@implementation A5MaliMetalFunction
- (instancetype)initWithLibrary:(A5MaliMetalLibrary *)library
                           name:(NSString *)name
                           type:(MTLFunctionType)type
{
    if ((self = [super init])) {
        _library = library;
        _name = [name copy];
        _functionType = type;
    }
    return self;
}
- (NSString *)name { return _name; }
- (MTLFunctionType)functionType { return _functionType; }
- (A5MaliMetalLibrary *)library { return _library; }
- (A5MaliRestrictedDevice *)device { return _library.device; }
@end

static BOOL compiledDescriptorMatches(const A5MaliCompiledProfile *p,
                                      MTLRenderPipelineDescriptor *d)
{
    if (d.rasterSampleCount != 1 || d.maxVertexAmplificationCount != 1 ||
        d.supportIndirectCommandBuffers || !d.isRasterizationEnabled ||
        d.isAlphaToCoverageEnabled || d.isAlphaToOneEnabled ||
        d.depthAttachmentPixelFormat || d.stencilAttachmentPixelFormat ||
        (d.inputPrimitiveTopology != MTLPrimitiveTopologyClassUnspecified &&
         d.inputPrimitiveTopology != MTLPrimitiveTopologyClassTriangle)) return NO;
    for (NSUInteger i = 0; i < 8; ++i) {
        MTLRenderPipelineColorAttachmentDescriptor *a = d.colorAttachments[i];
        if (a.pixelFormat != p->colorFormats[i]) return NO;
        BOOL coverage = (p->flags & A5MaliProfileCoverageAdd) != 0;
        BOOL stroke = (p->flags & A5MaliProfileStrokeSourceOver) != 0;
        if (coverage || stroke) {
            /* Audited QC Spec: coverage overrides RT0/1 off and RT2 Red/Add.
             * Stroke S=0 enables only RT0; original full formats are retained. */
            MTLColorWriteMask mask = coverage ? (i == 2 ? MTLColorWriteMaskRed : MTLColorWriteMaskNone)
                                             : (i == 0 ? MTLColorWriteMaskAll : MTLColorWriteMaskNone);
            if (a.writeMask != mask || a.isBlendingEnabled != (coverage ? i == 2 : i == 0)) return NO;
            if (!a.isBlendingEnabled) continue;
            if (a.rgbBlendOperation != MTLBlendOperationAdd ||
                a.sourceRGBBlendFactor != MTLBlendFactorOne ||
                a.destinationRGBBlendFactor != (coverage ? MTLBlendFactorOne : MTLBlendFactorOneMinusSourceAlpha)) return NO;
            if (stroke && (a.alphaBlendOperation != MTLBlendOperationAdd ||
                a.sourceAlphaBlendFactor != MTLBlendFactorOne ||
                a.destinationAlphaBlendFactor != MTLBlendFactorOneMinusSourceAlpha)) return NO;
        } else {
            if (p->colorFormats[i] && a.writeMask != MTLColorWriteMaskAll) return NO;
            if (a.isBlendingEnabled &&
                (!(p->flags & A5MaliProfileSourceOverBlend) || !p->colorFormats[i] ||
                 a.rgbBlendOperation != MTLBlendOperationAdd ||
                 a.alphaBlendOperation != MTLBlendOperationAdd ||
                 a.sourceRGBBlendFactor != MTLBlendFactorOne ||
                 a.sourceAlphaBlendFactor != MTLBlendFactorOne ||
                 a.destinationRGBBlendFactor != MTLBlendFactorOneMinusSourceAlpha ||
                 a.destinationAlphaBlendFactor != MTLBlendFactorOneMinusSourceAlpha)) return NO;
        }
    }
    MTLVertexDescriptor *v = d.vertexDescriptor;
    for (NSUInteger i = 0; i < 31; ++i) {
        const A5MaliCompiledVertexAttribute *want = NULL;
        for (uint32_t j = 0; j < p->attributeCount; ++j)
            if (p->attributes[j].index == i) want = &p->attributes[j];
        MTLVertexAttributeDescriptor *a = v.attributes[i];
        if (a.format != (want ? want->format : MTLVertexFormatInvalid)) return NO;
        if (want && (a.offset != want->offset || a.bufferIndex != want->bufferIndex)) return NO;
    }
    for (uint32_t i = 0; i < p->layoutCount; ++i) {
        const A5MaliCompiledVertexLayout *want = &p->layouts[i];
        MTLVertexBufferLayoutDescriptor *a = v.layouts[want->index];
        if (a.stride != want->stride || a.stepFunction != want->stepFunction ||
            a.stepRate != want->stepRate) return NO;
    }
    return YES;
}

const A5MaliCompiledProfile *A5MaliSelectCompiledProfile(
    MTLRenderPipelineDescriptor *descriptor, NSError **error)
{
    if (error) *error = nil;
    id vertex = descriptor.vertexFunction, fragment = descriptor.fragmentFunction;
    if (!descriptor || ![vertex isMemberOfClass:[A5MaliMetalFunction class]] ||
        ![fragment isMemberOfClass:[A5MaliMetalFunction class]] ||
        [vertex library] != [fragment library] || [vertex device] != [fragment device] ||
        [vertex functionType] != MTLFunctionTypeVertex ||
        [fragment functionType] != MTLFunctionTypeFragment) {
        if (error) *error = libraryError(@"compiled pipeline requires authenticated same-library functions");
        return NULL;
    }
    size_t count = 0;
    const A5MaliCompiledProfile *profiles = A5MaliCompiledProfiles(&count);
    for (size_t i = 0; i < count; ++i) {
        const A5MaliCompiledProfile *p = &profiles[i];
        if ([[vertex name] isEqualToString:[NSString stringWithUTF8String:p->vertexName]] &&
            [[fragment name] isEqualToString:[NSString stringWithUTF8String:p->fragmentName]] &&
            compiledDescriptorMatches(p, descriptor)) return p;
    }
    if (error) *error = libraryError(@"no compiled pair matches the complete attachment and vertex-layout contract");
    return NULL;
}
