/* SPDX-License-Identifier: MIT
 * Read-only preflight for the staged iOS 16 Metal provider boundary.
 * This file does not register an accelerator or publish a Metal device.
 */
#ifndef A5_MALI_DISCOVERY_AUDIT_H
#define A5_MALI_DISCOVERY_AUDIT_H

#import <Foundation/Foundation.h>
#include <stdint.h>

typedef enum {
    A5MaliDiscoveryMissingClass        = 1u << 0,
    A5MaliDiscoveryMissingBase         = 1u << 1,
    A5MaliDiscoveryMissingInitializer  = 1u << 2,
    A5MaliDiscoveryMissingMetal        = 1u << 3,
    A5MaliDiscoveryMissingMetalSPI     = 1u << 4,
    A5MaliDiscoveryMissingRenderPath   = 1u << 5,
    A5MaliDiscoveryMissingResources    = 1u << 6,
    A5MaliDiscoveryMissingQueue        = 1u << 7,
} A5MaliDiscoveryDeficiency;

/* A zero ABI mask is only a static selector/protocol checkpoint. It is not
 * permission to set MetalPluginName or to advertise IOAcceleratorES: command
 * execution, shader translation, resource lifetime, and phone proof are
 * separate requirements.
 */
uint32_t A5MaliAuditMetalProviderClass(Class _Nullable providerClass);

#endif
