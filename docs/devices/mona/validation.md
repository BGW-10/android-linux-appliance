# Mona observations and pending validation

[Mona index](README.md) · [Sources and revisions](../../reference/sources.md)

## Read-only inspection on 2026-10-16

These samples were taken at different times, mostly with the display dozing.
They are historical observations, not a workload or electrical qualification.

| Item | Observation | Consequence |
| --- | --- | --- |
| Device/software | `mona`, Android 16, build `W1VAS36.62-22-26-7-2-3` | Recheck after OTAs. |
| Running kernel | `6.6.118-4k-g613d3a188049` | Already contains the USB serial changes. |
| Battery | Present, Good, Discharging; 80%; about 4.171–4.174 V, -143 to -148 mA, 24 C | External battery-rail power is still interpreted as battery discharge. |
| Fake SOC | `-22`; running config has the debug option disabled | The observed 80% is not proof that fake SOC works. |
| Charger | `qti_battery_charger` loaded; file at `/vendor_dlkm/lib/modules/qti_battery_charger.ko` | An Image-only update cannot change this driver. |
| OEM battery driver | `qti_glink_charger` and `mmi_charger` also loaded; `mmi_battery` also reports 80% | Check both power supplies and Android after deploying the override. |
| USB/wireless input | Both `online=0`; USB voltage about 5.188 V; Android says unpowered | This is not proof that the physical USB VBUS path is isolated. |
| CPUs | All eight online; CPUs 0–3 up to 1.8048 GHz; CPUs 4–7 up to 2.4 GHz | These are already available stock operating points. |
| CPU policy | WALT on both clusters; big-cluster `scaling_max_freq=1900800` | A 1.9008 GHz policy limit was present during inspection. |
| CPU history | Big-cluster time-in-state includes 2.4 GHz | The hardware has operated above the sampled limit. |
| Thermal state | Framework status 0; all sampled cooling devices at state 0 | No exposed cooling intervention at that instant; this does not exclude other limits. |
| Battery depletion zone | `socd=20`, with trip values 95, 98, 100 | This is depletion percentage, not degrees C. |
| Sleep/tuning | Doze disabled, Battery Saver off, USB autosuspend `-1`, Wi-Fi power saving off | Existing startup script already applies these settings. |
| Wakefulness | Display dozing; `/sys/power/wake_lock` empty; no PowerManager suspend-blocker wake lock | No named appliance wake lock was observed. Other wakeup sources may still be active. |
| Chroot launcher | CPU affinity 0–7, root cpuset | The sampled launcher is not limited to little cores; check actual service workers too. |
| USB peripheral | Realtek `0bda:8153`, Lenovo USB-C to LAN, power control `on` | Ethernet is available; CP210X was not attached during this inspection. |
| SELinux | Enforcing | No policy relaxation is needed for the observed root inspection. |

The pulled running `.config` and the previously generated configuration differ
only in `QTI_PMIC_GLINK_CLIENT_DEBUG` and tool metadata `PAHOLE_VERSION`
(130 versus 131). The previous clean baseline/final configuration comparison
changed only the debug flag. This comparison is not proof of module ABI
compatibility. The earlier validation compiled all three affected driver
objects; it did not produce a deployable vendor module distribution.

## Subsequent repository and deployment work

- Kernel fragment: `CONFIG_QTI_PMIC_GLINK_CLIENT_DEBUG=y` survived merging and
  `olddefconfig`; the three affected driver objects compiled. Full vendor module
  packaging and boot validation remain pending. USB serial changes were already
  flashed, according to the operator.
- The earlier framework ADB script was installed and its authenticated TCP
  listener checked without restarting it. Its backup is under
  `/data/adb/appliance/backups/20261016T120629-29511/`.
- The simplified scripts at appliance commit `103bb35` passed ShellCheck,
  shell syntax, and a temporary runit service exercise. They have not been
  installed/reboot-tested on the phone. No charging-control or fake-SOC write
  was performed in those checks.
- Appliance revision `830087d` added a shared Android boot helper, a root service
  environment, and the disabled charging script under `service.d`; printer
  application service files were removed. All eight shell files passed
  ShellCheck and BusyBox ash/host sh syntax checks. Temporary host checks
  exercised boot-wait success, delay, timeout, and the disabled charging path.
  This work adds no live-device or kernel-build results.
- The Wi-Fi link-event monitor was restored, and USB tuning now uses a
  BusyBox `uevent` listener. Temporary host checks covered both event paths and
  restart behavior. A read-only phone check confirmed Magisk BusyBox 1.36.1.1
  includes `uevent`; a five-second passive listener opened without error but
  received no events. The updated tuning script has not been deployed, and
  USB unplug/replug validation remains pending.

## Deployment order

1. Qualify the supply, reverse-current blocker, and phone-side overvoltage
   containment with a load and instruments, then the intended USB arrangement.
2. Build/package the matching charger module and kernel; retain recovery images.
3. After boot, confirm `fake_soc=-22`; manually set 80 and check kernel/Android
   capacity, `mmi_battery`, `socd`, and live voltage/current/temperature. Restore -22.
4. Install the simplified scripts during maintenance. Check ADB, SSH, one runit
   supervisor, the wake lock, first-unlock behavior, and long screen-off operation.
5. Validate serial and network recovery, sustained workload temperatures, and
   planned reboot. Keep MCU heater/watchdog protection intact.
6. Test total power-loss recovery separately. Manual fake SOC must be reapplied
   explicitly after reboot; automatic activation is not part of this setup.

The old audit's combined probes timed out while reading `/sys/power/wakeup_count`;
that read can wait for wakeup events. Later bounded probes omitted it and
succeeded. Do not use the timeout as evidence of a power fault. Temporary audit
files under `/tmp/mona-appliance-audit/` are not required documentation inputs.
