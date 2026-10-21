/* SPDX-License-Identifier: MIT
 * Exact stock QuartzCore shader-library identity for the bounded read_surf
 * render experiment. No metallib or translated shader bytes are distributed.
 */
#import "A5MaliRestrictedDevice.h"
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
    return @[@"read_surf_vert", @"read_surf_frag"];
}
- (A5MaliMetalFunction *)newFunctionWithName:(NSString *)name
{
    MTLFunctionType type;
    if ([name isEqualToString:@"read_surf_vert"])
        type = MTLFunctionTypeVertex;
    else if ([name isEqualToString:@"read_surf_frag"])
        type = MTLFunctionTypeFragment;
    else return nil;
    return [[A5MaliMetalFunction alloc] initWithLibrary:self name:name type:type];
}

- (A5MaliMetalFunction *)newFunctionWithDescriptor:(MTLFunctionDescriptor *)descriptor
                                            error:(NSError * _Nullable * _Nullable)error
{
    if (![descriptor isMemberOfClass:[MTLFunctionDescriptor class]]) {
        if (error) *error = libraryError(@"a plain function descriptor is required");
        return nil;
    }
    /* QuartzCore uses this selector for both ordinary and specialized shaders.
     * Only the two already authenticated, unspecialized translations exist.
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
        *error = libraryError(@"function is outside the authenticated read_surf pair");
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
