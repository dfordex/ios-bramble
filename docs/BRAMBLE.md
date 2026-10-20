# bramble (Pixel 4a 5G) port notes

Observed on a bramble PVT (MP1.0, ABL `b5-0.6-10489838`, UP1A.231105.001.B2)
from its live FDT and the redbull kernel tree
(`android-msm-redbull-4.19-android14-qpr3`). Device dumps stay out of git.

## Hardware facts vs sweet

| | sweet | bramble |
| --- | --- | --- |
| GICD / GICR | 0x17a00000 / 0x17a60000 | same |
| UFS host | 0x1d84000 | same |
| PSHOLD | 0xc264000 | same |
| IMEM restart_reason | 0x146aa65c | 0x146ab65c |
| Panel | 1080x2400 DSC video mode | sofef01 1080x2340 **command mode**, 24 bpp, TE gpio10 |
| Splash | 0x9c000000 | cont_splash_region 0xa0000000 (0x2300000) |
| MDSS | | 0xae00000; SSPP vig0/1 +0x5000/+0x7000, dma0-2 +0x25000/+0x27000/+0x29000; CTL +0x2000 (x4, 0x200 apart); PP +0x71000; INTF +0x6b000 (1, 2 = DSI) |
| Touch | Goodix GT9896, I2C, QUP SE7 | ST FTM5 (`st,fts`), SPI on QUP SE0 0x880000, IRQ gpio9, reset gpio8, AVDD pm8150 L13 3.3 V; gpio35 low = touch to AP (high = SLPI) |
| Keys | PM6150 PON, Vol+ PM6150L GPIO2 | PM8150 PON (SID 0, 0x800), Vol+ PM8150L GPIO5 (SID 4, 0xc400) |
| RAM | upper bank 0x1_00000000, 0xfcc00000 | memory node: 0x80000000+0x3cc00000, 0xc0000000+1G, 0x1_00000000+4G; every fixed carve-out and dynamic pool is below 4G |
| Boot image | header v2, dtb in boot.img | header v3, DTB and a 28 MB vendor ramdisk from vendor_boot |
| Logs | ring at end of userdata | ramoops 0xb7e41000 (4 MiB: 20x0x20000 dump, 1 MiB console, 512K pmsg), alt 0xb8241000 |
| Debug UART | wired as SPI | qup_uart@888000 exists (serial0); route to USB-C SBU unverified |

## Port notes

- v3: initrd = vendor ramdisk + ours, so `loader.c` must not expect the
  payload at `linux,initrd-start` (observed offset 0x1c378d5, unaligned).
- Keep the log ring off `userdata` until Android is given up: it would
  corrupt the f2fs partition. Use the ramoops console zone instead.
- Stock kernel is LZ4; the shim is sent raw (Qualcomm ABL takes both; not yet
  verified on bramble's ABL).

## Milestone 1: display probe (`shim/bramble.c`, `shim/build-bramble.sh`)

Logs the scanning SSPP (address, size, stride, format), CTL state and MDP
registers that change by themselves, then draws a big digit per phase:
1 = no MDP writes, 2 = CTL_START kick every 16 ms, 3 = done. After 30 s it
warm-resets into Android with the log in both pstore console zones.

Boot image: ABL refuses a raw Image ("Unsupported"), text_offset 0
("Invalid Parameter") and unsigned vbmeta; it boots LZ4 + text_offset 0x80000
+ the signed vbmeta borrowed from the phone's boot_a (hash mismatch is fine
unlocked). "boot.img missing cmdline or OS version" is printed for stock too.

Result (2026-10-21, two boots, photos): **phase 1 visible full screen = ABL
leaves autorefresh on; plain memory writes reach the panel, no kicks.**
- SSPP0 (vig0) scans out: addr 0xa0000000, 1080x2340 (size 0x09240438),
  stride 0x10e0, fmt 0x000237ff (4 bpp, alpha), unpack 0x03020001 =
  bytes B,G,R,A = a8r8g8b8 like sweet. SSPP1-4 idle.
- CTL0 top 0x20000, intf_active 0x2 (INTF1 = DSI0); CTL1-3 top 0x1f00.
- Self-changing in 100 ms: TOP+0x300/0x304/0x308, INTF1+0x0ac/0x0b0/0x298/0x2b0
  (INTF tear-check counters: TE-driven autorefresh is running).
- Phase 2 (CTL_START every 16 ms on top of autorefresh) blanked the top
  ~15 % and **reset the SoC within ~2 s, in both boots. Never kick.**
- pstore stays empty after every reset (also the clean PSCI one).

## Milestone 2: watchdog (probe 2, video 2026-10-21)

APSS WDT at entry: **WDT0_EN = 0** (ABL does not arm it), bark 0x7ffff,
bite 0xfffff. The probe ran 60 s without pets and reset cleanly. Android
reports `bootreason=watchdog` for any reset it did not initiate (also the
probe's PSCI reset), so that string means nothing here. XNU needs no pet.
