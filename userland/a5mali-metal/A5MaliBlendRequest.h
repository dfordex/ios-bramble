/* SPDX-License-Identifier: MIT */
#ifndef A5_MALI_BLEND_REQUEST_H
#define A5_MALI_BLEND_REQUEST_H
#import <Foundation/Foundation.h>
/* Immutable pipeline-dependent fragment variant. Blend constants are dynamic
 * draw data, never part of the compiled shader identity. Dual-source factors
 * require a second color output ABI, which this color0 backend does not have. */
static inline BOOL A5MaliValidBlendRequest(id state) {
 NSArray *keys=@[@"format",@"write_mask",@"rgb_operation",@"alpha_operation",
  @"source_rgb",@"destination_rgb",@"source_alpha",@"destination_alpha"];
 if(![state isKindOfClass:NSDictionary.class]||
  ![[NSSet setWithArray:[state allKeys]] isEqual:[NSSet setWithArray:keys]])return NO;
 for(NSString *key in keys){id n=state[key];
  unsigned limit=[key isEqual:@"format"]?80:[key isEqual:@"write_mask"]?15:
   [key hasSuffix:@"operation"]?4:14;
  if(![n isKindOfClass:NSNumber.class]||CFGetTypeID((__bridge CFTypeRef)n)==CFBooleanGetTypeID()||
   [n doubleValue]<0||[n doubleValue]>limit||[n doubleValue]!=(double)[n unsignedIntValue])return NO;
 }
 return [state[@"format"] isEqual:@80]||[state[@"format"] isEqual:@43];
}
#endif
