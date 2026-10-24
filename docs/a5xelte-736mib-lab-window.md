# Opt-in 736 MiB XNU RAM window

The default remains the working 512 MiB checkpoint, `0x80000000..0xa0000000`.
`RAM_MIB=736 sh shim/a5xelte/build-xnu-boot.sh` builds an explicit opt-in loader
for `0x80000000..0xae000000`. Package it with:

```
python3 tools/a5xelte-pack-metal-boot.py REFERENCE_BOOT KERNEL OUTPUT_BOOT \
  --ram-mib 736 --loader-path PRIVATE_736_IMAGE [other existing options]
```

The packer requires the opt-in loader's capacity descriptor and Samsung header.
It changes only the eight existing `/chosen/dram-size` value bytes; every other
ADT byte, including seed and padding, survives. `mkpayload` derives its header
RAM base/size from that ADT. An inconsistent reference payload/ADT is rejected.
The BOOT embedded DTBH bounds guard remains unchanged. No factory DTB partition
or firmware reservation is modified.

## Evidence and limits

The actual SM-A510F recovery DT reports banks `0x40000000+0x20000000`,
`0x60000000+0x20000000`, `0x80000000+0x20000000`, and
`0xa0000000+0x1e800000`. Captured reserved-memory regions and the recovered
`exynos7580-reserve-2000MB-Ax.dtsi` agree on these upper carveouts:

| Base | Size | Use |
| --- | --- | --- |
| `0xaec00000` | `0x01400000` | video_ext |
| `0xb8000000` | `0x00200000` | mfc_fw |
| `0xb8200000` | `0x00110000` | mfc_nfw |
| `0xb8400000` | `0x05800000` | video |
| `0xbdc00000` | `0x00600000` | common |
| `0xbe200000` | `0x00100000` | fimc_is_fd |

The same recovered Ax source declares `/memreserve/` ranges
`0xb0000000+0x07800000` for CP/shared memory and
`0xbe800000+0x01800000` for the EL3 monitor. The chosen window ends 12 MiB
below the first of these recovered upper reservations. Recovery `/proc/iomem`
shows RAM broadly and does not enumerate all carveouts; it cannot establish
their absence. This audit does not prove every possible firmware reservation.

The loader supplies both XNU `memSize` and `memSizeActual` from the payload.
The inspected arm64 bootstrap maps the supplied size; no separate 512 MiB cap
was found. The extension remains within the same physical 1 GiB table region.
The new capacity is 771751936 bytes, 188416 pages at 4 KiB, before kernel and VM
overheads (57344 more raw pages than 512 MiB).

This larger window is physically unverified. The next hardware check must
confirm XNU's reported memory/page counts and successful sustained allocation
and compiler/UI operation without corruption. Keep the 512 MiB BOOT checkpoint
for rollback; this option does not establish that all 2 GB is safe for XNU.

## Local verification

With the same Homebrew LLVM toolchain as the shipped loader, the new source's
default 512 MiB Image rebuilt byte-for-byte equal to the actual 0222 BOOT loader
(10336 bytes, SHA256
`522c365351f65f5f7459d03126b3b327c3f755363e11e614ecd69cc6b4efab37`).
The only source variation for 736 MiB is the capacity bound plus its explicit
24-byte descriptor; compiler instruction selection and relocation can also
change when the bound changes. No loader copy, MMU, FDT or handoff algorithm is
changed. The 736 MiB Image is 10368 bytes, SHA256
`055a2886aa2146cdba20236da78862d23492eb0415063162915ca00d722c5632`.

`tools/test-a5xelte-ram-window.py` checks default byte preservation, raw ADT byte
preservation, actual payload-header derivation, and malformed/inconsistent
inputs. Its optional private BOOT/loader inputs additionally replay the real
checkpoint without committing captured bytes.
