# 0238 runtime optimization review

Verdict: CONCERNS. Native rendering succeeds in the captured samples, but the
new presentation optimization is defeated by a concrete invalidation defect.
Shader cache misses and storage contention also cause long pauses. This review
reads the complete diagnostic ring and bounded shader artifacts; it does not
change or flash a new build.

## Current device evidence

The reserved SYSTEM ring decodes flush77,693248raw bytes without wrap, yielding
7321lines/693003UTF-8bytes. All4identity values still match iPhone10,5/D211AP.
The startup helper verifies all3 existing app proxies without registering again
and exits0. PosterBoard receives the new exact global-capture authorization,
initializes the GPU device and completes an empty command buffer. Its earlier
GPU-client initialization error and nil-dictionary crash are absent. One
PosterBoard external360x640 texture still rejects a null IOSurface, and a later
IOSurface create fails with zero geometry. Those observations do not establish
the originating property/creation failure; passing a null surface cannot be
fixed by silently allocating unrelated image contents.

There are65 captured CB result records, allCompleted/error0:64from backboardd
and one empty PosterBoard buffer. Captured begins contain1783 queued draws,
134clears and440render encoders; the largest buffer has114 operations.
The first32 native receipts have status0/MMU0. Eight panel/source sample grids
have4096samples each with zero RGB and alpha mismatches. No recorded kernel
panic, backboardd crash or SpringBoard crash appears. One driverkitd
per-process memory-limit death remains, versus21 in the previous capture;
the different runs do not prove causation from the registration change.

## Evidence and priorities

Line references below refer to the private complete0238 decoded log or to the
0238 staged kernel sources. Raw logs and captured shader artifacts stay outside
git. The patch files preserve the relevant staged changes.

| Priority | Finding | Evidence | Next concrete change |
|---|---|---|---|
| P1 | Damage comparison is invalidated by a no-op self presentation | Log1394/1397/1400 and2509/2514/2523 show surface23 copied, followed by surface1 (physical framebuffer). All band receipts through256 have partial0/unchanged0. SweetFramebuffer.cpp765 invalidates before the loop;786 skips s==fSurface without writing. | Invalidate only for actual panel mutations. Track direct CPU/GPU writes separately; preserve the shadow across a true no-op. Retest full/partial/unchanged/fade/fallback and real alias-write cases. |
| P1 | Shader cache misses synchronously block callers for minutes | Log5442: AIR translation exits0 after378.973s wall time;5554: backend exits0 after8.592s. MetalLibrary.m711-739 waits for a real cache entry. | Warm exact known specializations before interactive use and reuse their authenticated persistent publications. Investigate executable/page-in costs; retain real terminal failure reporting and avoid placeholder shaders. |
| P1 | Every draw retains a separate native transaction and full allocation coherency | A5MaliNative.c allocates/copies256KiB per submit. A5XELTENativeQueue.inc62-72 copies the job and cleans all mapped source/target/buffer bytes;88-97 runs and waits for both stages, then invalidates the entire written allocation. | Introduce bounded render-pass/CB batches and resource ownership generations. Coalesce redundant transfers/cleans under unchanged CPU ownership; keep true fences and required stage/alias dependencies. |
| P2 | Self presentation also consumes a presentation slot and inflates FPS |150 intervals total567 shown,282GPU copies,1CPU copy and282 self/missing-source records. Log6563 reports60shown/10.1fps but the paired line has30actual copies in5883ms. | Separate acknowledged swaps, changed scanouts and actual copies. Once a self presentation is proven no-op, acknowledge it in order without an extra scheduled panel operation. |
| P2 | Final presentation timing adds work time to a relative timer | SweetFramebuffer.cpp calls setTimeoutUS at the end of vsyncFired; sampled real-copy time is approximately19.53ms, and mean pending-record age25.70ms. | Use a bounded absolute presentation deadline and skip missed ticks. Measure pending age and actual job phases separately before changing the30Hz cap. |
| P2 | Storage is saturated for much of this run | Final eMMC counters:2863963136read/133513216written bytes,0errors,552072ms active; recorded FB windows total801130ms. Logger837ms; parallel aggregate lock wait14371002ms is not wall time. | Attribute reads/page faults to processes and files, then reduce repeated tool loading and unnecessary service work. Longer transfers/DMA need their own hardware validation; do not assume raising a block/frequency limit repairs this. |
| P2 | Two requested SpringBoard samplers are rejected | Log6171/6821 request normalizedCoordinates0. MetalDeviceResources.m717 rejects them; runtime_misc_encode.c hardcodes normalized coordinates in existing routes. | Carry pixel-coordinate semantics through API, reflected state and Mali sampler emission, then test with known pixels. Merely removing the API rejection is insufficient. |

## Presentation accounting

Of150 sampled intervals,108 have zero shown records, including startup and idle.
The completed presentation totals are282GPU and1CPU copies. GPU bytes are
2339020800, exactly282 times8294400: every captured GPU copy is full height.
There is no recorded GPU fallback. The partial-transfer change has therefore
not demonstrated any bandwidth saving on this run.

The highest reported FPS is10.1, but that window's actual panel-copy rate is
30/5.883=5.10 per second. This is a copy-event rate rather than proof of unique
visual frames. The approximate19.53ms per actual copy is reconstructed from
rounded interval means; it includes comparison, mapping, native presentation
and other work in present(). It is not isolated fragment-shader execution time.
The existing avg_wait_us is the age of a pending swap before presentation,
not a measured GPU fence duration. No controlled0237/0238 FPS comparison or
quantified gain from cooperative polling is established.

The unconditional invalidation is sufficient to force a full-height comparison
after the observed no-op sequence. Fixing it makes partial rendering possible;
it does not prove future frames have localized pixel changes. Direct writes to
the published framebuffer must still invalidate/version the shadow. The final
compiled-success stripe is a separate intentional overlay and needs an explicit
policy when comparing panel pixels.

## Shader and I/O follow-up

A bounded read of exactly four named request/artifact sets consumes210432physical
bytes. Three real fragment publications are present, with1760/880/1104byte
native code and matching receipt size/SHA256. Their source request canonical
hashes match their names and receipt identities. The fourth request is present
but has no public receipt/native code or private terminal status at recovery.
This proves persistent compilation works for three requests; it does not prove
a compiler crash for the unfinished fourth. Later worker messages are subject
to output budgets, so absence from the console is not completion evidence.

These are real function-constant variants, including different image/texture
functions and coordinate counts. Reuse/prewarm them with the exact request and
ABI identities; do not substitute a nearby variant. Dynamic receipts mark
pipeline_compatible=false because they are individual stages: the current
stage loader explicitly expects this flag before performing composition. It
is not, by itself, another pipeline rejection.

The first AIR tool spends378.973s elapsed but reports about11.19s CPU at exit.
Together with heavy storage traffic and tiny early resident sets, this makes
loading/I/O/scheduling a higher-value investigation than treating all six
minutes as shader arithmetic. Attribution is not yet proven. The service
already restores nice0, so suggesting that same priority change again would
not address new evidence. The phone continues to attempt bluetoothd57times
and fairplayd63times;383xpcproxy executions are also recorded. These are exec
counts, not all proven crashes. Their individual I/O/CPU costs are unmeasured.

The first implementation sequence should be: correct no-op invalidation and
presentation accounting; preserve/warm exact shader cache entries; add bounded
native batches with measured coherency ranges. Then assess storage attribution
and the sampler/IOSurface functional gaps. Required GPU memory ordering,
resource retention and real completion checks remain part of every step.
