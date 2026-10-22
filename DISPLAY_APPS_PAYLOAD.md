# Scoped display application payload

`tools/a5xelte-metal-bundle-embed.py --display-apps /mounted/OS/Applications`
extends the existing private BOOT payload with only these fixed bundles:

- ClockAngel.app
- InputUI.app
- MediaRemoteUI.app
- PaperBoard.app
- PosterBoard.app
- PreBoard.app

This is not an all-applications restore. Other Applications children and the large
omitted asset directories are not enumerated or copied. The source volume is
read only. The script does not contact the phone or modify an HFS image.

## Contents and metadata

Every regular file and directory under the six roots is included. Regular file
bytes, including executable code signatures and `_CodeSignature/CodeResources`,
are read unchanged; no re-signing, binary patching, plist conversion or resource
filtering is applied to these applications. The existing thirteen provider,
probe, cache and compiler payloads keep their prior contents and default UID/GID
zero.

App file and directory UID, GID and permission bits come from `lstat`. Nested
symlinks and special files are rejected, rather than followed or silently lost.
The actual selected source contains neither. Source extended attributes are
inventoried without following links. Unknown/functional attributes, including
resource forks, are rejected. `com.apple.decmpfs` and provenance/quarantine
attributes may be omitted only because the payload holds expanded regular file
bytes, and no compressed-file flags or storage representation are restored.
The selected source has **zero extended attributes**, so no attribute omission is
needed for this payload.

The generated include adds UID/GID fields to each `a5metal_install_file` after
`packed_size`. It defines `A5METAL_DIRECTORIES_PRESENT` and emits an optional
`a5metal_install_directories` table with `{path, mode, uid, gid}`. Directory order
is UTF-8 byte order, with `/Applications` first and each parent before its
children. The corresponding kernel installer patch must be present before using
this include. Zero-byte regular files use a nonnull byte-array sentinel while
logical size and packed size remain zero.

The stdout JSON receipt lists every file's expanded size, mode, UID/GID and
CRC32, plus directory metadata and xattr inventory. CRC32 is a corruption check,
not cryptographic authentication. Neither receipt nor generated include belongs
in Git: both may contain or describe private Apple artifacts.

Limits remain 32 MiB per app file, 4,096 app records, 64 MiB expanded combined
payload and 10 MiB compressed combined payload. Paths must fit the kernel's 1,024-byte MAXPATHLEN including NUL. C path strings escape UTF-8 bytes
using unambiguous three-digit octal escapes.

## Current local preparation evidence

The selected `SydneyUpdate20H392.D21D211OS/Applications` source contributes 47
files and 224 directories, plus the `/Applications` anchor: 1,494,904 expanded
bytes. Combined with the thirteen existing payload files, the private include
has 60 files, 225 directories, 29,710,506 expanded bytes and 8,412,239 stored
bytes. An independent extraction and decompression compared all sixty files to
the exact original source paths: every byte matched, including the thirteen
existing files.

These are preparation and host verification results. They do not prove that the
kernel installed the apps or that the phone displayed its interface afterward.

## Source-only tests

```sh
python3 experiments/ios-a5xelte/tools/test_display_apps_embed.py
```

The synthetic suite checks exact root selection, numeric metadata and content,
signature-resource preservation, empty files, UTF-8 C escaping, real payload
compression/decompression, missing bundles, symlinks, unknown functional xattrs
and oversized files. It contains no Apple binaries or phone operations.
