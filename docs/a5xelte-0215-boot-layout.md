# 0215 early reboot: selected DTB staging overlap

## Phone result

The user reports repeated Samsung-logo reboot immediately after0215. TWRP still exposes the previous0214 SYSTEM record (flush151,772,359bytes):0215 never initialized that logger. The independent reserved loader record exists, but status10 is-1 before initrd discovery, initrd start/end remain zero, and the XNU entry marker is absent.

S-Boot logs the correct0215 ramdisk size, successfully selects the same revision4 DTB, then prints `ERROR: Updating Device Tree Failed`. It starts the loader and later resets with watchdog reset status. This places the observed failure before shader installation, GPU submission or iOS runtime.

## Static packaging defect

The loader and all DTBH bytes are identical in working0214 and failed0215. Added shader publications and fixtures grow the Android ramdisk from0x1db0850 to0x1dd19f0. With S-Boot's observed whole-image staging base0x40204800, the selected revision4 DTB header moves from0x41fed800 to0x4200e800. S-Boot's observed ramdisk relocation destination is0x42000000.

Thus the new selected DTB header is inside the destination of ramdisk relocation. Simulating relocation there replaces the DTB magic with payload bytes. Actual firmware copy ordering is not recovered, so this is a confirmed layout conflict consistent with the observed update error, not instruction-level proof of firmware corruption. The old DTB tail already overlapped; its header remained below the destination.

The former packaging check covered the32MiB partition but did not cover this firmware staging conflict. That check was insufficient.

## Correction

The0215b packer moves the selected DTB blob into the first equal-sized physical slot in the BOOT-carried DTBH container. Only the two corresponding entry offsets change. Every entry's logical DTB, padding, chip/revision selection and metadata remain identical; no device-tree properties are edited. This writes neither the factory DTB partition nor S-Boot.

The packer checks table/range/FDT bounds, rejects overlapping or conflicting aliases, and requires the entire selected DTB source range to remain below0x42000000 before producing an image. This is a new conservative rule based on this phone's observed firmware layout. It also rejects the former0214 tail overlap unless safely rearranged.

The native kernel, loader, ADT, boot arguments,21shader publications and47GPU fixtures remain exactly those of0215. Host verification and the physical boot result are separate checkpoints.

## Host result

Ten focused tests pass, including invalid table/FDT bounds, overlaps and no safe slot. The real0215 candidate fails the staging guard. Repacking swaps entry1/3 offsets0x800/0x34800: selected FDT source becomes0x41fda800..0x41ff4800, leaving47,104bytes below the initrd destination. All six logical blob and padding hashes remain identical. BOOT0215b stays31,924,240bytes; only DTBH slot placement/offsets and the Android header digest change. An independent full-image comparison confirms the entire loader and ramdisk/kernel payload are byte-identical. Physical boot is pending.
