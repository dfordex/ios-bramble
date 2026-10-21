/* SPDX-License-Identifier: MIT */
/* Host-only ABI and stale-handle tests. Build with -I pointing to an XNU
 * tree with patch 0155 applied; this test never touches the GPU or device. */
#include "A5XELTEGPUUserClientBatch.h"
#include <cassert>

int main()
{
    static_assert(sizeof(A5GPUClientCreateBufferRequest) == 24, "ABI");
    static_assert(sizeof(A5GPUClientCreateBufferResult) == 32, "ABI");
    static_assert(sizeof(A5GPUClientSubmitAfterRequest) == 80, "ABI");
    static_assert(sizeof(A5GPUClientFenceResult) == 24, "ABI");
    uint32_t slot = 99;
    for (uint32_t i = 0; i < kA5GPUClientBufferSlots; ++i) {
        const uint64_t token = (static_cast<uint64_t>(i + 1) << 32) |
            (kA5GPUClientBufferHandleBase + i);
        assert(a5gpu_buffer_token_slot(token, &slot) && slot == i);
    }
    assert(!a5gpu_buffer_token_slot(0, &slot));
    assert(!a5gpu_buffer_token_slot(1ULL << 32, &slot));
    assert(!a5gpu_buffer_token_slot((1ULL << 32) | 1, &slot));
    assert(!a5gpu_buffer_token_slot((1ULL << 32) |
        (kA5GPUClientBufferHandleBase + kA5GPUClientBufferSlots), &slot));
    assert(!a5gpu_buffer_token_slot((1ULL << 32) |
        kA5GPUClientBufferHandleBase, nullptr));
    assert(a5gpu_buffer_access_valid(3840, 256, 4096,
        kA5GPUClientRead | kA5GPUClientWrite, kA5GPUClientWrite));
    assert(!a5gpu_buffer_access_valid(3841, 256, 4096,
        kA5GPUClientWrite, kA5GPUClientWrite));
    assert(!a5gpu_buffer_access_valid(UINT32_MAX, 2, 4096,
        kA5GPUClientWrite, kA5GPUClientWrite));
    assert(!a5gpu_buffer_access_valid(0, 0, 4096,
        kA5GPUClientWrite, kA5GPUClientWrite));
    assert(!a5gpu_buffer_access_valid(0, 257, 4096,
        kA5GPUClientWrite, kA5GPUClientWrite));
    assert(!a5gpu_buffer_access_valid(0, 1, 4096,
        kA5GPUClientRead, kA5GPUClientWrite));
}
