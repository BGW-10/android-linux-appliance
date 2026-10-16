# Install and operate the Mona scripts

[Documentation index](README.md) · [Adding runit services](runit.md)

The files mirror their Android or Debian destination paths. Edit the few
settings directly in each script, then copy the files you want. Work while the
printer is idle with heaters off, and keep an authorized ADB connection available.

## 1. Prepare Debian

Inside the Debian chroot, as root, with this checkout accessible:

```sh
apt install runit util-linux openssh-server
repo=/path/to/klipper-android-appliance-scripts
mkdir -p /etc/sv /etc/service /usr/local/bin

# Back up any existing files at these destinations before replacing them.
install -m 755 "$repo/debian/usr/local/bin/start-services" /usr/local/bin/start-services
cp -a "$repo/debian/etc/sv/sshd" /etc/sv/
chmod 755 /etc/sv/sshd/run /etc/sv/sshd/log/run
```

Use the `runit` package for its tools; Android remains PID 1. Inspect
`ls -l /etc/service` and `sv status /etc/service/*`. Enable exactly one SSH
service. If the packaged `ssh` is already enabled, either keep it or stop it
from an ADB/local shell and remove its `/etc/service/ssh` **symlink** before
using this repository's `sshd`. Stopping SSH disconnects SSH sessions.

To enable the supplied definition once that is resolved:

```sh
ln -s /etc/sv/sshd /etc/service/sshd
```

Keep existing SSH keys and authentication settings. The launcher starts all
linked services; see [runit](runit.md) to add Klipper, Moonraker, or another daemon.

## 2. Install the Android boot scripts

Prerequisites: Magisk, `/system/bin/chroot-distro`, and the existing Debian
chroot. Review `DISTRO` in `start-debian.sh` and the device IDs/Wi-Fi settings in
`appliance-tuning.sh`. Record your Battery Saver threshold before changing it:
`settings get global low_power_trigger_level` in an Android root shell.

Copy the checkout to the phone, then run in an **Android root shell**:

```sh
repo=/data/local/tmp/klipper-android-appliance-scripts
backup=/data/local/tmp/appliance-backup-$(date +%Y%m%d-%H%M%S)
mkdir -p /data/adb/service.d "$backup"
cp -a /data/adb/service.d "$backup/"

# For ADB only, use just enable-tcp-adb.sh in this list.
for script in enable-tcp-adb.sh appliance-tuning.sh start-debian.sh; do
    cp "$repo/android/data/adb/service.d/$script" "/data/adb/service.d/$script.new"
    chmod 700 "/data/adb/service.d/$script.new"
    mv -f "/data/adb/service.d/$script.new" "/data/adb/service.d/$script"
done
```

Magisk runs executable service.d scripts through its BusyBox shell. For a manual
invocation, use the same environment, for example:

```sh
ASH_STANDALONE=1 /data/adb/magisk/busybox sh /data/adb/service.d/enable-tcp-adb.sh
```

[Magisk boot-script documentation](https://topjohnwu.github.io/Magisk/guides.html#boot-scripts).

### Updating from the earlier framework

Replace Debian's launcher and the Android scripts together, then use an
**attended reboot** to retire the old supervisor/monitor processes. Do not start
a second supervisor alongside the old one. The new files ignore
`/data/adb/appliance/config.sh` and `/etc/default/appliance-services`; move any
wanted settings into the scripts themselves. Keep the old backups until verified.

The optional charging script now lives under `examples/android/`. If the old
`/data/adb/service.d/charging-inhibit.sh` is present but unused, move it into
`$backup` before reboot. If you already enabled a charging policy, review the
[optional charging section](#optional-charging-inhibition) and qualify its
replacement before changing that policy.

## 3. Verify after an attended reboot

From the workstation, without manually running `adb tcpip` first:

```sh
adb connect PHONE_IP:5555
adb shell getprop service.adb.tcp.port
adb shell getprop ro.adb.secure
```

Expect `5555` and `1`. Check `/data/local/tmp/enable-tcp-adb.log`,
`start-debian.log`, and `appliance-tuning.log` on Android. Each script replaces
its own log when it starts. Repeated tuning failures go to Android's log buffer:
`logcat -d -s appliance-tuning`.

Inside Debian, check `sv status /etc/service/*` and
`cat /sys/power/wake_lock` for `klipper-appliance`. SSH logs are under
`/var/log/sshd/`. Confirm screen-off networking and printer serial reliability
before a print. A failed mount is logged and not retried automatically; if the
chroot needs first unlock, unlock and invoke `start-debian.sh` manually afterward.

The ADB script requests the port once per boot and restarts adbd only when its
current properties require it. Verify connectivity separately; it does not
monitor the listener. Classic TCP ADB is not TLS-paired wireless debugging.
Keep it on a trusted management LAN, retain host-key authentication, and use
`adb shell` followed by `su` for root.

## Settings and disabling scripts

- **ADB:** remove executable permission from `enable-tcp-adb.sh` to disable
  future startup. To close TCP now, use `adb usb` from an authorized USB host;
  this disconnects TCP sessions.
- **Debian:** remove executable permission from `start-debian.sh` to skip it
  next boot. Manage running services with `sv`; see the wake-lock notes in the
  [service guide](runit.md#keeping-the-phone-awake).
- **Tuning:** edit the USB IDs, Wi-Fi interface, or Wi-Fi switch at the top of
  `appliance-tuning.sh`. Its small loop handles USB reconnects every 30 seconds.
  To stop applying tuning, remove executable permission and reboot. Re-enable
  Doze with `cmd deviceidle enable` if needed, and restore your chosen Battery
  Saver settings/threshold in Android. The threshold setting persists across
  reboots; deleting a script does not restore it. If you used the old framework,
  its `tuning-baseline` directory may contain your earlier values.

Rollback means restoring the saved files and doing another attended reboot.
A reboot clears this launcher's wake lock. There is no custom start/stop/status
interface or saved-settings database in the simplified scripts.

## Optional charging inhibition

The [hardware guide](https://github.com/BGW-10/moto-g-stylus-2025-kernel/blob/mona-appliance/docs/mona/hardware.md)
explains reverse-current blocking and phone-side voltage protection. Keep both
flags at `0` in [charging-inhibit.sh](../examples/android/charging-inhibit.sh)
until that circuit is electrically qualified.

After qualification, set both flags to `1` in a local copy and run it manually
through Magisk BusyBox for an attended test. It checks Mona and the conflicting
forced-charge setting, then requests Motorola's charging-disable vote **once**.
It does not poll/reassert after USB events or firmware resets, and cannot cover
the bootloader. Measure actual current direction and rail voltage. To request
it each boot later, copy the reviewed file into `/data/adb/service.d/` and make
it executable; keep one charging-policy owner.

Removing the script does not clear its write-only vote. After removing incoming
charging sources and confirming ownership, write `0` to
`/sys/class/power_supply/battery/device/force_charging_disable` to remove it.
Do not use `force_charging_enable=1` as rollback. Fake SOC remains a separate
manual kernel operation.

## Deployment status

The earlier framework version of the ADB script was installed on 2026-10-16;
its backup is under `/data/adb/appliance/backups/20261016T120629-29511/`.
This simplification has not been installed on the phone. Host validation covers
shell syntax, ShellCheck, and a temporary runit service exercise. Phone reboot,
Klipper/Moonraker integration, and electrical qualification remain to be done.
