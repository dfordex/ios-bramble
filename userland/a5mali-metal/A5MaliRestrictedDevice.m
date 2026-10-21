/* SPDX-License-Identifier: MIT */
#import "A5MaliRestrictedDevice.h"

@interface A5MaliReadSurfCandidate (PrivateInit)
- (instancetype)initWithDevice:(A5MaliRestrictedDevice *)device;
@end

@implementation A5MaliRestrictedDevice {
    A5MaliDevice *_privateDevice;
}

- (A5MaliDevice *)privateDevice { return _privateDevice; }

- (instancetype)initWithAcceleratorPort:(io_service_t)service
{
    if (!service || !IOObjectConformsTo(service, "A5XELTEGPU"))
        return nil;
    if ((self = [super init])) {
        _privateDevice = [[A5MaliDevice alloc] initWithService:service
                                                         error:NULL];
        if (!_privateDevice)
            return nil;
    }
    return self;
}

- (A5MaliSurface *)importPrivateBGRA8Surface:(IOSurfaceRef)surface
                                       usage:(uint32_t)usage
                                       error:(NSError * _Nullable * _Nullable)error
{
    return [_privateDevice importSurface:surface usage:usage error:error];
}

- (A5MaliCommandQueue *)newPrivateCommandQueue
{
    return [_privateDevice newCommandQueue];
}

- (A5MaliReadSurfCandidate *)newPrivateReadSurfCandidateWithDescriptor:
    (MTLRenderPipelineDescriptor *)descriptor
{
    if (A5MaliInspectReadSurfPipelineDescriptor(descriptor) !=
        A5MaliPipelineShapeReadSurfCandidate)
        return nil;
    return [[A5MaliReadSurfCandidate alloc] initWithDevice:self];
}

#ifdef A5_MALI_HOST_TEST
- (instancetype)initWithTransport:(A5MaliTransport)transport context:(void *)context
{
    return [self initWithTransport:transport context:context
        commandCapabilities:15];
}

- (instancetype)initWithTransport:(A5MaliTransport)transport context:(void *)context
             commandCapabilities:(uint32_t)commands
{
    if ((self = [super init]))
        _privateDevice = [[A5MaliDevice alloc] initWithTransport:transport
            context:context commandCapabilities:commands operationCapabilities:127];
    return _privateDevice ? self : nil;
}
#endif

- (id)newPrivateRenderPipelineWithVertex:(NSString *)vertex
                                fragment:(NSString *)fragment
                                   error:(NSError * _Nullable * _Nullable)error
{
    (void)vertex;
    (void)fragment;
    if (error)
        *error = [NSError errorWithDomain:@"com.orhunnx.a5xelte.mali"
                                    code:kIOReturnUnsupported userInfo:nil];
    return nil;
}

@end
