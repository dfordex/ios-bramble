/* SPDX-License-Identifier: MIT
 * Source-only boot harness for locally generated, authenticated Mac outputs.
 * The private include is generated outside Git. Tests precede runtime clients;
 * a terminal fence and cache invalidation precede every CPU observation.
 */
struct A5SuiteOutput {
    const char *name;
    uint32_t offset, bytes, elementBytes, tolerance;
    const uint8_t *expected, *mask;
};
struct A5SuiteRegion { uint32_t offset, bytes; };
struct A5SuiteCase {
    const char *name;
    const uint8_t *sparse;
    uint32_t sparseBytes;
    uint64_t payloadHash;
    const A5SuiteOutput *outputs;
    uint32_t outputCount;
    const A5SuiteRegion *immutable;
    uint32_t immutableCount;
};
static const uint32_t kA5SuiteBytes = 0x40000;

#if __has_include("A5XELTEShaderSuiteData.inc")
#include "A5XELTEShaderSuiteData.inc"

static bool a5suite_range(uint32_t off, uint32_t length)
{ return length && off <= kA5SuiteBytes && length <= kA5SuiteBytes - off; }

static uint64_t a5suite_hash(const uint8_t *bytes, uint32_t count)
{
    uint64_t hash = 0xcbf29ce484222325ULL;
    while (count--) hash = (hash ^ *bytes++) * 0x100000001b3ULL;
    return hash;
}

static uint32_t a5suite_word(const uint8_t *p, uint32_t width)
{
    uint32_t v = 0;
    memcpy(&v, p, width);
    return v;
}

static bool a5suite_unpack(const A5SuiteCase &test, uint8_t *data)
{
    if (!test.sparse || !test.sparseBytes || test.sparseBytes > 0x48000 ||
        !test.outputCount || test.outputCount > 8 || test.immutableCount > 16)
        return false;
    bzero(data, kA5SuiteBytes);
    uint32_t cursor = 0, end = 0;
    while (cursor < test.sparseBytes) {
        if (test.sparseBytes - cursor < 8) return false;
        uint32_t off = a5suite_word(test.sparse + cursor, 4);
        uint32_t n = a5suite_word(test.sparse + cursor + 4, 4);
        cursor += 8;
        bool fill = (n & 0x80000000u) != 0;
        n &= 0x7fffffffu;
        uint32_t encoded = fill ? 1u : n;
        if (off < end || !a5suite_range(off, n) || encoded > test.sparseBytes - cursor)
            return false;
        if (fill) memset(data + off, test.sparse[cursor], n);
        else memcpy(data + off, test.sparse + cursor, n);
        end = off + n;
        cursor += encoded;
    }
    for (uint32_t i = 0; i < test.outputCount; ++i) {
        const A5SuiteOutput &out = test.outputs[i];
        if (!out.expected || !a5suite_range(out.offset, out.bytes) ||
            (out.elementBytes != 1 && out.elementBytes != 2 && out.elementBytes != 4) ||
            out.bytes % out.elementBytes) return false;
    }
    for (uint32_t i = 0; i < test.immutableCount; ++i)
        if (!a5suite_range(test.immutable[i].offset, test.immutable[i].bytes))
            return false;
    uint64_t next = 0;
    memcpy(&next, data + 0x18, 8);
    return data[0x10] == 0x0b && data[0x110] == 0x0f &&
        data[0x210] == 0x13 && next == kA5G3DTestVA + 0x100 &&
        a5suite_hash(data, kA5SuiteBytes) == test.payloadHash;
}

