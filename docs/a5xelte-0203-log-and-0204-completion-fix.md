# 0203 root mount regression and 0204 completion correction

## Physical failure

The user's screen shows repeated HFS metadata-read error5 (EIO), followed by
root mount failure. Read-only SYSTEM recovery obtains flush12, all47,877
recorded bytes, without ring overwrite. Raw logs stay private.

The first batch receipt (238) is a read of8 blocks with4096 bytes moved,
error5, CMD12 stop error5, idle0 and poisoned1. Batching is disabled and
subsequent root I/O fails closed. No successful multi-block read or write is
counted. Metrics (414–416) record5063 requests,2,578,944 read bytes,512 write
bytes,25 errors,914ms active I/O,0ms aggregate lock wait and34ms log writes.
The existing single-sector path handled these other requests; this is not a
throughput result for successful batching. The failure happens before iOS
userland startup or the installer can complete.

## Incorrect extra completion gate

0203 requires `TCBCNT == requested_bytes` after PIO has copied all bytes,
command/data completion indications are present and card busy has cleared.
The working downstream `dw_mmc.c` completes bounded SBC requests from data
events/PIO length and does not impose this counter equality. If that extra
gate rejects a successful CMD23 transfer, CMD12 then addresses a card which
has already returned to transfer state and can fail, triggering poisoned I/O.

0203's terse error receipt omits the original controller/response/counter
values and exact failure phase. Therefore this mechanism is a source-backed
candidate for the observed failure, not a conclusively decoded hardware fault;
a late controller error after all bytes moved remains possible.

Patch0198 removes the unsupported counter-equality gate. It preserves full
PIO byte length, command/data indications, R1/controller error checks, card
busy wait, partition guards, error abort and no replay of partial writes.
Both hardware counters are now observations on the first four successful
batches. Any failure records its phase and original RINT/RESP/STATUS/TCBCNT/
TBBCNT before CMD12 can overwrite them.

## Local verification

Actual extracted command/PIO/strategy functions pass91 ASan/UBSan MMIO cases.
The model now explicitly accepts complete reads and writes with a zero TCBCNT
while still rejecting missing data completion, short PIO, transport/R1 errors,
busy timeout and partial-write failure. The old test incorrectly treated the
assumed counter equality as its oracle; host-model success had not proved the
real controller semantics.

Patch application with zero fuzz reproduces staged source exactly. Full
XNU DEVELOPMENT ARM64 A5XELTE build passes. BOOT0204 is30,359,568 bytes and
retains `a5emmc_blocks=32`, existing provider/compiler payload and23 GPU cases.
Physical root mount, batch acceptance, data correctness and speed remain
pending. No successful storage repair is claimed from the build alone.
