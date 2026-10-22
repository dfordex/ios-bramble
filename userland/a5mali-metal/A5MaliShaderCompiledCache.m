/* SPDX-License-Identifier: MIT
 * Known602/603 native stage cache. Root publication authenticates provenance;
 * code/metadata pins and the caller's independent exact pipeline selection
 * preserve the already reviewed executable ABI. No arbitrary code admission.
 */
#import "A5MaliShaderCompiledCache.h"
#import <CommonCrypto/CommonDigest.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
#include <stdio.h>

#ifndef A5_SHADER_COMPILED_CACHE_HOST_TEST
static const char *const cacheRoot="/private/var/tmp/a5mali-shader-compiled";
static uid_t ownerUID(void){return 0;}
#else
#ifndef A5_SHADER_COMPILED_CACHE_TEST_ROOT
#error "Host compiled-cache tests require an explicit private root"
#endif
static const char *const cacheRoot=A5_SHADER_COMPILED_CACHE_TEST_ROOT;
static uid_t ownerUID(void){return geteuid();}
#endif
static NSString *const librarySHA=@"11c74cc42ce5137b73d44d427f75764f886656d4ddb374422d56b609ed2762d9";
/* SHA256 of the complete sorted named-constant JSON arrays. Indexed arrays
 * must be empty in each worker recipe. These are semantic contract
 * hashes, independent of native dead-resource optimization. */
typedef struct {
    uint32_t profileID,vertexBytes,fragmentBytes,vertexRegisters,fragmentRegisters;
    const char *recipe,*vertexSHA,*fragmentSHA,*vertexConstantsSHA,*fragmentConstantsSHA;
} CacheContract;
static const CacheContract contracts[]={
    {602,1808,848,8,6,"quartzcore-generic-602",
        "3cdf2b0db0b9992ce887242e7cac282cd70c3f8051e3ace3e791a0b676193a79",
        "e66041333f6452510cda4d0ee1f1c1edf443a12007a989871a1546791deb0834",
        "d8b11a43b5075c7c8f179f6da7849edc5c5534f161590552da6b177007c8595f",
        "5e1fae69edcd5f51efdf3a4adbca80e9c7901844f942404208c0b2dc89bb7c7f"},
    /* Both stage specializations were accepted on the phone. This corrected
     * normalized-UV fragment is host-compiled; its device pixels still need
     * verification. The caller independently matches the exact stage
     * constants and full pipeline state before replacing profile 603. */
    {603,2192,880,8,5,"quartzcore-generic-603",
        "e0c51d2171b28c891677cdb1f1c98032bee0f03bb64af694a8321d711159fc96",
        "e4cf4d31a87bde096cc7cc57a12818f79296e3998d22d9c6c5139a9887f30047",
        "57f61f4161d206f26026807dd822e5fae8713e3b9f183f381d116cddd6d40112",
        "1314cb292bea03fb85537fdebb3919e65b76db1e99f72b12f7fb1abcd7c8d50d"},
};
static const CacheContract *contractForID(uint32_t profileID)
{
    for(unsigned i=0;i<sizeof(contracts)/sizeof(contracts[0]);++i)
        if(contracts[i].profileID==profileID)return contracts+i;
    return NULL;
}

@interface A5MaliShaderCompiledCacheEntry ()
- (instancetype)initWithRequestID:(NSString *)requestID expected:(const A5MaliCompiledProfile *)expected
    vertex:(NSData *)vertex fragment:(NSData *)fragment;
@end
@implementation A5MaliShaderCompiledCacheEntry {
    NSData *_vertexData,*_fragmentData;
    NSString *_requestID;
    A5MaliCompiledProfile _profile;
    A5MaliCompiledPass _pass;
    A5MaliCompiledAttachmentContract _attachmentContracts[2];
}
- (instancetype)initWithRequestID:(NSString *)requestID expected:(const A5MaliCompiledProfile *)expected
    vertex:(NSData *)vertex fragment:(NSData *)fragment
{
    if((self=[super init])) {
        _requestID=[requestID copy];_vertexData=[vertex copy];_fragmentData=[fragment copy];
        _profile=*expected;_pass=expected->passes[0];
        _pass.vertex.bytes=_vertexData.bytes;_pass.fragment.bytes=_fragmentData.bytes;
        _profile.passes=&_pass;
        if(expected->attachmentContracts&&expected->attachmentContractCount<=2){
            memcpy(_attachmentContracts,expected->attachmentContracts,
                expected->attachmentContractCount*sizeof(_attachmentContracts[0]));
            _profile.attachmentContracts=_attachmentContracts;
        }
    }
    return self;
}
- (const A5MaliCompiledProfile *)profile{return &_profile;}
- (NSString *)requestID{return _requestID;}
@end