static bool a5suite_flush_tables(vm_offset_t gpu)
{
    if (!a5g3d_downsample_mmu_ready(gpu) || a5g3d_read32(gpu, 0x2000) ||
        a5g3d_read32(gpu, 0x241c)) return false;
    static_assert((kA5G3DTestVA & (kA5SuiteBytes - 1)) == 0, "aligned suite map");
    a5g3d_write32(gpu, 0x2410, static_cast<uint32_t>(kA5G3DTestVA) | 17u);
    a5g3d_write32(gpu, 0x2414, 0);
    __sync_synchronize();
    a5g3d_write32(gpu, 0x2418, 2);
    if (!a5g3d_downsample_mmu_ready(gpu)) return false;
    a5g3d_write32(gpu, 0x2418, 4);
    return a5g3d_downsample_mmu_ready(gpu) &&
        !a5g3d_read32(gpu, 0x2000) && !a5g3d_read32(gpu, 0x241c);
}

static bool a5suite_compare(const A5SuiteCase &test, const uint8_t *data)
{
    bool all = true;
    for (uint32_t i = 0; i < test.outputCount; ++i) {
        const A5SuiteOutput &out = test.outputs[i];
        uint32_t matched = 0, firstBad = ~0u, firstActual = 0, firstExpected = 0;
        const uint32_t fullMask = out.elementBytes == 4 ? ~0u :
            ((1u << (8 * out.elementBytes)) - 1);
        for (uint32_t off = 0; off < out.bytes; off += out.elementBytes) {
            uint32_t mask = out.mask ? a5suite_word(out.mask + off, out.elementBytes) : fullMask;
            uint32_t a = a5suite_word(data + out.offset + off, out.elementBytes) & mask;
            uint32_t e = a5suite_word(out.expected + off, out.elementBytes) & mask;
            uint32_t difference = a > e ? a - e : e - a;
            bool good = mask == fullMask ? difference <= out.tolerance : a == e;
            matched += good;
            if (!good && firstBad == ~0u) { firstBad = off; firstActual = a; firstExpected = e; }
        }
        bool pass = matched == out.bytes / out.elementBytes;
        all &= pass;
        IOLog("A5XELTE G3D SUITE: case=%s output=%s elements=%u/%u width=%u tol=%u first_bad=%u actual=%08x expected=%08x pass=%u\n",
            test.name, out.name, matched, out.bytes / out.elementBytes,
            out.elementBytes, out.tolerance, firstBad, firstActual, firstExpected, pass);
    }
    return all;
}

