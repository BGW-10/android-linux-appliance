# Mona deployment, validation, and recovery

[Documentation index](README.md)

This branch prepares a reproducible userspace policy for the Moto G Stylus 5G
(2025) on Android 16. The kernel investigation is in the separate
[Mona kernel documentation](https://github.com/BGW-10/moto-g-stylus-2025-kernel/tree/mona-appliance/docs/mona).
The printer configuration in this repository is retained as supplied.

## Observed installation

Read-only inspection on 2026-10-16 found:

- Magisk and `chroot-distro` 2.1.0, with `debian-trixie` under
  `/data/local/chroot-distro/`.
- Existing `appliance-tuning.sh` and `start-debian.sh` in Magisk `service.d`.
- An additional `enable-tcp-adb.sh` already on the phone, not in the original
  repository. It waits indefinitely for boot and always restarts `adbd`.
- `ro.adb.secure=1`, `ro.debuggable=0`, a TCP 5555 listener, and no configured
  `persist.adb.tcp.port` or `service.adb.listen_addrs` value.
- Both `ssh` and `sshd` enabled under Debian's runit service directory. They
  must be reconciled during migration; this change does not choose remotely.

The supplied replacements use the existing service.d convention. A separate
Magisk module would add another owner without helping this installation.
If packaging a module later, use its `service.sh`; do not also install competing
service.d copies. Keep long waits out of blocking `post-fs-data` scripts.
[Magisk boot-script documentation](https://topjohnwu.github.io/Magisk/guides.html#boot-scripts).

## Persistent ADB

Install `tools/install-android.sh --adb-only` from an Android root shell.
This installs the shared library, creates configuration only if absent, and
backs up/replaces the ADB boot script. It does not require a kernel change.

At each boot the script waits at most 180 seconds for `sys.boot_completed`,
checks `ro.adb.secure=1`, and requests `service.adb.tcp.port=5555`. It restarts
`adbd` once only when the property/listener state needs changing, then checks
for a listener for at most 30 seconds. A healthy existing TCP connection is
left running. It does not repeatedly override a later deliberate `adb usb`.

AOSP gives `service.adb.listen_addrs` precedence over the TCP-port properties;
the script reports a conflict instead of overwriting that separate policy.
The per-boot port property avoids a lingering persistent property after disabling
the script. [AOSP adbd implementation](https://android.git.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/daemon/main.cpp).

Authentication, host authorization keys, USB composition, and SELinux remain
in place. Classic `adb tcpip` is not the TLS-paired wireless-debugging transport;
restrict it to a trusted management LAN/VPN boundary. Configure a DHCP reservation
for Ethernet/Wi-Fi as appropriate. No firewall rule is guessed from the current
IP address. Keep an authorized USB recovery host available.

After the next attended reboot, without first issuing `adb tcpip`:

```sh
adb connect PHONE_IP:5555
adb shell getprop service.adb.tcp.port
adb shell getprop ro.adb.secure
adb shell "su -c 'cat /data/adb/appliance/log/enable-tcp-adb.log'"
```

Expect `5555`, `1`, and a successful listener message. Test boot before first
unlock too. A boot that never reaches readiness or a failed Magisk installation
still needs USB/local recovery; this script cannot run in the bootloader.

### Disable ADB startup

Set `ADB_TCP_ENABLED=0` in `/data/adb/appliance/config.sh`, or remove executable
permission from `/data/adb/service.d/enable-tcp-adb.sh`. This affects future
invocations; it does not close an already running listener. To close it now,
use an authorized **USB** connection and `adb usb`, or from a local root shell:

```sh
setprop service.adb.tcp.port -1
setprop ctl.restart adbd
```

That restart disconnects TCP sessions. This version does not set
`persist.adb.tcp.port`; inspect and remove any separate policy if another tool
has configured it. File backups are under `/data/adb/appliance/backups/`.

## Debian migration

Perform this while the printer is idle, heaters off, and with independent ADB
access. Install Debian files before enabling the new Android launcher. Do not
run both the old and new service supervisors.

1. Install `runit`, `openssh-server`, and `util-linux` in Debian. Run
   `tools/install-debian.sh` there. It saves replaced files under
   `/var/backups/appliance/` and preserves an existing
   `/etc/default/appliance-services`.
2. Inspect `sv status /etc/service/*` and the process tree. Choose the packaged
   `ssh` service or the repository's `sshd`, keeping the appropriate service's
   configuration and key policy. For the repository's logging, select `sshd`.
   Remove only the unwanted link in `/etc/service`, never the service directory
   containing configuration. Arrange a maintenance window for the SSH restart.
3. For the old plain `runsvdir` launcher, record its exact PID from `ps`. Bring
   its services down with `sv -w 20 down /etc/service/*`, verify they stopped,
   then send **HUP** to that confirmed `runsvdir` PID. HUP terminates its runsv
   children; TERM alone does not. Do not use a broad `killall` or `pkill`.
   [runsvdir signal behavior](https://smarden.org/runit/runsvdir.8).
4. Stop the existing Android Wi-Fi monitor before starting its replacement.
   Inspect the `appliance-tuning.sh` process tree and terminate only those
   confirmed processes, or perform the migration through an attended reboot.
5. Run `tools/install-android.sh --all` on Android and review
   `/data/adb/appliance/config.sh`. Set `DISTRO`/`CHROOT_DISTRO` as installed;
   leave charging inhibition disabled. The installer neither unmounts Debian
   nor restarts it. Existing configuration is retained, so review new options
   when upgrading.
6. Start once through Magisk's BusyBox shell or use the next attended reboot.
   Check the Android log, Debian `start-services status`, actual worker cpusets,
   and the `klipper-appliance` entry in `/sys/power/wake_lock`.

`start-debian.sh` bounds mount commands, retries mount failures three times with
backoff, and does not start services after a failed mount. It logs the real
supervisor exit status. Runit handles individual service restarts. A whole
supervisor failure requires inspection and manual restart, avoiding an automatic
printer-stack reboot/restart loop.

The Debian wrapper refuses an already supervised service directory. Its file
lock prevents duplicate wrappers; child processes do not inherit that lock.
It acquires the named kernel wake lock before launching services. A normal stop
requests service shutdown, terminates runsvdir, and releases the lock only when
cleanup succeeds. Unsupported wake-lock interfaces fail startup by default;
`REQUIRE_WAKE_LOCK=0` is only for a host with another proven suspend blocker.

### Supervisor failure recovery

`start-services stop` validates the recorded PID's start time before signaling
it. If shutdown fails, it reports failure and retains the wake lock when held.
Do not release that lock while printing or while service shutdown is unresolved.

SIGKILL and sudden power loss cannot run shell cleanup. For an orphan:

1. Inspect `/run/appliance-services/{owner,runsvdir}`, `ps`, and
   `sv status /etc/service/*`. The records include process start times; stale
   PIDs must not be blindly signaled.
2. With heaters off and printing stopped, shut down surviving services and
   their confirmed supervisor as in the migration sequence. Check for orphaned
   workers and logs that are still draining.
3. After confirming nothing depends on the lock, release only this owner's lock:
   `printf 'klipper-appliance\n' > /sys/power/wake_unlock`.
4. Start the wrapper again. `flock` releases automatically when its owner exits;
   do not delete a lock file while another process holds it.

## Android tuning and rollback

The profile changes Doze, Battery Saver, its automatic threshold, selected USB
runtime-power settings, and Wi-Fi power saving. It leaves adaptive-power-saver
policy, CPU frequency limits, governors, scheduler placement, and thermal rules
alone. Saved settings are at `/data/adb/appliance/tuning-baseline/`; they represent
what was observed before this profile first touched each control, including
settings already changed by your earlier script.

Add actual printer and Ethernet VID:PID pairs to `USB_KEEP_AWAKE_IDS`. Newly
attached matching devices are handled at the next poll, not instantly. The
profile does not change global USB autosuspend or every Android USB device.
USB rollback checks the saved port's VID:PID before restoring its `power/control`.
Different devices or missing interfaces require operator review.

To stop and restore, from an Android root shell:

```sh
ASH_STANDALONE=1 /data/adb/magisk/busybox sh /data/adb/service.d/appliance-tuning.sh --restore
```

This signals the monitor to stop, waits for its lock, then restores saved
values. Also set `ENABLE_TUNING=0` for later boots. Keep the baseline until the
restored state is checked; archive it before deliberately establishing a new
baseline. Changes persist if only the script is deleted. Disabling Doze does
not replace the service-owned wake lock.

## Optional charging inhibition

Keep both `ENABLE_CHARGING_INHIBIT=0` and `CHARGING_HARDWARE_QUALIFIED=0` until
the XL4015 circuit is electrically qualified. Follow the separate
[USB-C power investigation](https://github.com/BGW-10/moto-g-stylus-2025-kernel/blob/mona-appliance/docs/mona/usb-power.md):
a reverse-current blocker protects the converter, but incoming charging energy
can still raise the phone-side rail. Independent containment is necessary for
that fault. Software cannot cover bootloader time.

After qualification, with one charging-policy owner, setting both options to
`1` enables the Mona-only script. It waits up to 120 seconds for the driver,
checks that `force_charging_enable` reads zero, and writes only `1` to Motorola's
`force_charging_disable`. It checks again every 30 seconds and logs observed
status, voltage, current, input state, and role. Missing/conflicting controls
produce an error. Polling can miss short attach/reset events; repeated same-value
writes may be cached and cannot prove firmware enforcement.

Use `charging-inhibit.sh --once` via Magisk BusyBox for an attended first test.
Measure converter-side current direction and phone-side peak voltage with
external instruments while checking USB data. Sysfs measurements alone do not
qualify protection. The script neither turns charging on to refresh the vote
nor changes `force_charger_suspend` or debugfs charging overrides.

`charging-inhibit.sh --stop` stops polling without clearing the write-only
vote. Set `ENABLE_CHARGING_INHIBIT=0` for future boots. Only after removing
incoming charging sources and confirming ownership of the vote, manually write
`0` to `/sys/class/power_supply/battery/device/force_charging_disable` to remove
this inhibit. Never use `force_charging_enable=1` as rollback.

## Remaining qualification

- Test authenticated ADB after reboot and before first unlock; check Ethernet
  and Wi-Fi addresses independently.
- Test one supervisor, wake-lock acquisition/cleanup, a long screen-off idle,
  service failure, USB reconnection, and log/free-space limits while attended.
- Leave WALT and thermal policy in place. Measure actual worker CPU limits and
  thermal sensors under realistic workloads before comparing governors or
  adding cooling. Do not infer safe rail behavior from CPU frequency alone.
- Keep fake SOC manual. The kernel's charger module still needs to be rebuilt
  and deployed; these scripts never write `fake_soc`, spoof Android battery
  state, or mask voltage/current/temperature readings.
- Retain MCU heater/watchdog shutdown. Verify end-to-end serial reliability
  before printing; do not change printer safety limits to hide host stalls.
- Validate recovery from input-power loss separately. Magisk cannot power on
  a phone whose bootloader has not started; consider a qualified upstream UPS
  and a controller for the power-key contact if needed.

Host test results cover script behavior and real runit lifecycle on the
workstation. They do not qualify the buck converter, charging firmware, or
unattended printing. Reboot and electrical results must be recorded after the
corresponding attended tests.

### Implementation validation, 2026-10-16

- All 14 host tests passed, including real runit start/stop, supervisor death,
  and retaining the wake lock after a failed shutdown.
- ShellCheck and BusyBox ash syntax checks passed. The Android scripts also
  parsed under the phone's Magisk BusyBox 1.36.1.1. That version lacks
  `flock -w`; the Android restore path uses bounded nonblocking retries instead.
- Only the ADB startup script and its shared library/configuration were installed
  on the phone. The replaced script was backed up at
  `/data/adb/appliance/backups/20261016T120629-29511/enable-tcp-adb.sh`.
  Its replacement's SHA-256 matched the repository file.
- Running the installed ADB script found the existing authenticated TCP 5555
  listener and exited successfully without restarting it. A fresh root ADB
  command confirmed `ro.adb.secure=1`, `init.svc.adbd=running`, SELinux Enforcing,
  and `fake_soc=-22`.
- Existing phone `appliance-tuning.sh` and `start-debian.sh` hashes were unchanged.
  Debian migration, new tuning, and charging inhibition have not been deployed.
  No reboot, kernel flash, charging-control write, or printing test was performed.
