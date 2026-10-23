# 0203: bounded eMMC read/write batching

## Implementation

Patch0197 adds opt-in `a5emmc_blocks=32`. Aligned full-sector parts of BSD
root requests use up to32 sectors (16KiB) per transfer: CMD23 declares the
block count, followed by CMD18 for reads or CMD25 for writes. Small/partial
requests retain the existing512-byte path and partial write read/modify/write.
The packer requires the new kernel marker before enabling this mode.

Hardware sequencing follows the working Exynos7580 downstream
`drivers/mmc/host/dw_mmc.c`: SBC before data, no explicit stop on successful
bounded SBC transfer, explicit CMD12 stop/abort on data failure. FIFO units
retain the Samsung paired32-bit access for64-bit data, the actual64-unit
depth and bootloader timing/clock/pad state. DMA is not enabled.
Command and response definitions are checked against the
[Linux v6.12 MMC header](https://raw.githubusercontent.com/torvalds/linux/v6.12/include/linux/mmc/mmc.h).

Every batch validates the complete root range and32-bit sector-address limit.
Writes retain the existing explicit USERDATA write gate. Recovery, EFS,
factory/radio partitions and GPT are not targets. SYSTEM logger writes keep
their existing separate bounded single-sector path.

R1/controller errors, FIFO bounds, complete data/command indications,
transferred byte counter and card-busy completion are checked. A completed
CMD23 ILLEGAL_COMMAND can fall back before data starts. A partially transferred
request is never replayed by this driver as legacy writes. Data errors abort
with CMD12, disable batching and return an error without claiming completion;
failed abort/idle or uncertain setup disables further root I/O for this boot.

Cumulative request bytes, errors, active time, mutex wait, maximum request,
log-flush time and successful batch counts are printed approximately once
per minute. Metrics are copied under the controller mutex and printed after
unlock. No per-sector log flood is introduced.

## Verification and limits

The actual command, PIO and strategy functions run under ASan/UBSan against
a strict MMIO/card model:90 cases pass. Tests cover2..32-block reads/writes,
unaligned memory pointers,32/64-bit FIFO units, partition/address bounds,
short tails preserving unrelated bytes, CMD23 rejection, command/data timeout,
R1/controller error, wrong byte count, busy/abort failure and partial write
failure without legacy replay. A64KiB strategy request uses four data batches
instead of128 single-sector transfers. These are host-model results, not a
physical throughput result.

The generated patch applies with zero fuzz and reproduces staged source
exactly. Repository integrity passes197 patches/35Python/10shell scripts.
The complete XNU build passes. Existing Metal/compiler payload and23 GPU
cases remain. Device batching acceptance, filesystem correctness, measured
speed and later UI progression require the next runtime capture.
