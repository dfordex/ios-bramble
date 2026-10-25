/* SPDX-License-Identifier: MIT
 * Translate the reflected Vulkan immutable state to the native sampler ABI.
 * Only implemented normalized, noncomparison, single-level states are valid.
 */
#ifndef A5_MALI_IMMUTABLE_SAMPLER_H
#define A5_MALI_IMMUTABLE_SAMPLER_H
#import <Foundation/Foundation.h>
#include <math.h>
#include "A5MaliCompiledRegistry.h"
static inline BOOL A5MaliDecodeImmutableSampler(NSDictionary *state,uint32_t native,
                                               A5MaliCompiledSampler *out) {
    NSArray *keys=@[@"mag_filter",@"min_filter",@"mipmap_mode",@"address_mode_u",
        @"address_mode_v",@"address_mode_w",@"mip_lod_bias",@"max_anisotropy",
        @"compare",@"min_lod",@"max_lod",@"border_color",@"reduction",@"border_components"];
    if(![state isKindOfClass:NSDictionary.class]||state.count!=keys.count||native>=4)return NO;
    for(NSString *key in keys)if(!state[key])return NO;
    for(NSString *key in @[@"max_anisotropy",@"compare",@"border_components"])
        if(state[key]!=NSNull.null)return NO;
    for(NSString *key in @[@"mag_filter",@"min_filter",@"mipmap_mode",@"address_mode_u",
        @"address_mode_v",@"address_mode_w",@"mip_lod_bias",@"min_lod",@"max_lod",@"border_color",@"reduction"]){
        id n=state[key];
        if(![n isKindOfClass:NSNumber.class]||CFGetTypeID((__bridge CFTypeRef)n)==CFBooleanGetTypeID()||
           !isfinite([n doubleValue]))return NO;
    }
    for(NSString *key in @[@"mag_filter",@"min_filter"])
        if(![state[key] isEqual:@0]&&![state[key] isEqual:@1])return NO;
    for(NSString *key in @[@"mipmap_mode",@"mip_lod_bias",@"border_color",@"reduction"])
        if(![state[key] isEqual:@0])return NO;
    unsigned modes[3];unsigned i=0;
    for(NSString *key in @[@"address_mode_u",@"address_mode_v",@"address_mode_w"]){
        if([state[key] isEqual:@0])modes[i++]=1; /* Vulkan repeat -> native repeat */
        else if([state[key] isEqual:@2])modes[i++]=0; /* clamp to edge */
        else if([state[key] isEqual:@3])modes[i++]=4; /* transparent black border */
        else return NO;
    }
    double min=[state[@"min_lod"] doubleValue],max=[state[@"max_lod"] doubleValue];
    if(min<0||max<min||max>15)return NO;
    if(out)*out=(A5MaliCompiledSampler){native,[state[@"min_filter"] unsignedIntValue],
        [state[@"mag_filter"] unsignedIntValue],0,modes[0],modes[1],modes[2],1,(float)min,(float)max};
    return YES;
}
#endif
