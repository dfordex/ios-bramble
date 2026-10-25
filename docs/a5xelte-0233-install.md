# 0233 installation

Source: `1e9cacff693a497c4fc9fb71a684cdac79b41e63`.

The source transition is now packaged with the shared render-state/upload plans,
independent function request lane, pipeline-dependent NIR blending and clean
compiler spawn. Full XNU make exits0. The actual installer preflight validates
374 files:17,554,125 raw bytes/3,771,571 packed bytes. Final linked-kernel symbols
and all374 file CRCs match the BOOT payload, including the signed provider,
updated compiler worker and released-Mesa backend.

| Component | Bytes |
| --- | ---: |
| BOOT image |25,784,336 |
| BOOT capacity |33,554,432 |
| Unstripped XNU |25,118,104 |
| Signed provider |982,448 |
| Signed Midgard backend |11,466,064 |

The previous loader, ADT, DTBH and complete boot arguments remain byte-identical
to0230. Selected FDT staging is below the relocation boundary. Four CPUs,
736MiB managed RAM,32-sector eMMC, quiet functional touch and native GPU remain
selected. The32 existing shader publications and270 original stock app files
with their metadata are unchanged. Optional GPU suites remain disabled.

Recovery/model/TWRP/BOOT p10/capacity guards passed on the explicitly selected
A5. A fresh unbuffered local image stream began at offset zero. `dd` acknowledged
all25,784,336bytes; sync exited0; reboot was requested. No BOOT backup, post-write
readback/hash or whole USERDATA transfer was performed. Recovery/EFS/radio/GPT
were not targets.

This is installation acknowledgement, not a physical boot/rendering result.
New blend pixels, interactive UI and progress of the previously waiting
translator require the next device observation and SYSTEM log capture.
