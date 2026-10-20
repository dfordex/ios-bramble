# Bounded Mali tile transfer (patch 0142)

Patch 0142 exposes a kernel-only `a5g3d_transfer_sample_bgra16` operation.
It accepts a **retained** single-plane BGRA `SweetSurface`, a clipped 16 × 16
source tile and a caller-owned 256-pixel output buffer. It does not accept
shader bytes, Mali addresses, page tables or arbitrary job descriptors.

The operation snapshots the source into the queue's pinned private backing,
submits one tiler job and one fragment job, checks both finite completion
fences, invalidates the CPU cache for GPU writes, then compares all 256
result pixels against the source snapshot before publishing output. A
composite fixture lock spans both jobs; the first-swap diagnostic uses the
same lock so it cannot overwrite the shared descriptors between fences.
On ambiguous hardware completion the underlying queue halts and keeps
GPU-visible pages pinned for the remainder of the boot.

This is a **correctness primitive**, not a full-frame accelerator. Each
16 × 16 transfer still copies data CPU → private backing → GPU → private
backing → CPU. It is not wired into the normal framebuffer swap path and
does not expose the iOS IOGPU, IOAccelerator or Metal user-client ABI.
The hardware result and impact on frame rate require a device run after
the patch is built and flashed. A future backend must either honor the
shared fixture lock or use an independent GPU address space and backing.
