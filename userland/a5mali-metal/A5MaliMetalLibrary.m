/* SPDX-License-Identifier: MIT
 * Exact stock QuartzCore shader-library identity and authenticated native
 * family registry. No metallib or translated shader bytes are distributed.
 */
#import "A5MaliRestrictedDevice.h"
#import "A5MaliCompiledRegistry.h"
#import "A5MaliShaderCompileRequest.h"
#import <CommonCrypto/CommonDigest.h>
#include <string.h>
#include <stdatomic.h>
#include <stdio.h>

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

const A5MaliCompiledFunctionConstant *A5MaliCompiledConstantsForProfile(uint32_t profileID,size_t *count)
{
    if(count)*count=0;
#ifdef A5_MALI_HAS_GENERIC_600
    if(profileID==600 && A5MaliCompiledProfileForID(600)) {
        if(count)*count=sizeof(kA5MaliProfile600Constants)/sizeof(kA5MaliProfile600Constants[0]);
        return kA5MaliProfile600Constants;
    }
#endif
#ifdef A5_MALI_HAS_GENERIC_601
    if(profileID==601 && A5MaliCompiledProfileForID(601)) {
        if(count)*count=sizeof(kA5MaliProfile601Constants)/sizeof(kA5MaliProfile601Constants[0]);
        return kA5MaliProfile601Constants;
    }
#endif
#ifdef A5_MALI_HAS_GENERIC_602
    if(profileID==602 && A5MaliCompiledProfileForID(602)) {
        if(count)*count=sizeof(kA5MaliProfile602Constants)/sizeof(kA5MaliProfile602Constants[0]);
        return kA5MaliProfile602Constants;
    }
#endif
#ifdef A5_MALI_HAS_GENERIC_603
    if(profileID==603 && A5MaliCompiledProfileForID(603)) {
        if(count)*count=sizeof(kA5MaliProfile603Constants)/sizeof(kA5MaliProfile603Constants[0]);
        return kA5MaliProfile603Constants;
    }
#endif
#if !defined(A5_MALI_HAS_GENERIC_600) && !defined(A5_MALI_HAS_GENERIC_601) && !defined(A5_MALI_HAS_GENERIC_602) && !defined(A5_MALI_HAS_GENERIC_603)
    (void)profileID;
#endif
    return NULL;
}

/* Fragment and vertex constants are independent Metal specializations. A
 * function may be reused by multiple compiled pipeline profiles when its exact
 * typed constant contract is identical; no shader name is substituted. */
const A5MaliCompiledFunctionConstant *A5MaliCompiledVertexConstantsForProfile(uint32_t profileID,size_t *count)
{
    if(count)*count=0;
#ifdef A5_MALI_HAS_GENERIC_602
    if(profileID==602 && A5MaliCompiledProfileForID(602)) {
        if(count)*count=sizeof(kA5MaliProfile602VertexConstants)/sizeof(kA5MaliProfile602VertexConstants[0]);
        return kA5MaliProfile602VertexConstants;
    }
#endif
#ifdef A5_MALI_HAS_GENERIC_603
    if(profileID==603 && A5MaliCompiledProfileForID(603)) {
        if(count)*count=sizeof(kA5MaliProfile603VertexConstants)/sizeof(kA5MaliProfile603VertexConstants[0]);
        return kA5MaliProfile603VertexConstants;
    }
#endif
#if !defined(A5_MALI_HAS_GENERIC_602) && !defined(A5_MALI_HAS_GENERIC_603)
    (void)profileID;
#endif
    return NULL;
}

