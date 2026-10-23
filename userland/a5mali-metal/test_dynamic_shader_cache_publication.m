/* SPDX-License-Identifier: MIT
 * Read-only integration against a private worker publication, no GPU execution.
 */
#import "A5MaliDynamicShaderCache.h"
#include <assert.h>
#include <unistd.h>
uid_t A5MaliDynamicShaderCacheTestUID(void) { return geteuid(); }
int main(int argc, char **argv) {
    @autoreleasepool {
        assert(argc == 2);
        NSData *data = [NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[1]]];
        NSMutableDictionary *request = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:NULL];
        assert([request isKindOfClass:NSDictionary.class]);
        NSString *requestID = request[@"request_id"];
        assert([request[@"owner_uid"] unsignedIntegerValue] == geteuid());
        [request removeObjectForKey:@"request_id"];
        [request removeObjectForKey:@"owner_uid"];
        NSError *error = nil;
        A5MaliDynamicShaderCacheEntry *entry = A5MaliLoadDynamicShaderStage(requestID, request, &error);
        if (!entry) NSLog(@"%@", error);
        assert(entry && !error && entry.shader->bytes && entry.shader->byteCount);
        assert([entry.functionPayload isEqual:request]);
        for (unsigned i = 0; i < entry.resourceCount; ++i) {
            const A5MaliCompiledResource *r = entry.resources+i;
            if (r->kind == A5MaliResourceBuffer)
                assert(r->uniformBytes && r->nativeIndex && r->nativeIndex < 8);
        }
        printf("worker dynamic publication loaded: stage=%u bytes=%u resources=%u pushes=%u attrs=%u layouts=%u (no GPU execution)\n", entry.stage, entry.shader->byteCount, entry.resourceCount, entry.pushFieldCount, entry.attributeCount, entry.layoutCount);
    }
    return 0;
}
