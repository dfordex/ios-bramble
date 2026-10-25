# 0240: disable continuous CPU damage comparison

The user requests removing comparison after correct drawing, to avoid0239's whole-image CPU work. This trial selects the existing full-frame GPU path with `a5fb_damage=0`. It does not claim that correct sampled pixels alone justify removing synchronization or resource validation.

## Behavior

- The full-source CPU flush used specifically for comparison,1920-row comparison and shadow remember/allocation branch are skipped. Every eligible frame is transferred completely by the existing Mali presentation jobs.
- Existing frame mapping/source coherency, geometry/resource checks and real terminal GPU fences remain. The eight startup sample-grid diagnostics are unchanged; they are separate from continuous damage detection.
- Native batching, provider, worker and all386 embedded files/36 prewarmed publications are exactly0239. Previously generated phone shader cache remains persistent.
- Full-frame transfer now costs8294400bytes per GPU presentation.0239's90.71% transfer saving is intentionally exchanged for avoiding continuous CPU comparison. Only a fresh runtime can establish the latency/FPS result.

## Reproducible selection

The BOOT packer now accepts mutually exclusive `--present-damage` and `--full-frame-present`. Explicit full-frame mode removes every inherited `a5fb_damage` occurrence and writes a single0. Omitting both preserves the reference policy. Seven packer regression tests pass, including duplicate inherited overrides and conflicting switches failing before file access.

0240 reuses the exact linked0239 kernel without recompilation. Offline verification proves the loader, DTBH, ADT, all kernel segments and every non-argument payload byte are exact0239; Android header digest is valid. The only semantic boot-argument delta is `a5fb_damage=1`→`0`. Existing staging bounds remain below0x42000000.

## Package and install

- BOOT25837584bytes; SHA256`60455a9ea5aad6a7f59080d7a36bd25cd8ffb8f8f35a9f4121d2d12cbf6f1e27`.
- Guarded recovery/a5xelte/TWRP/BOOTp10/capacity checks pass. Offset-zero write acknowledges all25837584bytes, sync0 and reboot requested. No BOOT backup/readback or whole USERDATA transfer.
- Image, verification script/proof and installation receipt retained privately under workspace research build0240, outside git.

## Runtime check

Compare real GPU copy rate and presentation path cost with0239, separating self/no-op shown counts. Confirm no damage-comparison receipts, expected full-frame byte totals, real fence completion and physical UI response. Other known upload-lifetime barriers and Query17 mapping rejection are unchanged. No FPS improvement or animation repair is claimed before this test.