static const A5MaliCompiledFunctionConstant *constantsForStage(uint32_t profileID,
    MTLFunctionType stage,size_t *count)
{
    return stage==MTLFunctionTypeVertex?
        A5MaliCompiledVertexConstantsForProfile(profileID,count):
        A5MaliCompiledConstantsForProfile(profileID,count);
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

/* Exact iOS16 MTLFunctionConstantSPI. The returned arrays own copied values;
 * no object layout or private storage offset is assumed. */
@interface MTLFunctionConstantValues (A5MaliConstantCapture)
- (NSArray *)newNamedConstantArray;
- (NSArray *)newIndexedConstantArray;
@end
@protocol A5MaliConstantRecord
- (NSString *)name;
- (NSUInteger)index;
- (MTLDataType)dataType;
- (const void *)data;
@end

static NSString *boundedFunctionIdentifier(NSString *name)
{
    if (![name isKindOfClass:[NSString class]] || !name.length || name.length>128)
        return @"<invalid>";
    static NSCharacterSet *invalid;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        invalid=[[NSCharacterSet characterSetWithCharactersInString:
            @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"] invertedSet];
    });
    return [name rangeOfCharacterFromSet:invalid].location==NSNotFound ? name : @"<invalid>";
}

static void logConstantArray(NSArray *array,BOOL indexed,unsigned request)
{
    if (![array isKindOfClass:[NSArray class]]) {
        fprintf(stderr,"A5XELTE Metal specialize: request=%u kind=%s unavailable=1\n",
            request,indexed?"indexed":"named");
        return;
    }
    fprintf(stderr,"A5XELTE Metal specialize: request=%u kind=%s count=%lu truncated=%u\n",
        request,indexed?"indexed":"named",(unsigned long)array.count,array.count>64);
    Class expected=NSClassFromString(indexed?@"MTLIndexedConstantValue":@"MTLNamedConstantValue");
    for (NSUInteger i=0;i<MIN(array.count,(NSUInteger)64);++i) {
        id<A5MaliConstantRecord> entry=array[i];
        if (!expected || ![(id)entry isMemberOfClass:expected] ||
            ![(id)entry respondsToSelector:@selector(dataType)] ||
            ![(id)entry respondsToSelector:@selector(data)] ||
            ![(id)entry respondsToSelector:indexed?@selector(index):@selector(name)]) {
            fprintf(stderr,"A5XELTE Metal specialize: request=%u entry=%lu invalid=1\n",
                request,(unsigned long)i);continue;
        }
        MTLDataType type=entry.dataType;
        /* QuartzCore uses UChar, UChar3 and Bool. In particular, type51 is
         * THREE UChar bytes, not UInt (type33). Never read an unknown width. */
        NSUInteger bytes=type==MTLDataTypeUChar3?3:
            (type==MTLDataTypeUChar || type==MTLDataTypeBool)?1:0;
        char raw[7]="";
        if (bytes && entry.data) {
            uint8_t value[3];memcpy(value,entry.data,bytes);
            for (NSUInteger j=0;j<bytes;++j)snprintf(raw+j*2,3,"%02x",value[j]);
        }
        NSString *key=indexed?[NSString stringWithFormat:@"index_%lu",(unsigned long)entry.index]:
            boundedFunctionIdentifier(entry.name);
        fprintf(stderr,"A5XELTE Metal specialize: request=%u key=%s type=%lu bytes=%lu raw=%s\n",
            request,key.UTF8String,(unsigned long)type,(unsigned long)bytes,
            bytes&&entry.data?raw:"unavailable");
    }
}

static void forwardFunctionSpecialization(NSString *name,MTLFunctionConstantValues *values)
{
    MTLFunctionType stage=0;
    if([name hasPrefix:@"fixed_vert_"]||[name containsString:@"_vert"])stage=MTLFunctionTypeVertex;
    else if([name hasPrefix:@"fixed_frag_"]||[name containsString:@"_frag"])stage=MTLFunctionTypeFragment;
    if(!stage)return; /* Do not invent a stage for an unclassified source name. */
    NSError *error=nil;
    NSDictionary *payload=A5MaliShaderCompileFunctionPayload(name,stage,values,&error);
    NSString *requestID=nil;
    A5MaliShaderForwardResult result=payload?A5MaliForwardShaderCompileRequest(payload,&requestID,&error):A5MaliShaderForwardFailed;
    static atomic_uint receipts;
    if(atomic_fetch_add_explicit(&receipts,1,memory_order_relaxed)<16)
        fprintf(stderr,"A5XELTE Metal compile request: function=%s result=%ld request=%s\n",
            boundedFunctionIdentifier(name).UTF8String,(long)result,requestID.UTF8String?:"unavailable");
}

static void logFunctionSpecialization(NSString *name,MTLFunctionConstantValues *values)
{
    forwardFunctionSpecialization(name,values);
    static atomic_uint requests;
    unsigned request=atomic_fetch_add_explicit(&requests,1,memory_order_relaxed);
    if(request>=4)return;
    fprintf(stderr,"A5XELTE Metal specialize: request=%u function=%s constants=%u result=unsupported\n",
        request,boundedFunctionIdentifier(name).UTF8String,values!=nil);
    if (!values)return;
    if (![values isKindOfClass:[MTLFunctionConstantValues class]] ||
        ![values respondsToSelector:@selector(newNamedConstantArray)] ||
        ![values respondsToSelector:@selector(newIndexedConstantArray)]) {
        fprintf(stderr,"A5XELTE Metal specialize: request=%u accessor_unavailable=1\n",request);return;
    }
    NSArray *named=[values newNamedConstantArray];
    NSArray *indexed=[values newIndexedConstantArray];
    logConstantArray(named,NO,request);
    logConstantArray(indexed,YES,request);
}

static BOOL constantsMatchProfile(MTLFunctionConstantValues *values,uint32_t profileID,MTLFunctionType stage)
{
    size_t count=0;
    const A5MaliCompiledFunctionConstant *expected=constantsForStage(profileID,stage,&count);
    if(!expected || !count || count>64 ||
        ![values isKindOfClass:[MTLFunctionConstantValues class]] ||
        ![values respondsToSelector:@selector(newNamedConstantArray)] ||
        ![values respondsToSelector:@selector(newIndexedConstantArray)])return NO;
    MTLFunctionConstantValues *snapshot=[values copy];
    NSArray *named=[snapshot newNamedConstantArray],*indexed=[snapshot newIndexedConstantArray];
    if(![named isKindOfClass:[NSArray class]] || ![indexed isKindOfClass:[NSArray class]] ||
        named.count!=count || indexed.count)return NO;
    Class valueClass=NSClassFromString(@"MTLNamedConstantValue");
    NSMutableSet<NSString *> *seen=[NSMutableSet new];
    for(id<A5MaliConstantRecord> entry in named) {
        if(!valueClass || ![(id)entry isMemberOfClass:valueClass])return NO;
        NSString *name=entry.name;
        if(![name isKindOfClass:[NSString class]] || !name.length || name.length>128 || [seen containsObject:name])return NO;
        [seen addObject:name];
        const A5MaliCompiledFunctionConstant *match=NULL;
        for(size_t i=0;i<count;++i)if([name isEqualToString:[NSString stringWithUTF8String:expected[i].name]]){match=expected+i;break;}
        if(!match || entry.dataType!=match->dataType || !entry.data ||
            !((match->dataType==MTLDataTypeUChar3 && match->byteCount==3) ||
              ((match->dataType==MTLDataTypeBool || match->dataType==MTLDataTypeUChar) && match->byteCount==1)) ||
            memcmp(entry.data,match->raw,match->byteCount))return NO;
    }
    return YES;
}

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
    uint32_t _specializationProfileID;
    NSDictionary *_compileRequestPayload;
}
- (instancetype)initWithLibrary:(A5MaliMetalLibrary *)library
                           name:(NSString *)name
                           type:(MTLFunctionType)type;
