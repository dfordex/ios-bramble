# 0224 readout and 0225 incremental repair

## Verdict: CONCERNS — progression confirmed, responsive UI still pending

The user can dismiss the lock screen with buttons, but reports extreme slowness
and no icons. The complete SYSTEM capture is flush 66, 592,110 logical bytes and
7,271 decoded lines. No kernel panic or backboardd crash is recorded. This does
not establish that all new packed-source/Float2 paths were exercised.

## Evidence

Line numbers below refer to the private complete 0224 capture, retained outside
Git. Raw logs, shader publications, Apple binaries and cache windows are not
committed.

| Evidence | Observation |
| --- | --- |
| 1099–5967 | 18 command buffers, CB2–19, complete with status 4/error 0/submitted 1 |
| 3029–3089 | Blur 100/104 query, native encoding and submission succeed |
| 4507–5481 | An uncached fragment waits, translates, compiles, publishes 1,120 bytes, is accepted by backboardd, and CB14 completes |
| 5209, 5324–5328 | AIR wall time 52.734 seconds; native backend 10.401 seconds, with about 0.240 seconds accounted child CPU at the preceding sample and approximately 4 MB compiler output |
| 6028–6048 | The 128-entry logical import table fills; eight subsequent surface imports fail |
| 6087–6089 | SpringBoard receives SIGTRAP; a new SpringBoard later runs as PID 356 |
| 6072–6078, 6906–6947 | Another fragment proceeds through translator, validator and native compiler exec markers; no completed publication survives the bounded HFS readout |
| 6879–6881 | 2,485,206,016 bytes read, zero storage errors; heavy aggregate lock contention remains |
| 7117 | HID queue head advances to 12,288, with full=0 |

Sampled display counters during much of this run are below 2 FPS, with one later
interval at 7.5. These are interval counters, not an isolated performance test.
Copy samples around 6 ms and waits around 30 ms do not alone explain the complete
UI delay. The compiler and backboardd tee budgets reach exactly 128 and 1,024
chunks respectively; missing later text is not proof that those processes stop.
The kernel resource log's `closed=0` is a client state, not a release counter.

## Findings and changes

### P1: retained textures exhaust import residency

Application texture ownership can legitimately outlive a command buffer.
Keeping every such texture permanently imported exhausts the fixed kernel table.
0225 separates texture ownership from import residency: a bounded weak LRU drops
only idle handles while retaining each original IOSurface. The next use obtains
a fresh generation and validates immutable geometry and usage.

Each synchronous operation pins its resolved handles through terminal fence
proof. Active/ambiguous DMA, failed unmap/release and stale geometry remain
quarantined. Alias checks use stable IOSurface identity rather than a temporary
token. The logical capacity stays **128**, physical windows stay **4**, and no
kernel resource capacity is increased.

Tests retain 384 textures against a 128-slot mock transport, preserve original
backing pixels, exercise lazy generation refresh and aliases, reject all-busy
eviction, and cover failed release/unmap and unknown fences. Actual provider
blur, 40 retained completed command buffers, copy/mip/memoryless paths and iOS
Werror compilation pass. Two old texture tests expected unsafe release after a
missing terminal fence; the unmodified baseline reproduces that failure. Those
expectations now require quarantine, retaining the successful-release checks.

### P1: unconditional NIR output adds disk traffic

Full NIR text is now opt-in with `A5_MIDGARD_DUMP_NIR=1`. A real compiler recipe
shrinks from 4,104,160 output bytes to roughly 0.4 KB. Four verbosity cases retain
identical native code, and all ten native outputs for static profiles 602–606
retain their existing pins. Validation and native metadata remain enabled.
This removes unnecessary I/O; it is not a claim that all frame latency is fixed.

The later 0224 fragment also compiles on the Mac to a genuine 1,536-byte program,
five registers and no TLS/WLS. Production cache/factory/emitter replay passes
eight format/packing/blend cases with a known compatible captured vertex. The
exact late device pipeline was outside the tee budget, so that pair is not
claimed as the captured device pair. The 1,120-byte phone publication and this
new publication bring the embedded cache from 27 to **29**.

### P1, unresolved: SpringBoard null process identity

Bounded reads of stock dyld metadata, two image headers and selected code/string
windows identify the intentional FrontBoardServices assertion:
`Invalid condition not satisfying: processIdentity`.

The unslid private function is `0x19b916880..0x19b916978`; a null identity enters
the assertion path and executes `BRK #0` at `0x19b916970`. It is not the nearest
export, `FBSWorkspaceInitialize`. Callers include SpringBoard framework and
AXSpringBoardServerInstance. The reason the identity is null is not established.
No assertion bypass or unsupported-instruction workaround is introduced.

### Selected stock applications were absent

Read-only catalog lookups confirm that Settings, Clock and Safari are absent,
while PosterBoard is present. Earlier staging intentionally selected six system
UI bundles. Missing application files independently prevent those application
icons from appearing; resource failures may affect other content as well.

The user explicitly selected **Settings, Clock and Safari**. Their exact 20H392
bundles contain 270 files and 3,536,989 bytes. A range-backed read-only Apple OS
image supplied them using about 64.6 MB of selective network data, without
hydrating the 6.16 GB IPSW. Temporary image/proxy resources were cleaned up.

Clock's original restore source is
`/private/var/staged_system_apps/MobileTimer.app`; the packager maps that exact
source to `/Applications/MobileTimer.app`. Source ownership is preserved,
including Clock's original 501:501 metadata. All 270 contents and app directory
modes/UID/GID were checked against the original metadata-bearing archive in the
final BOOT. Source bundles have no functional xattrs to omit.

Patch 0209 extends only the fixed installer app allowlist by these three names.
The host packager accepts the original six UI bundles or this exact three-app
set. The HFS installer retains its traversal, parent, mode, size and compressed
stream checks. Seven source-policy tests and the actual 364-file kernel
preflight pass.

## 0225 build and installation boundary

This is an incremental update of the verified 0224 root. Only the rebuilt generic
compiler backend is replaced; the working worker, translator, validator, baseline
compiler and recipes remain installed. `--compiler-backend-only` still requires
the complete validated package and the generic backend. It avoids carrying
unchanged large helpers again and leaves room for the requested app bundles.
It is not a fresh-root compiler installer.

Full XNU make exits 0. The payload contains 364 files, 29 complete shader stages,
17,211,339 raw bytes and 3,649,983 packed bytes. The signed provider is 962,816
bytes. BOOT is **25,669,648 bytes**, with a **25,002,448-byte** kernel. Every linked
segment and embedded file was checked in the image. The selected FDT stages at
`0x419e3800..0x419fd800`, below the unchanged `0x42000000` boundary.

Loader, ADT and DTBH are byte-identical to 0224. The only added argument is
`a5apps_install=1`: four cores, 736 MiB managed RAM, 32-sector I/O, native GPU,
quiet functional touch and disabled optional GPU suites remain selected.
Applications install through journaled HFS VFS before launchd, with no whole
USERDATA transfer. Physical installation acknowledgement and subsequent
app registration, icons, speed and input observations are separate checkpoints.

Guarded TWRP/model/BOOT p10/capacity checks passed. A fresh unbuffered file at
offset zero supplied all 25,669,648 bytes; `dd` acknowledged that count, `sync`
exited 0 and reboot was requested. No BOOT backup, post-write readback or whole
USERDATA transfer was performed. Application installation through VFS and the
physical results still require the next capture.