static void a5g3d_shader_suite(IOService *service, vm_offset_t gpu,
    IOBufferMemoryDescriptor *storage)
{
    int enabled = 0;
    if (!PE_parse_boot_argn("a5shadersuite", &enabled, sizeof(enabled)) || enabled != 1) return;
    static_assert(kA5G3DDataOffset + kA5SuiteBytes <= kA5G3DTestBytes, "suite fits pinned BO");
    if (!service || service != gA5G3DQueueOwner || !gpu || gpu != gA5G3DQueueGPU ||
        !storage || storage != gA5G3DQueueBacking || !storage->getBytesNoCopy() ||
        storage->getLength() != kA5G3DTestBytes || gA5G3DRuntimeReady ||
        a5g3d_read32(gpu, 0x100) != 3 || a5g3d_read32(gpu, 0x104)) {
        IOLog("A5XELTE G3D SUITE: preflight failed; no job submitted\n");
        return;
    }
    uint8_t *bytes = static_cast<uint8_t *>(storage->getBytesNoCopy());
    uint8_t *data = bytes + kA5G3DDataOffset;
    IOByteCount span = 0;
    uint64_t phys = storage->getPhysicalSegment(0, &span, kIOMemoryMapperNone);
    uint64_t ttbr = (uint64_t(a5g3d_read32(gpu, 0x2404)) << 32) | a5g3d_read32(gpu, 0x2400);
    if (!phys || (phys & 4095) || span < kA5G3DTestBytes || (ttbr & ~4095ULL) != phys) return;
    const uint32_t shader = a5g3d_read32(gpu, 0x140);
    if (!shader) return;
    uint32_t passed = 0, evaluated = 0;
    for (const A5SuiteCase &test : kA5SuiteCases) {
        if (!__sync_bool_compare_and_swap(&gA5G3DQueueState, 0u, 3u)) break;
        if (!a5suite_unpack(test, data)) {
            gA5G3DQueueState = 0;
            IOLog("A5XELTE G3D SUITE: malformed case=%s; skipped\n", test.name);
            continue;
        }
        uint64_t hashes[16] = {};
        for (uint32_t i = 0; i < test.immutableCount; ++i)
            hashes[i] = a5suite_hash(data + test.immutable[i].offset, test.immutable[i].bytes);
        uint64_t *l3 = reinterpret_cast<uint64_t *>(bytes + 0x3000);
        for (uint32_t p = 0; p < kA5SuiteBytes / 4096; ++p)
            l3[p] = (phys + kA5G3DDataOffset + p * 4096) | 0x2c1;
        if (storage->performOperation(kIOMemoryIncoherentIOStore, 0, kA5G3DTestBytes) != kIOReturnSuccess ||
            !a5suite_flush_tables(gpu)) {
            gA5G3DQueueState = 2;
            IOLog("A5XELTE G3D SUITE: mapping uncertain case=%s; all pages pinned\n", test.name);
            break;
        }
        gA5G3DQueueState = 0;
        A5G3DQueueRequest vertex = {}; vertex.slot = 1; vertex.shaderMask = shader;
        A5G3DQueueCompletion vd = {}, fd = {};
        A5G3DQueueStatus vs = a5g3d_queue_submit(service, gpu, storage, bytes, vertex, &vd);
        bool chain = vs == kA5G3DQueueCompleted &&
            storage->performOperation(kIOMemoryIncoherentIOFlush, kA5G3DDataOffset, kA5SuiteBytes) == kIOReturnSuccess;
        if (chain) { __sync_synchronize(); chain = a5suite_word(data, 4) == 1 && a5suite_word(data + 0x100, 4) == 1; }
        A5G3DQueueStatus fs = kA5G3DQueueInvalid;
        if (chain) {
            A5G3DQueueRequest fragment = {}; fragment.slot = 0; fragment.jobOffset = 0x200; fragment.shaderMask = shader;
            fs = a5g3d_queue_submit(service, gpu, storage, bytes, fragment, &fd);
        }
        bool visible = fs == kA5G3DQueueCompleted &&
            storage->performOperation(kIOMemoryIncoherentIOFlush, kA5G3DDataOffset, kA5SuiteBytes) == kIOReturnSuccess;
        bool clean = false, correct = false;
        if (visible) {
            clean = true;
            __sync_synchronize();
            for (uint32_t i = 0; i < test.immutableCount; ++i)
                clean &= hashes[i] == a5suite_hash(data + test.immutable[i].offset, test.immutable[i].bytes);
            correct = a5suite_compare(test, data);
            ++evaluated;
        }
        bool pass = visible && correct && clean && fd.headerStatus == 1 && !fd.mmuIRQ && !vd.mmuIRQ;
        passed += pass;
        IOLog("A5XELTE G3D SUITE: case=%s vertex_fence=%llu status=%u fragment_fence=%llu status=%u header=%08x mmu=%08x evaluated=%u immutable=%u pass=%u\n",
            test.name, vd.fence, vs, fd.fence, fs, fd.headerStatus, vd.mmuIRQ | fd.mmuIRQ, visible, clean, pass);
        if (gA5G3DQueueState != 0) break;
    }
    service->setProperty("A5G3DShaderSuitePassed", passed, 32);
    IOLog("A5XELTE G3D SUITE: completed passed=%u evaluated=%u cases=%u; GPU pixels only, not compositor coverage\n",
        passed, evaluated, unsigned(sizeof(kA5SuiteCases) / sizeof(kA5SuiteCases[0])));
    if (gA5G3DQueueState == 0 && !a5g3d_reset_private_texture(storage)) gA5G3DQueueState = 2;
}
#else
static void a5g3d_shader_suite(IOService *, vm_offset_t, IOBufferMemoryDescriptor *) {}
#endif
