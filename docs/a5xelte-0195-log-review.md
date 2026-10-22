# 0195: runtime audit passes and native work resumes; black screen unresolved

## Read-only device evidence

Recovered SYSTEM flush 28: all 108,016 recorded bytes, no ring overwrite.
Decoded text is 107,771 bytes / 1,257 lines. The complete capture has no
process crash record or kernel panic. The user reports a black screen and
returned the lab phone to TWRP. Raw captures remain private.

| Lines | Observation |
| --- | --- |
| 874, 892 | Both backboardd and probe runtime audits check 14 class/protocol mappings and 751 methods with zero errors. |
| 898 | Stock Metal accepts the Mali device. |
| 1005, 1011 | Actual pipelines 602 and 603 bind their matching phone-compiled cache entries. Publication is now followed by real use. |
| 1013–1034 | Backboardd command buffer 2 submits clear0 and indexed 602/603. All three native jobs return status0, header1, MMU0. Command buffer reports Completed/error0. |
| 1046 | Shared buffer NonVolatile to Volatile transition succeeds. |
| 1088–1105 | Volatile to NonVolatile succeeds; command buffer3 submits two more 602/603 jobs with successful terminal fences and Completed/error0. |
| 1106–1113 | The existing live IOSurface sample matches256/256; one full-panel copy of surface23 completes. This is not a full-panel pixel comparison. |
| 1118–1119 | One GPU presentation reports8,294,400 copied bytes, CPUcopy0. |
| 1146 | iOS requests display off; `a5fb_keep_on` ignores the physical display-off request. |
| 1164–1257 | Subsequent windows show no new native work/presentation. Other services and SpringBoard requests continue. |

Thus the 0194 audit regression is fixed on the phone and the purge method is
actually exercised without the old selector crash. Five genuine native jobs
complete. This still does not establish correct iOS pixels: successful fences
and the private256-texel sample cannot prove the composed full-screen image
or physical scanout content.

There is no saved new shader rejection, command error, native MMU fault,
timeout or poisoned-context marker. The backboardd user-output tee is bounded,
so absence of later user-output text is not comprehensive process telemetry;
kernel crash/native-job and framebuffer counters are independently available.

The one SpringBoard privilege1007 denial is PRIV_DARKBOOT (darkboot flag
manipulation), not proof of GPU denial. Its effect is not established here.

## Next controlled observation

The user confirmed they did not try Home or power after the black screen.
Ignoring physical display off does not prove that the iOS compositor remains
awake and schedules new content. Sleep is therefore a testable possibility,
not an identified cause of the original black frame.

The same0195 installation was rebooted from TWRP without any new image write.
Try short Home/power presses after black, observe any visible change, then
recover another log. If waking still produces no image, compare actual
render-target and scanout pixels and inspect completion/wakeup scheduling;
do not claim that all GPU work is correct merely from the fences above.