- (instancetype)initWithLibrary:(A5MaliMetalLibrary *)library name:(NSString *)name
    type:(MTLFunctionType)type specializationProfileID:(uint32_t)profileID;
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
                size_t constants=0;
                A5MaliCompiledVertexConstantsForProfile(profiles[i].profileID,&constants);
                if(constants)continue;
                type = MTLFunctionTypeVertex; found = YES; break;
            }
            if ([name isEqualToString:[NSString stringWithUTF8String:profiles[i].fragmentName]]) {
                size_t constants=0;
                A5MaliCompiledConstantsForProfile(profiles[i].profileID,&constants);
                if(constants)continue; /* Required specialization cannot be omitted. */
                type = MTLFunctionTypeFragment; found = YES; break;
            }
        }
        if (!found) { logFunctionSpecialization(name,nil);return nil; }
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
    /* Unsupported options never bypass the authenticated function contract.
     * A nonnil constants object is compared by name, type and complete bytes. */
    MTLFunctionDescriptor *snapshot = [descriptor copy];
    if (snapshot.specializedName || snapshot.options ||
        snapshot.binaryArchives.count ||
        ([snapshot respondsToSelector:@selector(pipelineOptions)] &&
         snapshot.pipelineOptions) ||
        ([snapshot respondsToSelector:@selector(pluginData)] &&
         snapshot.pluginData) ||
        ([snapshot respondsToSelector:@selector(privateFunctions)] &&
         snapshot.privateFunctions.count)) {
        static atomic_uint rejectedDescriptors;
        if(atomic_fetch_add_explicit(&rejectedDescriptors,1,memory_order_relaxed)<4)
            fprintf(stderr,"A5XELTE Metal function descriptor: function=%s specialized_name=%u options=%llu archives=%lu pipeline_options=%llu plugin_data=%u private_functions=%lu result=unsupported\n",
                boundedFunctionIdentifier(snapshot.name).UTF8String,snapshot.specializedName!=nil,
                (unsigned long long)snapshot.options,(unsigned long)snapshot.binaryArchives.count,
                (unsigned long long)([snapshot respondsToSelector:@selector(pipelineOptions)]?snapshot.pipelineOptions:0),
                [snapshot respondsToSelector:@selector(pluginData)]&&snapshot.pluginData!=nil,
                (unsigned long)([snapshot respondsToSelector:@selector(privateFunctions)]?snapshot.privateFunctions.count:0));
        logFunctionSpecialization(snapshot.name,snapshot.constantValues);
        if (error) *error = libraryError(@"function specialization and archives are unsupported");
        return nil;
    }
    A5MaliMetalFunction *function = [self newFunctionWithName:snapshot.name
        constantValues:snapshot.constantValues error:error];
    if (!function && error)
        *error = libraryError(@"function is outside the authenticated compiled library profiles");
    return function;
}

