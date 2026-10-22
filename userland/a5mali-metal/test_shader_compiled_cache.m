/* SPDX-License-Identifier: MIT
 * Root-cache loader ownership/hash/ABI/lifetime regression. Operator supplies
 * actual private pinned602/603 native bytes; no shader bytes are in this source.
 */
#import "A5MaliShaderCompiledCache.h"
#include <assert.h>
#include <sys/stat.h>
#include <unistd.h>
#include <errno.h>
#ifndef A5_SHADER_COMPILED_CACHE_TEST_ROOT
#error "private cache test root required"
#endif
static NSString *const root=@A5_SHADER_COMPILED_CACHE_TEST_ROOT;
static NSString *const key=@"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
#ifndef A5_CACHE_TEST_PROFILE
#define A5_CACHE_TEST_PROFILE 602
#endif
#if A5_CACHE_TEST_PROFILE == 602
enum {testProfile=602,vertexLength=1808,fragmentLength=848,fragmentRegisters=6};
static NSString *const vs=@"3cdf2b0db0b9992ce887242e7cac282cd70c3f8051e3ace3e791a0b676193a79";
static NSString *const fs=@"e66041333f6452510cda4d0ee1f1c1edf443a12007a989871a1546791deb0834";
static NSString *const vertexConstants=@"d8b11a43b5075c7c8f179f6da7849edc5c5534f161590552da6b177007c8595f";
static NSString *const fragmentConstants=@"5e1fae69edcd5f51efdf3a4adbca80e9c7901844f942404208c0b2dc89bb7c7f";
static NSString *const otherConstants=@"57f61f4161d206f26026807dd822e5fae8713e3b9f183f381d116cddd6d40112";
#elif A5_CACHE_TEST_PROFILE == 603
enum {testProfile=603,vertexLength=2192,fragmentLength=976,fragmentRegisters=6};
static NSString *const vs=@"e0c51d2171b28c891677cdb1f1c98032bee0f03bb64af694a8321d711159fc96";
static NSString *const fs=@"b7ab26bc9a0da3ff4a5f87e73fe6aaab07680ae383a3fbdd9d8abc000387cd96";
static NSString *const vertexConstants=@"57f61f4161d206f26026807dd822e5fae8713e3b9f183f381d116cddd6d40112";
static NSString *const fragmentConstants=@"1314cb292bea03fb85537fdebb3919e65b76db1e99f72b12f7fb1abcd7c8d50d";
static NSString *const otherConstants=@"d8b11a43b5075c7c8f179f6da7849edc5c5534f161590552da6b177007c8595f";
#else
#error "only known602/603 cache tests exist"
#endif
static NSString *entryPath(void){return [root stringByAppendingPathComponent:key];}
static NSString *filePath(NSString *name){return [entryPath() stringByAppendingPathComponent:name];}
static NSDictionary *stage(NSString *name,NSString *sha,NSUInteger bytes,NSUInteger registers)
{
    return @{@"file":name,@"bytes":@(bytes),@"sha256":sha,@"first_tag":@5,
        @"work_registers":@(registers),@"tls_bytes":@0,@"wls_bytes":@0};
}
static NSMutableDictionary *receipt(void)
{
    return [@{@"schema":@1,@"request_id":key,@"profile_id":@(testProfile),@"source_library":@"quartzcore",
        @"metallib_sha256":@"11c74cc42ce5137b73d44d427f75764f886656d4ddb374422d56b609ed2762d9",
        @"gpu_id":@"07201000",@"compiler_abi":@1,@"recipe":[NSString stringWithFormat:@"quartzcore-generic-%u",testProfile],
        @"stage_compiled":@YES,@"pipeline_compatible":@NO,
        @"descriptor_sha256":key,
        @"vertex_constants_sha256":vertexConstants,@"fragment_constants_sha256":fragmentConstants,
        @"vertex":stage(@"vertex.midgard",vs,vertexLength,8),
        @"fragment":stage(@"fragment.midgard",fs,fragmentLength,fragmentRegisters)} mutableCopy];
}
static void writeFile(NSString *name,NSData *data)
{
    NSString *path=filePath(name);[NSFileManager.defaultManager removeItemAtPath:path error:NULL];
    assert([data writeToFile:path options:0 error:NULL]);assert(!chmod(path.fileSystemRepresentation,0444));
}
static void writeReceipt(NSDictionary *r)
{
    NSData *data=[NSJSONSerialization dataWithJSONObject:r options:NSJSONWritingSortedKeys error:NULL];
    assert(data);writeFile(@"receipt.json",data);
}
static void expectRejected(const A5MaliCompiledProfile *profile)
{
    static unsigned check;NSError *error=nil;
    id loaded=A5MaliLoadShaderCompiledCache(key,profile,&error);++check;
    if(loaded||!error||error.code==ENOENT)fprintf(stderr,"rejection check%u returned object=%u error=%ld\n",check,loaded!=nil,(long)error.code);
    assert(!loaded&&error&&error.code!=ENOENT);
}
int main(int argc,const char **argv)
{
    @autoreleasepool {
        assert(argc==3&&[root hasPrefix:@"/private/tmp/"]);
        NSData *vertex=[NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[1]]];
        NSData *fragment=[NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[2]]];
        assert(vertex.length==vertexLength&&fragment.length==fragmentLength);
        A5MaliCompiledPass pass={.passID=testProfile,.logicalTarget=0,
            .vertex={vertex.bytes,vertexLength,5,8,0,0,vs.UTF8String},
            .fragment={fragment.bytes,fragmentLength,5,fragmentRegisters,0,0,fs.UTF8String}};
        A5MaliCompiledProfile profile={.profileID=testProfile,.name="generic-cache-test",.vertexName="fixed_vert_lph_spc",
            .fragmentName="fixed_frag_lph_cph",.passes=&pass,.passCount=1,.colorFormats={80}};
        NSFileManager *fm=NSFileManager.defaultManager;[fm removeItemAtPath:root error:NULL];
        NSError *error=nil;assert(!A5MaliLoadShaderCompiledCache(key,&profile,&error)&&error.code==ENOENT);
        assert([fm createDirectoryAtPath:entryPath() withIntermediateDirectories:YES attributes:nil error:NULL]);
        assert(!chmod(root.fileSystemRepresentation,0755));assert(!chmod(entryPath().fileSystemRepresentation,0755));
        writeFile(@"vertex.midgard",vertex);writeFile(@"fragment.midgard",fragment);writeReceipt(receipt());
        A5MaliShaderCompiledCacheEntry *loaded=A5MaliLoadShaderCompiledCache(key,&profile,&error);
        assert(loaded&&!error&&loaded.profile!=&profile&&loaded.profile->passes!=&pass);
        assert(loaded.profile->passes[0].vertex.bytes!=vertex.bytes&&loaded.profile->passes[0].fragment.bytes!=fragment.bytes);
        assert(!memcmp(loaded.profile->passes[0].vertex.bytes,vertex.bytes,vertex.length));
        assert(!memcmp(loaded.profile->passes[0].fragment.bytes,fragment.bytes,fragment.length));
        assert(loaded.profile->passes[0].passID==testProfile&&loaded.profile->colorFormats[0]==80&&[loaded.requestID isEqual:key]);

        NSMutableData *changed=[vertex mutableCopy];((uint8_t *)changed.mutableBytes)[37]^=1;
        writeFile(@"vertex.midgard",changed);expectRejected(&profile);writeFile(@"vertex.midgard",vertex);
        changed=[fragment mutableCopy];((uint8_t *)changed.mutableBytes)[83]^=1;
        writeFile(@"fragment.midgard",changed);expectRejected(&profile);writeFile(@"fragment.midgard",fragment);
        for(NSString *field in @[@"schema",@"profile_id",@"compiler_abi"]){
            NSMutableDictionary *r=receipt();r[field]=@99;writeReceipt(r);expectRejected(&profile);
        }
        for(NSString *field in @[@"request_id",@"source_library",@"metallib_sha256",@"gpu_id",@"recipe",
            @"vertex_constants_sha256",@"fragment_constants_sha256"]){
            NSMutableDictionary *r=receipt();r[field]=@"wrong";writeReceipt(r);expectRejected(&profile);
        }
        for(NSString *which in @[@"vertex",@"fragment"])
            for(NSString *field in @[@"bytes",@"first_tag",@"work_registers",@"tls_bytes",@"wls_bytes",@"file",@"sha256"]){
                NSMutableDictionary *r=receipt(),*s=[r[which] mutableCopy];
                s[field]=[s[field] isEqual:@0]?@1:@0;r[which]=s;
                writeReceipt(r);expectRejected(&profile);
            }
        NSMutableDictionary *r=receipt();r[@"schema"]=@YES;writeReceipt(r);expectRejected(&profile);
        r=receipt();r[@"stage_compiled"]=@1;writeReceipt(r);expectRejected(&profile);
        r=receipt();r[@"pipeline_compatible"]=@YES;writeReceipt(r);expectRejected(&profile);
        r=receipt();r[@"vertex_constants_sha256"]=otherConstants;writeReceipt(r);expectRejected(&profile);
        r=receipt();r[@"fragment_constants_sha256"]=otherConstants;writeReceipt(r);expectRejected(&profile);
        r=receipt();r[@"recipe"]=[NSString stringWithFormat:@"quartzcore-generic-%u",testProfile==602?603:602];
        writeReceipt(r);expectRejected(&profile);
        writeReceipt(receipt());
        assert(!chmod(filePath(@"vertex.midgard").fileSystemRepresentation,0644));expectRejected(&profile);
        assert(!chmod(filePath(@"vertex.midgard").fileSystemRepresentation,0444));
        assert(!chmod(entryPath().fileSystemRepresentation,0777));expectRejected(&profile);
        assert(!chmod(entryPath().fileSystemRepresentation,0755));
        assert(!chmod(root.fileSystemRepresentation,0777));expectRejected(&profile);
        assert(!chmod(root.fileSystemRepresentation,0755));
        NSString *outside=[root stringByAppendingString:@"-outside"];
        assert([vertex writeToFile:outside options:0 error:NULL]);assert(!chmod(outside.fileSystemRepresentation,0444));
        assert(!unlink(filePath(@"vertex.midgard").fileSystemRepresentation));
        assert(!symlink(outside.fileSystemRepresentation,filePath(@"vertex.midgard").fileSystemRepresentation));expectRejected(&profile);
        assert(!unlink(filePath(@"vertex.midgard").fileSystemRepresentation));
        assert(!link(outside.fileSystemRepresentation,filePath(@"vertex.midgard").fileSystemRepresentation));expectRejected(&profile);
        assert(!unlink(filePath(@"vertex.midgard").fileSystemRepresentation));assert(!unlink(outside.fileSystemRepresentation));
        writeFile(@"vertex.midgard",vertex);
        pass.vertex.workRegisters=7;expectRejected(&profile);pass.vertex.workRegisters=8;
        profile.profileID=601;expectRejected(&profile);profile.profileID=testProfile;
        profile.profileID=testProfile==602?603:602;pass.passID=profile.profileID;
        expectRejected(&profile);profile.profileID=testProfile;pass.passID=testProfile;
        assert(!A5MaliLoadShaderCompiledCache(@"../escape",&profile,&error)&&error);
        writeFile(@"receipt.json",[@"[]" dataUsingEncoding:NSUTF8StringEncoding]);expectRejected(&profile);
        writeFile(@"receipt.json",[@"not JSON" dataUsingEncoding:NSUTF8StringEncoding]);expectRejected(&profile);

        /* Loaded objects own native memory even after publication is removed;
         * no byte pointer continues to map mutable/deleted cache files. */
        assert([fm removeItemAtPath:root error:NULL]);
        assert(!memcmp(loaded.profile->passes[0].vertex.bytes,vertex.bytes,vertex.length));
        assert(!memcmp(loaded.profile->passes[0].fragment.bytes,fragment.bytes,fragment.length));
        printf("known%u compiled cache: exact native pins, receipt identity/metadata, owner/mode/symlink/link rejection and retained byte lifetime: PASS\n",testProfile);
    }
    return 0;
}
