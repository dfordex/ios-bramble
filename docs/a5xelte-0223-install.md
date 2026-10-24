# 0223: direct compiler startup, bounded storage limits and RAM window

## Changes

- Spawn the installed libSystem-only translator/backend directly, avoiding the extra Foundation/IOKit worker startup observed in 0222. Keep process groups, descendant accounting, resource limits and unlimited compilation time.
- Report the implemented 16 KiB I/O limits to HFS. Preserve the existing 32-sector PIO transfer path, synchronization and clock settings; read-only write limits remain zero.
- Opt in to the documented 736 MiB XNU RAM window. The default 512 MiB loader stays byte-identical to 0222. Only the existing ADT dram-size value changes; the payload header and explicit loader capacity agree. Physical stability is pending.
- Include the newly captured genuine 1,152-byte fragment, bringing persistent stage publications to 26. No new translator or native emitter implementation was needed for it.
- Choose the shortest of compatible standard-zlib streams for each embedded file, retaining the previous compression as a candidate. The 97-file payload saves 17,305 bytes with identical decoded bytes and CRCs. This resolves the strict S-Boot staging failure without dropping stages or weakening the bounds guard.

## Local verification

- XNU build exits zero. BOOT is 31,957,008 bytes; unstripped kernel is 31,290,544 bytes.
- Signed provider remains the 943,392-byte 0221 provider; updated signed compiler is 247,920 bytes. All 26 publications and signed binaries are embedded; actual installer/cache preflight passes.
- Eight actual OS exec/resource cases and the genuine automatic worker compilation pass. Native output matches its reference.
- Actual eMMC ioctl/HFS calculation passes 16 sanitizer cases; the existing 91 MMIO/PIO cases pass.
- RAM tests pass five cases, existing packer tests six. Actual checkpoint replay verifies baseline loader identity and the bounded ADT change. Loader is 10,368 bytes, with the explicit 736 MiB capacity descriptor.
- Compression tests cover all 97 files and 33 synthetic cases. No entry grows relative to the previous compression candidate.
- Final BOOT parser verifies unchanged logical DTBH, complete selected FDT staging at `0x41fe2800..0x41ffc800`, 556-byte command line, four CPUs, native rendering and compiler enabled, quiet functional touch, 32-sector mode, and optional GPU suites disabled.

## Installation and pending results

The installer identified the A5 recovery, TWRP version and BOOT alias/capacity before writing only p10. `dd` acknowledges all 31,957,008 bytes; sync succeeds and reboot is requested. No BOOT backup, post-write readback/hash or whole-USERDATA transfer is performed.

This establishes build and write completion. It does not establish responsive UI, safe sustained use of the larger RAM window, faster storage or automatic publication of an uncached stage on the phone. The next capture must check XNU memory counts, storage errors/latency, actual translator execution and `STAGE PUBLISHED`; physical Home/power/touch behavior must be reported separately. The 512 MiB 0222 host checkpoint remains available.