- (A5MaliMetalFunction *)newFunctionWithName:(NSString *)name
                           constantValues:(MTLFunctionConstantValues *)constants
                                    error:(NSError **)error
{
    if (constants) {
        size_t profileCount=0;const A5MaliCompiledProfile *profiles=A5MaliCompiledProfiles(&profileCount);
        for(size_t i=0;i<profileCount;++i) {
            const A5MaliCompiledProfile *profile=profiles+i;
            if(profile->flags&A5MaliProfileNotExecutable)continue;
            for(MTLFunctionType stage=MTLFunctionTypeVertex;stage<=MTLFunctionTypeFragment;++stage) {
                const char *stageName=stage==MTLFunctionTypeVertex?profile->vertexName:profile->fragmentName;
                if(![name isEqualToString:[NSString stringWithUTF8String:stageName]] ||
                    !constantsMatchProfile(constants,profile->profileID,stage))continue;
                size_t constantCount=0;constantsForStage(profile->profileID,stage,&constantCount);
                static atomic_uint accepted;
                if(atomic_fetch_add_explicit(&accepted,1,memory_order_relaxed)<16)
                    fprintf(stderr,"A5XELTE Metal specialize: accepted profile=%u function=%s constants=%zu stage=%s\n",
                        profile->profileID,name.UTF8String,constantCount,stage==MTLFunctionTypeVertex?"vertex":"fragment");
                if(error)*error=nil;
                return [[A5MaliMetalFunction alloc]initWithLibrary:self name:name
                    type:stage specializationProfileID:profile->profileID];
            }
        }
        logFunctionSpecialization(name,constants);
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
    return [self initWithLibrary:library name:name type:type specializationProfileID:0];
}
- (instancetype)initWithLibrary:(A5MaliMetalLibrary *)library name:(NSString *)name
    type:(MTLFunctionType)type specializationProfileID:(uint32_t)profileID
{
    if ((self = [super init])) {
        _library = library;
        _name = [name copy];
        _functionType = type;
        _specializationProfileID=profileID;
        size_t count=0;const A5MaliCompiledFunctionConstant *expected=constantsForStage(profileID,type,&count);
        MTLFunctionConstantValues *values=count?[MTLFunctionConstantValues new]:nil;
        for(size_t i=0;i<count;++i)[values setConstantValue:expected[i].raw type:expected[i].dataType
            withName:[NSString stringWithUTF8String:expected[i].name]];
        _compileRequestPayload=A5MaliShaderCompileFunctionPayload(_name,type,values,NULL);
    }
    return self;
}
- (NSString *)name { return _name; }
- (MTLFunctionType)functionType { return _functionType; }
- (A5MaliMetalLibrary *)library { return _library; }
- (A5MaliRestrictedDevice *)device { return _library.device; }
- (uint32_t)specializationProfileID { return _specializationProfileID; }
- (NSDictionary *)compileRequestPayload { return _compileRequestPayload; }
@end

static NSString *compiledDescriptorMismatch(const A5MaliCompiledProfile *p,
                                      MTLRenderPipelineDescriptor *d)
{
    if (d.rasterSampleCount != 1) return @"rasterSampleCount must be1";
    if (d.maxVertexAmplificationCount != 1) return @"maxVertexAmplificationCount must be1";
    if (d.supportIndirectCommandBuffers) return @"indirect command buffers unsupported";
    if (!d.isRasterizationEnabled || d.isAlphaToCoverageEnabled || d.isAlphaToOneEnabled)
        return @"rasterization/alpha-to-coverage/alpha-to-one state unsupported";
    if (d.depthAttachmentPixelFormat || d.stencilAttachmentPixelFormat)
        return @"depth/stencil attachments unsupported";
    if (d.inputPrimitiveTopology != MTLPrimitiveTopologyClassUnspecified &&
        d.inputPrimitiveTopology != MTLPrimitiveTopologyClassTriangle)
        return @"primitive topology must be triangle";
    for (NSUInteger i = 0; i < 8; ++i) {
        NSUInteger actual=d.colorAttachments[i].pixelFormat;
        if (actual != p->colorFormats[i]) return [NSString stringWithFormat:
            @"attachment%lu.pixelFormat actual=%lu expected=%u",(unsigned long)i,(unsigned long)actual,p->colorFormats[i]];
    }
    if (!p->attachmentContracts || !p->attachmentContractCount)
        return @"missing authenticated QuartzCore attachment contract";
    BOOL matched=NO;NSString *stateReason=nil;
    for (uint32_t c=0;c<p->attachmentContractCount;++c) {
        BOOL equal=YES;
        for (NSUInteger i=0;i<8;++i) {
            MTLRenderPipelineColorAttachmentDescriptor *a=d.colorAttachments[i];
            const A5MaliCompiledAttachmentState *want=&p->attachmentContracts[c].attachments[i];
            const NSUInteger actual[8]={a.writeMask,a.isBlendingEnabled,a.rgbBlendOperation,a.alphaBlendOperation,
                a.sourceRGBBlendFactor,a.destinationRGBBlendFactor,a.sourceAlphaBlendFactor,a.destinationAlphaBlendFactor};
            const uint32_t expected[8]={want->writeMask,want->blendEnabled,want->rgbOperation,want->alphaOperation,
                want->sourceRGB,want->destinationRGB,want->sourceAlpha,want->destinationAlpha};
            const char *names[8]={"writeMask","blendEnabled","rgbOperation","alphaOperation","sourceRGB","destinationRGB","sourceAlpha","destinationAlpha"};
            for(NSUInteger f=0;f<8;++f)if(actual[f]!=expected[f]) {
                if(!stateReason)stateReason=[NSString stringWithFormat:@"attachment%lu.%s actual=%lu expected=%u (QC contract%u)",
                    (unsigned long)i,names[f],(unsigned long)actual[f],expected[f],c];
                equal=NO;break;
            }
            if(!equal)break;
        }
        if(equal){matched=YES;break;}
    }
    if(!matched)return stateReason?:@"attachment state differs from every actual QC row";
    MTLVertexDescriptor *v = d.vertexDescriptor;
    for (NSUInteger i = 0; i < 31; ++i) {
        const A5MaliCompiledVertexAttribute *want = NULL;
        for (uint32_t j = 0; j < p->attributeCount; ++j)
            if (p->attributes[j].index == i) want = &p->attributes[j];
        MTLVertexAttributeDescriptor *a = v.attributes[i];
        if (a.format != (want ? want->format : MTLVertexFormatInvalid)) return @"vertex attribute/layout contract differs";
        if (want && (a.offset != want->offset || a.bufferIndex != want->bufferIndex)) return @"vertex attribute/layout contract differs";
    }
    for (uint32_t i = 0; i < p->layoutCount; ++i) {
        const A5MaliCompiledVertexLayout *want = &p->layouts[i];
        MTLVertexBufferLayoutDescriptor *a = v.layouts[want->index];
        if (a.stride != want->stride || a.stepFunction != want->stepFunction ||
            a.stepRate != want->stepRate) return @"vertex attribute/layout contract differs";
    }
    return nil;
}

static BOOL specializationIdentityMatches(A5MaliMetalFunction *function,
    const A5MaliCompiledProfile *profile,MTLFunctionType stage)
{
    size_t expectedCount=0,actualCount=0;
    const A5MaliCompiledFunctionConstant *expected=constantsForStage(profile->profileID,stage,&expectedCount);
    uint32_t identity=function.specializationProfileID;
    if(!expectedCount)return identity==0;
    const A5MaliCompiledProfile *origin=A5MaliCompiledProfileForID(identity);
    const A5MaliCompiledFunctionConstant *actual=constantsForStage(identity,stage,&actualCount);
    if(!origin||!expected||!actual||expectedCount!=actualCount)return NO;
    const char *expectedName=stage==MTLFunctionTypeVertex?profile->vertexName:profile->fragmentName;
    const char *actualName=stage==MTLFunctionTypeVertex?origin->vertexName:origin->fragmentName;
    if(strcmp(expectedName,actualName))return NO;
    for(size_t i=0;i<expectedCount;++i) {
        if(strcmp(expected[i].name,actual[i].name)||expected[i].dataType!=actual[i].dataType||
            expected[i].byteCount!=actual[i].byteCount||
            memcmp(expected[i].raw,actual[i].raw,expected[i].byteCount))return NO;
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
    NSString *reason=nil;BOOL knownPair=NO;int reasonScore=-1;
    for (size_t i = 0; i < count; ++i) {
        const A5MaliCompiledProfile *p = &profiles[i];
        if (p->flags&A5MaliProfileNotExecutable) continue;
        if ([[vertex name] isEqualToString:[NSString stringWithUTF8String:p->vertexName]] &&
            [[fragment name] isEqualToString:[NSString stringWithUTF8String:p->fragmentName]]) {
            if(!specializationIdentityMatches(vertex,p,MTLFunctionTypeVertex) ||
                !specializationIdentityMatches(fragment,p,MTLFunctionTypeFragment)) {
                knownPair=YES;
                if(reasonScore<0 && !reason)reason=@"function specialization identity differs from the compiled profile";
                continue;
            }
            knownPair=YES;NSString *mismatch=compiledDescriptorMismatch(p,descriptor);
            if(!mismatch)return p;
            int score=0;for(NSUInteger a=0;a<8;++a)
                score+=(descriptor.colorAttachments[a].pixelFormat==p->colorFormats[a]);
            /* Same named shader has several genuine attachment profiles.
             * Report the closest full-format contract, not the first unrelated
             * format variant, while accepting only exact complete contracts. */
            if(score>reasonScore){reasonScore=score;reason=[NSString stringWithFormat:@"profile%u: %@",p->profileID,mismatch];}
        }
    }
    if (error) *error = libraryError(reason?: (knownPair?@"no exact compiled descriptor contract":
        @"no executable compiled pair for authenticated function names"));
    return NULL;
}
