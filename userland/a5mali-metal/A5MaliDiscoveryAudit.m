/* SPDX-License-Identifier: MIT */
#import "A5MaliDiscoveryAudit.h"
#import <objc/runtime.h>

static bool isSubclassOf(Class candidate, Class base)
{
    for (Class current = candidate; current; current = class_getSuperclass(current))
        if (current == base)
            return true;
    return false;
}

static bool hasSelectors(Class providerClass, const char *const *names,
                         size_t count)
{
    for (size_t i = 0; i < count; ++i) {
        SEL selector = sel_registerName(names[i]);
        if (!class_getInstanceMethod(providerClass, selector))
            return false;
    }
    return true;
}

uint32_t A5MaliAuditMetalProviderClass(Class providerClass)
{
    if (!providerClass)
        return A5MaliDiscoveryMissingClass | A5MaliDiscoveryMissingBase |
            A5MaliDiscoveryMissingInitializer | A5MaliDiscoveryMissingMetal |
            A5MaliDiscoveryMissingMetalSPI |
            A5MaliDiscoveryMissingRenderPath |
            A5MaliDiscoveryMissingResources | A5MaliDiscoveryMissingQueue;

    uint32_t failures = 0;
    Class base = objc_getClass("_MTLDevice");
    if (!base || !isSubclassOf(providerClass, base))
        failures |= A5MaliDiscoveryMissingBase;
    if (!class_getInstanceMethod(providerClass,
            sel_registerName("initWithAcceleratorPort:")))
        failures |= A5MaliDiscoveryMissingInitializer;

    Protocol *publicProtocol = objc_getProtocol("MTLDevice");
    Protocol *privateProtocol = objc_getProtocol("MTLDeviceSPI");
    if (!publicProtocol || !class_conformsToProtocol(providerClass, publicProtocol))
        failures |= A5MaliDiscoveryMissingMetal;
    if (!privateProtocol || !class_conformsToProtocol(providerClass, privateProtocol))
        failures |= A5MaliDiscoveryMissingMetalSPI;

    /* These are the minimum QuartzCore selectors seen in the locally staged
     * iOS 16.7.16 cache. A generic compositor needs many more variants.
     */
    static const char *const render[] = {
        "newDefaultLibrary", "newLibraryWithURL:error:",
        "newRenderPipelineStateWithDescriptor:error:",
        "newComputePipelineStateWithFunction:error:",
    };
    static const char *const resources[] = {
        "newTextureWithDescriptor:",
        "newTextureWithDescriptor:iosurface:plane:",
        "newBufferWithLength:options:",
        "newSamplerStateWithDescriptor:",
        "newDepthStencilStateWithDescriptor:",
    };
    static const char *const queue[] = { "newCommandQueue" };
    if (!hasSelectors(providerClass, render, sizeof(render) / sizeof(render[0])))
        failures |= A5MaliDiscoveryMissingRenderPath;
    if (!hasSelectors(providerClass, resources,
                      sizeof(resources) / sizeof(resources[0])))
        failures |= A5MaliDiscoveryMissingResources;
    if (!hasSelectors(providerClass, queue, sizeof(queue) / sizeof(queue[0])))
        failures |= A5MaliDiscoveryMissingQueue;
    return failures;
}
