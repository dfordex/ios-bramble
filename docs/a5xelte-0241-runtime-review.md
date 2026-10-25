# 0241 runtime review and 0241b installation

## Result

Immutable upload reuse executes on the phone and the captured native work completes without a reported GPU fault. This run does **not** demonstrate a performance improvement. Only17 completed command buffers and17 actual panel copies occur across roughly727seconds of sampled intervals, including startup, idle and shutdown. The peak actual-copy interval is0.94/s, below0240's5.13/s; workloads are not replay-controlled, so this is not a quantified causal regression of the arena change.

## Readout scope

Read the8193-sector SYSTEM diagnostic area before installing the follow-up. Flush70 contains527898 recovered bytes,5993 decoded lines/527641UTF-8 bytes, without ring overwrite. Private raw logs, analysis scripts and machine-readable results are retained in workspace research build0241/runtime. No full USERDATA transfer or additional shader-file read was needed.

| Observation | Result | Limit |
| --- | --- | --- |
| Command buffers |17 captured results, all Completed/error0 | These are all recorded results, not a claim that every conceivable workload succeeds |
| Native groups |14 sampled receipts:11count1,3count2; all completed/status0; last group384 | First8/every64 logging does not reveal the distribution of all384groups |
| Upload arenas |8 sampled session summaries;8creates,36writes,19resets,3362816 staged bytes total; all result0/uncertain0 | Session summaries are bounded samples; reset includes initial allocation/growth, not only exhausted capacity |
| Queue/mapping |No admission-wait or mapping-failure diagnostic; no nonzero Query17 result | No contention recovery was exercised in the recorded diagnostics; this cannot prove all prior failures fixed |
| Native phases |128 captured phase receipts, none nonzero | Early detailed logging is bounded |
| GPU completion |32 native status0/MMU0;34 AS0 fence receipts complete/MMU0 | Different queues/counters must not be combined as one workload count |
| Pixel samples |8grids of4096 points; RGB/alpha mismatch0 | Samples do not prove every pixel/every frame |
| Presentation |15GPU +2CPU copies;124416000GPU bytes;0GPUfallbacks | Full frame mode remains selected;14self/missing-source records are not copies |
| HID |35touch/20key records | Kernel reception does not prove prompt compositor/UI response |
| Crashes |No recorded kernel panic, backboardd/SpringBoard/PosterBoard crash;1driverkitd SIGKILL namespace1/code7 | The per-process memory-limit kill persists |
| Shader wait |No captured waiting request or new compile-request receipt | Does not rule out uninstrumented cache/file work |

## Remaining slowdown

137presentation intervals include123with zero shown;36shown includes no-ops. Peak reported1.8shown/s includes no-ops; peak paired actual copy rate is0.936/s. Reconstructed presentation cost is12.743ms/actual copy, close to0240's12.741ms. The estimate is sum(avg_copy_us*shown)/(GPU+CPU copies), not isolated hardware execution time. Pending-age estimate23.607ms also does not explain all time before a frame is submitted.

The current record does not identify the dominant delay. Low frame production, mostly single-item sampled groups and19sampled arena resets remain visible, despite removal of per-draw allocation. At least some current boundaries also involve clear/resource/surface changes and arena rollover; simply increasing the four-item limit is not supported by this evidence. The next diagnostic should timestamp command-buffer entry/exit, query/upload/flush and individual terminal jobs, and count group-boundary reasons. Keep the hardware fences and immutable-resource guarantees.

Final storage counters:2444342272B read,120061952B written,0errors; cumulative active471483ms, maximum request67ms, log976ms. Aggregate concurrent lock wait is not wall time. These counters justify investigating I/O ownership alongside render timing; they do not attribute the UI delay to a particular process or shader. The log ends with orderly shutdown initiated by SpringBoard, HFS unmount and CPU halted, rather than a recorded panic. The reason for the shutdown is not established from this readout.

## 0241b installed after saving0241

0241b was already built and offline-verified. It restores the output reply capacity before a regular allocation retry after a failed transport zeroes the size. This is a correctness fix for allocation-pressure recovery, not a promised FPS fix, and0241 did not capture that failure.

Recovery/model/TWRP/BOOT-p10/capacity guards pass. The host image matches its prepared offline proof; offset-zero write acknowledges25856016bytes, sync succeeds and reboot is requested. No BOOT backup/post-write readback/hash or whole USERDATA transfer. Private installation receipt and script are retained in research build0241b. This establishes installation, not0241b runtime performance or rendering. Physical UI response and the next runtime log remain pending.
