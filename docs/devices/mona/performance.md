# Mona performance and cooling

[Mona index](README.md) · [Supply requirements](power.md)

Use stock WALT and thermal policy as the baseline. The kernel already has the
performance governor and named wake-lock support; additional performance
Kconfig changes are not justified by the [recorded inspection](validation.md).
The frequency-cap cause is unresolved. Measurements below describe one session,
not a current guarantee or a sustained-load test.

## Preserve thermal management and investigate the existing cap

The big cluster exposes 2.4 GHz but was repeatedly limited to 1.9008 GHz during
the inspection. The Qualcomm performance max-vote node at
`/sys/kernel/msm_performance/parameters/cpu_max_freq` showed the unconstrained
value `2147483647` on all cores, and thermal cooling states were zero. The
source of the remaining limit is unresolved; do not label it battery throttling
without a controlled comparison. Vendor services or another frequency QoS
request may own it.

The live `/vendor/etc/thermal-engine-mona.conf` contains CPU limits based on
virtual board/skin sensors, including a 1.9008 GHz action. That identifies one
possible policy path, not proof that it was active. Stock Power HAL, perfservice,
thermal-engine, and thermal HAL were running. Compare frequency limits with
display state, workload, board temperatures, and power hints before changing a
policy. Read `cpuinfo_cur_freq` as well as `scaling_cur_freq`; a requested
frequency alone does not prove delivered performance.

Android's [fixed performance mode](https://developer.android.com/games/optimize/adpf/fixed-performance-mode)
selects a repeatable operating point rather than maximum throughput. It is not
the appliance tuning switch to use. This phone's vendor sustained-performance
profile also contains lower frequency caps. Avoid enabling either blindly.

Stock thermal policy can react to battery power constraints as well as
temperature; Android documents these roles in its
[thermal mitigation guide](https://source.android.com/docs/core/power/thermal-mitigation).
Do not stop thermal-engine, spoof temperatures, disable BCL, or keep overwriting
thermal frequency limits. The sampled HAL thresholds are policy reports, not
safe temperatures to target. A heatsink can improve sustained stock clocks
without changing those protections.

## Controlled governor comparison

The running kernel already has `CONFIG_CPU_FREQ_GOV_PERFORMANCE=y`, and
`performance` is listed in both policies. After supply qualification, compare
WALT and performance under the real workload with the display off. The
[performance governor](https://docs.kernel.org/admin-guide/pm/cpufreq.html)
requests each policy's highest permitted frequency; it does not defeat other
limits or create higher hardware operating points.

Example reversible test, in one root shell. Save these values before applying
the test, and run the restoration even if the workload fails:

```sh
p0=/sys/devices/system/cpu/cpufreq/policy0
p4=/sys/devices/system/cpu/cpufreq/policy4
old_gov0=$(cat "$p0/scaling_governor")
old_gov4=$(cat "$p4/scaling_governor")
echo performance > "$p0/scaling_governor"
echo performance > "$p4/scaling_governor"
# Run the intended workload and record throughput, latency, volts and temperatures.
# Restore in this same shell:
printf '%s\n' "$old_gov0" > "$p0/scaling_governor"
printf '%s\n' "$old_gov4" > "$p4/scaling_governor"
```

For a later test of the 1.9008 GHz cap, first establish that the supply is sound
and the cap is an ordinary user policy rather than an active protective request.
Save `scaling_max_freq`, request the advertised `cpuinfo_max_freq` once, and
inspect the effective readback. A lower readback or a returning limit calls for
tracing its owner, not a loop that fights it. Restore the previous user setting
after the experiment. No such write was made in this investigation.

The local [Qualcomm CPUFreq driver](https://github.com/BGW-10/moto-g-stylus-2025-kernel/blob/533a0b4f7464/drivers/cpufreq/qcom-cpufreq-hw.c) reads
hardware frequency/voltage lookup tables. Overclocking beyond 2.4 GHz is not a
defconfig toggle; it would require platform-specific clock/voltage/firmware
work and electrical validation. For an unattended host, recovering available
stock performance and improving cooling is the useful first target.

## Keep services awake and measure the actual workers

Use the [shared runit launcher](../../services/runit.md#keeping-the-phone-awake).
Its `klipper-appliance` wake lock stays held until reboot or deliberate release.
Doze disabled alone does not prevent kernel suspend, and a wake lock does not
pin CPU clocks. The [boot script](../../setup/boot-services.md) handles selected
USB devices and Wi-Fi without changing governors or thermal limits.

Check `/proc/WORKER_PID/cgroup` and `Cpus_allowed_list` in
`/proc/WORKER_PID/status`, not just the launcher. The sampled launcher had CPUs
0–7 available; this phone's Android background cpuset had only CPUs 0–3.
Measure throughput, scheduling latency, USB disconnects, voltage, and board/PMIC
temperatures with the display off before changing affinity or priorities.

A fake SOC of 80 should make `socd` report 20 because that zone represents
`100 - capacity`, not Celsius. Separate voltage/current BCL limits stay active.
Preserve them. Sensor values such as `-2147483648` or `-273000` can mean unavailable;
do not interpret them as low temperatures or justify more aggressive clocks.