static id failure(NSError **error,int code,NSString *reason)
{
    if(error)*error=[NSError errorWithDomain:@"com.orhunnx.a5xelte.shader-cache" code:code
        userInfo:@{NSLocalizedDescriptionKey:reason}];
    return nil;
}
static BOOL hexDigest(id value)
{
    if(![value isKindOfClass:NSString.class]||[value length]!=64)return NO;
    const char *p=[value UTF8String];if(!p||strlen(p)!=64)return NO;
    for(unsigned i=0;i<64;++i)if(!((p[i]>='0'&&p[i]<='9')||(p[i]>='a'&&p[i]<='f')))return NO;
    return YES;
}
static NSString *digest(const void *bytes,NSUInteger count)
{
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];CC_SHA256(bytes,(CC_LONG)count,hash);
    char raw[65];for(unsigned i=0;i<sizeof(hash);++i)snprintf(raw+2*i,3,"%02x",hash[i]);
    return [NSString stringWithUTF8String:raw];
}
static BOOL directory(int fd)
{
    struct stat st;return fd>=0&&!fstat(fd,&st)&&S_ISDIR(st.st_mode)&&
        st.st_uid==ownerUID()&&(st.st_mode&07777)==0755;
}
static NSData *readFile(int parent,const char *name,size_t maximum,NSError **error)
{
    int fd=openat(parent,name,O_RDONLY|O_NOFOLLOW);int saved=errno;
    if(fd<0)return failure(error,saved==ENOENT?ENOENT:EIO,@"compiled cache file unavailable");
    struct stat before,after;NSMutableData *data=nil;
    if(fstat(fd,&before)||!S_ISREG(before.st_mode)||before.st_uid!=ownerUID()||
        (before.st_mode&07777)!=0444||before.st_nlink!=1||before.st_size<=0||
        (uint64_t)before.st_size>maximum){
        close(fd);return failure(error,EINVAL,@"compiled cache file ownership/mode/size rejected");
    }
    data=[NSMutableData dataWithLength:(NSUInteger)before.st_size];size_t offset=0;
    while(offset<data.length){
        ssize_t n=read(fd,(uint8_t *)data.mutableBytes+offset,data.length-offset);
        if(n<0&&errno==EINTR)continue;
        if(n<=0){close(fd);return failure(error,EIO,@"compiled cache read failed");}
        offset+=(size_t)n;
    }
    if(fstat(fd,&after)||before.st_ino!=after.st_ino||before.st_size!=after.st_size||
        before.st_mtimespec.tv_sec!=after.st_mtimespec.tv_sec||before.st_mtimespec.tv_nsec!=after.st_mtimespec.tv_nsec||
        before.st_ctimespec.tv_sec!=after.st_ctimespec.tv_sec||before.st_ctimespec.tv_nsec!=after.st_ctimespec.tv_nsec||
        after.st_uid!=ownerUID()||(after.st_mode&07777)!=0444||after.st_nlink!=1){
        close(fd);return failure(error,EIO,@"compiled cache changed while reading");
    }
    if(close(fd))return failure(error,EIO,@"compiled cache close failed");
    return [data copy];
}
static BOOL expectedShader(const A5MaliCompiledShader *shader,const CacheContract *contract,BOOL vertex)
{
    NSUInteger bytes=vertex?contract->vertexBytes:contract->fragmentBytes;
    NSUInteger registers=vertex?contract->vertexRegisters:contract->fragmentRegisters;
    NSString *pin=[NSString stringWithUTF8String:vertex?contract->vertexSHA:contract->fragmentSHA];
    return shader->bytes&&shader->byteCount==bytes&&shader->firstTag==5&&
        shader->workRegisters==registers&&!shader->tlsBytes&&!shader->wlsBytes&&
        shader->sha256&&[pin isEqualToString:[NSString stringWithUTF8String:shader->sha256]]&&
        [digest(shader->bytes,shader->byteCount) isEqual:pin];
}
static BOOL exact603Attachments(const A5MaliCompiledProfile *profile)
{
    static const A5MaliCompiledAttachmentState copy={15,0,0,0,1,0,1,0};
    static const A5MaliCompiledAttachmentState sourceOver={15,1,0,0,1,5,1,5};
    if(profile->flags!=A5MaliProfileSourceOverBlend||
       profile->attachmentContractCount!=2||!profile->attachmentContracts||
       profile->colorFormats[0]!=80||profile->viewportWidth||profile->viewportHeight)
        return NO;
    for(unsigned i=1;i<8;++i)if(profile->colorFormats[i])return NO;
    for(unsigned contract=0;contract<2;++contract)
        for(unsigned slot=0;slot<8;++slot){
            const A5MaliCompiledAttachmentState *want=contract==1&&slot==0?&sourceOver:&copy;
            if(memcmp(&profile->attachmentContracts[contract].attachments[slot],want,sizeof(*want)))
                return NO;
        }
    return YES;
}
static BOOL exactNumber(id value,uint32_t expected)
{
    return [value isKindOfClass:NSNumber.class]&&CFGetTypeID((__bridge CFTypeRef)value)!=CFBooleanGetTypeID()&&
        !CFNumberIsFloatType((__bridge CFNumberRef)value)&&[value unsignedLongLongValue]==expected&&
        [value longLongValue]>=0;
}
static BOOL exactBool(id value,BOOL expected)
{
    return value&&CFGetTypeID((__bridge CFTypeRef)value)==CFBooleanGetTypeID()&&[value boolValue]==expected;
}
static BOOL stageRecord(NSDictionary *record,NSData *bytes,const A5MaliCompiledShader *expected,
    NSString *file)
{
    return [record isKindOfClass:NSDictionary.class]&&[record[@"file"] isEqual:file]&&
        exactNumber(record[@"bytes"],expected->byteCount)&&bytes.length==expected->byteCount&&
        exactNumber(record[@"first_tag"],expected->firstTag)&&exactNumber(record[@"work_registers"],expected->workRegisters)&&
        exactNumber(record[@"tls_bytes"],expected->tlsBytes)&&exactNumber(record[@"wls_bytes"],expected->wlsBytes)&&
        hexDigest(record[@"sha256"])&&[record[@"sha256"] isEqualToString:[NSString stringWithUTF8String:expected->sha256]]&&
        [digest(bytes.bytes,bytes.length) isEqual:record[@"sha256"]];
}
A5MaliShaderCompiledCacheEntry *A5MaliLoadShaderCompiledCache(NSString *requestID,
    const A5MaliCompiledProfile *expected,NSError **error)
{
    if(error)*error=nil;
    const CacheContract *contract=expected?contractForID(expected->profileID):NULL;
    if(!hexDigest(requestID)||!expected||!contract||expected->passCount!=1||!expected->passes||
        (expected->flags&A5MaliProfileNotExecutable)||expected->passes[0].passID!=contract->profileID||
        expected->passes[0].logicalTarget||!expected->vertexName||!expected->fragmentName||
        strcmp(expected->vertexName,"fixed_vert_lph_spc")||strcmp(expected->fragmentName,"fixed_frag_lph_cph")||
        !expectedShader(&expected->passes[0].vertex,contract,YES)||!expectedShader(&expected->passes[0].fragment,contract,NO)||
        (expected->profileID==603&&!exact603Attachments(expected)))
        return failure(error,EINVAL,@"compiled cache requires an exact authenticated602/603 stage contract");
    int root=open(cacheRoot,O_RDONLY|O_DIRECTORY|O_NOFOLLOW),dir=-1;
    if(root<0)return failure(error,errno==ENOENT?ENOENT:EIO,@"compiled cache not published");
    if(!directory(root)){close(root);return failure(error,EINVAL,@"compiled cache root ownership/mode rejected");}
    dir=openat(root,requestID.fileSystemRepresentation,O_RDONLY|O_DIRECTORY|O_NOFOLLOW);int saved=errno;
    close(root);
    if(dir<0)return failure(error,saved==ENOENT?ENOENT:EIO,@"compiled request not published");
    if(!directory(dir)){close(dir);return failure(error,EINVAL,@"compiled request ownership/mode rejected");}
    NSData *receiptData=readFile(dir,"receipt.json",16*1024,error);
    if(!receiptData){close(dir);return nil;}
    NSError *jsonError=nil;id decoded=[NSJSONSerialization JSONObjectWithData:receiptData options:0 error:&jsonError];
    if(![decoded isKindOfClass:NSDictionary.class]){
        close(dir);return failure(error,EINVAL,@"compiled receipt is not a JSON dictionary");
    }
    NSDictionary *receipt=decoded;
    if(!exactNumber(receipt[@"schema"],1)||![receipt[@"request_id"] isEqual:requestID]||
        !exactNumber(receipt[@"profile_id"],contract->profileID)||![receipt[@"source_library"] isEqual:@"quartzcore"]||
        ![receipt[@"metallib_sha256"] isEqual:librarySHA]||![receipt[@"gpu_id"] isEqual:@"07201000"]||
        !exactNumber(receipt[@"compiler_abi"],1)||![receipt[@"recipe"] isEqual:[NSString stringWithUTF8String:contract->recipe]]||
        !exactBool(receipt[@"stage_compiled"],YES)||!exactBool(receipt[@"pipeline_compatible"],NO)||
        !hexDigest(receipt[@"descriptor_sha256"])||
        ![receipt[@"vertex_constants_sha256"] isEqual:[NSString stringWithUTF8String:contract->vertexConstantsSHA]]||
        ![receipt[@"fragment_constants_sha256"] isEqual:[NSString stringWithUTF8String:contract->fragmentConstantsSHA]]){
        close(dir);return failure(error,EINVAL,@"compiled receipt identity/source/recipe rejected");
    }
    NSData *vertex=readFile(dir,"vertex.midgard",64*1024,error);
    NSData *fragment=vertex?readFile(dir,"fragment.midgard",64*1024,error):nil;
    close(dir);if(!vertex||!fragment)return nil;
    if(!stageRecord(receipt[@"vertex"],vertex,&expected->passes[0].vertex,@"vertex.midgard")||
        !stageRecord(receipt[@"fragment"],fragment,&expected->passes[0].fragment,@"fragment.midgard"))
        return failure(error,EINVAL,@"compiled stage bytes/hash/native metadata rejected");
    return [[A5MaliShaderCompiledCacheEntry alloc]initWithRequestID:requestID expected:expected vertex:vertex fragment:fragment];
}
