/* SPDX-License-Identifier: MIT
 * Host smoke for the user's locally staged QuartzCore metallib. It is passed
 * by environment; this test never copies it into the repository.
 */
#import "A5MaliRestrictedDevice.h"
#include <assert.h>
#include <stdlib.h>

static kern_return_t unusedTransport(void *context, uint32_t selector,
    const void *input, size_t inputSize, void *output, size_t *outputSize)
{
    (void)context; (void)selector; (void)input; (void)inputSize;
    (void)output; (void)outputSize;
    assert(0 && "library and pipeline validation must not submit a GPU job");
    return KERN_FAILURE;
}

static MTLRenderPipelineDescriptor *descriptor(A5MaliMetalLibrary *library)
{
    MTLRenderPipelineDescriptor *desc = [MTLRenderPipelineDescriptor new];
    desc.vertexFunction = (id<MTLFunction>)
        [library newFunctionWithName:@"read_surf_vert"];
    desc.fragmentFunction = (id<MTLFunction>)
        [library newFunctionWithName:@"read_surf_frag"];
    desc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    desc.inputPrimitiveTopology = MTLPrimitiveTopologyClassTriangle;
    return desc;
}

@interface MTLFunctionDescriptor (A5MaliDescriptorTest)
- (void)setPipelineOptions:(NSUInteger)options;
- (void)setPluginData:(NSDictionary *)data;
- (void)setPrivateFunctions:(NSArray *)functions;
@end

static void rejectFunction(A5MaliMetalLibrary *library,
                          MTLFunctionDescriptor *descriptor)
{
    NSError *error = nil;
    assert(![library newFunctionWithDescriptor:descriptor error:&error]);
    assert(error.code == kIOReturnUnsupported);
    assert([error.domain isEqualToString:@"com.orhunnx.a5xelte.mali"]);
    assert(![library newFunctionWithDescriptor:descriptor error:NULL]);
}

static void functionDescriptors(A5MaliMetalLibrary *library)
{
    for (NSString *name in library.functionNames) {
        MTLFunctionDescriptor *desc = [MTLFunctionDescriptor functionDescriptor];
        desc.name = name;
        NSError *error = nil;
        A5MaliMetalFunction *function =
            [library newFunctionWithDescriptor:desc error:&error];
        assert(function && !error && function.library == library);
        assert([function.name isEqualToString:name]);
        assert(function.functionType == ([name hasSuffix:@"vert"] ?
            MTLFunctionTypeVertex : MTLFunctionTypeFragment));
    }

    rejectFunction(library, nil);
    rejectFunction(library, (MTLFunctionDescriptor *)[NSObject new]);
    MTLFunctionDescriptor *desc = [MTLFunctionDescriptor functionDescriptor];
    rejectFunction(library, desc);
    desc.name = @"unimplemented_frag";
    rejectFunction(library, desc);
    desc.name = @"read_surf_frag";
    desc.constantValues = [MTLFunctionConstantValues new];
    rejectFunction(library, desc);
    desc.constantValues = nil;
    desc.specializedName = @"";
    rejectFunction(library, desc);
    desc.specializedName = nil;
    desc.options = MTLFunctionOptionCompileToBinary;
    rejectFunction(library, desc);
    desc.options = MTLFunctionOptionNone;
    desc.binaryArchives = @[(id<MTLBinaryArchive>)[NSObject new]];
    rejectFunction(library, desc);
    desc.binaryArchives = nil;
    if ([desc respondsToSelector:@selector(setPipelineOptions:)]) {
        [desc setPipelineOptions:1];
        rejectFunction(library, desc);
        [desc setPipelineOptions:0];
    }
    if ([desc respondsToSelector:@selector(setPluginData:)]) {
        [desc setPluginData:@{}];
        rejectFunction(library, desc);
        [desc setPluginData:nil];
    }
    if ([desc respondsToSelector:@selector(setPrivateFunctions:)]) {
        [desc setPrivateFunctions:@[[NSObject new]]];
        rejectFunction(library, desc);
        [desc setPrivateFunctions:@[]];
    }
}

int main(void)
{
    @autoreleasepool {
        int unusedContext = 0;
        A5MaliRestrictedDevice *disabled = [[A5MaliRestrictedDevice alloc]
            initWithTransport:unusedTransport context:&unusedContext
            commandCapabilities:15];
        A5MaliRestrictedDevice *enabled = [[A5MaliRestrictedDevice alloc]
            initWithTransport:unusedTransport context:&unusedContext
            commandCapabilities:31];
        assert(disabled && enabled);
        NSError *error = nil;
        assert(![enabled newLibraryWithURL:
            [NSURL URLWithString:@"https://example.invalid/default.metallib"]
            error:&error] && error.code == kIOReturnUnsupported);
        const uint8_t bad[] = {'M', 'T', 'L', 'B', 0};
        dispatch_data_t badData = dispatch_data_create(bad, sizeof(bad),
            dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0),
            DISPATCH_DATA_DESTRUCTOR_DEFAULT);
        error = nil;
        assert(![enabled newLibraryWithData:badData error:&error] &&
            error.code == kIOReturnUnsupported);

        const char *path = getenv("A5_MALI_STOCK_QUARTZCORE_METALLIB");
        if (!path) return 0;
        NSURL *url = [NSURL fileURLWithPath:
            [NSString stringWithUTF8String:path]];
        error = nil;
        A5MaliMetalLibrary *library =
            [enabled newLibraryWithURL:url error:&error];
        assert(library && !error && library.device == enabled);
        assert(library.functionNames.count == 2);
        assert(![library newFunctionWithName:@"unimplemented_frag"]);
        A5MaliMetalFunction *vertex =
            [library newFunctionWithName:@"read_surf_vert"];
        A5MaliMetalFunction *fragment =
            [library newFunctionWithName:@"read_surf_frag"];
        assert(vertex && fragment);
        assert(vertex.functionType == MTLFunctionTypeVertex);
        assert(fragment.functionType == MTLFunctionTypeFragment);
        assert(vertex.library == fragment.library);
        functionDescriptors(library);

        NSData *stockBytes = [NSData dataWithContentsOfURL:url];
        dispatch_data_t stockData = dispatch_data_create(stockBytes.bytes,
            stockBytes.length, dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0),
            DISPATCH_DATA_DESTRUCTOR_DEFAULT);
        error = nil;
        A5MaliMetalLibrary *fromData =
            [enabled newLibraryWithData:stockData error:&error];
        assert(fromData && !error && fromData.device == enabled);

        MTLRenderPipelineDescriptor *desc = descriptor(library);
        id pipeline = [enabled newRenderPipelineStateWithDescriptor:desc
            error:&error];
        assert([pipeline isKindOfClass:[A5MaliReadSurfCandidate class]] &&
            !error);
        error = nil;
        assert(![disabled newRenderPipelineStateWithDescriptor:desc
            error:&error] && error.code == kIOReturnUnsupported);
        desc.colorAttachments[0].blendingEnabled = YES;
        error = nil;
        assert(![enabled newRenderPipelineStateWithDescriptor:desc
            error:&error] && error.code == kIOReturnUnsupported);

        NSMutableData *changed = [stockBytes mutableCopy];
        assert(changed.length == 1014944);
        ((uint8_t *)changed.mutableBytes)[changed.length - 1] ^= 1;
        dispatch_data_t changedData = dispatch_data_create(changed.bytes,
            changed.length, dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0),
            DISPATCH_DATA_DESTRUCTOR_DEFAULT);
        error = nil;
        assert(![enabled newLibraryWithData:changedData error:&error] &&
            error.code == kIOReturnUnsupported);
    }
    return 0;
}
