# 0228 device readout

SYSTEM flush64 contains all813,801 logical bytes /9,217 lines without ring overwrite. Only the guarded a5xelte device was selected despite another phone also being connected. The first8,193 SYSTEM sectors were read; no partition writes or reboot occurred during this review.

## Verified checkpoints

- New963,888-byte provider installs; all367 payload entries complete/sync0.
- The phone's automatic translator/backend successfully publish two new genuine fragment programs,2,624 and1,072 bytes. Publication is captured; exact subsequent consumption of these two programs is not captured in the bounded provider output.
-83 captured command-buffer result records finish Completed/status4/error0. Eight source/panel sampled comparisons show no RGB/alpha mismatch. This is sampled evidence, not proof of all UI pixels or responsive interaction.
-65 touch and252 key HID records arrive. No kernel panic or captured MMU fault.

## Recorded failure and independent mapping failure

Backboardd aborts once with namespace13/code4, `Metal failed to build render pipeline`. The previous0227 fragment-specialization error is not the recorded abort here. The precise rejected pipeline descriptor and factory error are not present. Heap strings contain older attachment/format/blend contract mismatches; these are insufficient to identify the final failed predicate.

Before the abort, an external1200×489 BGRA8 source with2,351,104 allocation bytes imports but fails Map selector4 with `e00002be` (NoResources), logical slot115/generation2. This is a concrete second failure, not evidence that this specific map failure caused the later pipeline abort. Resource mapping capacity/reuse must be examined separately.

One separate siriactionsd SIGABRT occurs; it is not attributed to a GPU command-buffer failure.

## Bounded project request read

773,120 physical HFS bytes, including catalog nodes, retrieve the63 request names/current JSON bodies and the two explicitly logged stage publications where available. No full USERDATA image or unrelated private preferences are read. Saved request dates span older boots, so sorting modification dates alone does not identify the new request.

The two new function request bodies are present. No recovered complete-pipeline request contains their exact fragment constants. Consequently the old queued pipeline snapshots cannot be labeled the crashing new pipeline. The worker observes63 requests on its first scan and64 on a later scan; queue pressure still exists, while capture of the precise denied pipeline remains incomplete.

There is no explicit RGBA8 live acceptance receipt in this capture. Absence of the old rejection does not by itself prove the exact37×37 RGBA request was exercised. Next work: identify/replay the actual failed pipeline without losing its terminal receipt to output budgets, and fix the independent physical mapping-resource exhaustion/reuse path. Private logs, request identities and binary shader publications remain outside git.
