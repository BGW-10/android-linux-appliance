# Install and operate the boot scripts

[Documentation index](../README.md) · [Adding runit services](../services/runit.md)

The files mirror their Android or Debian destination paths. Edit the few
settings directly in each script, then copy the files you want. Work while the
printer is idle with heaters off, and keep an authorized ADB connection available.

## 1. Prepare Debian

Inside the Debian chroot, as root, clone a local copy if you do not already
have one there. An Android `/data/local/tmp` checkout is not automatically visible
inside the chroot:

```sh
apt install git runit util-linux openssh-server
git clone -b mona-appliance https://github.com/BGW-10/android-linux-appliance.git /root/android-linux-appliance
repo=/root/android-linux-appliance
mkdir -p /etc/sv /etc/service /usr/local/bin

# Back up any existing files at these destinations before replacing them.
install -m 755 "$repo/debian/usr/local/bin/start-services" /usr/local/bin/start-services
install -m 755 "$repo/debian/usr/local/bin/android-cmd" /usr/local/bin/android-cmd
cp -a "$repo/debian/etc/sv/sshd" /etc/sv/
chmod 755 /etc/sv/sshd/run /etc/sv/sshd/log/run
```

An existing checkout can keep its directory name. After the repository rename,
run this from that checkout and use its actual path for `repo` above:

```sh
git remote set-url origin https://github.com/BGW-10/android-linux-appliance.git
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
linked services; see [runit](../services/runit.md) to add your own daemons.

### Android commands from Debian

As Debian root, use `android-cmd getprop ro.product.device` to run Android's
`/system/bin/getprop`. The helper forwards the command and its arguments through
`chroot /proc/1/root`, using Android's filesystem. It assumes `/proc/1` is
Android's init process, as in this chroot setup.

## 2. Install the Android boot scripts

Prerequisites: Magisk, `/system/bin/chroot-distro`, and the existing Debian
chroot. Review `DISTRO` in `start-debian.sh` and the device IDs/Wi-Fi settings in
`appliance-tuning.sh`. Leave both charging-inhibit switches at `0` until you
have followed [the Mona charging guide](../devices/mona/usb-power.md#optional-charging-inhibition).
Record your Battery Saver threshold before changing it:
`settings get global low_power_trigger_level` in an Android root shell.

From the **host**, push the checkout (adjust its local path):

```sh
adb push /path/to/android-linux-appliance /data/local/tmp/
```

Then run in an **Android root shell**:

```sh
repo=/data/local/tmp/android-linux-appliance
backup=/data/local/tmp/appliance-backup-$(date +%Y%m%d-%H%M%S)
mkdir -p /data/adb/service.d /data/adb/appliance "$backup"
cp -a /data/adb/service.d "$backup/"
if [ -f /data/adb/appliance/common.sh ]; then
    cp -p /data/adb/appliance/common.sh "$backup/common.sh"
fi

# Install the shared helper first, including for an ADB-only installation.
cp "$repo/android/data/adb/appliance/common.sh" /data/adb/appliance/common.sh.new
chmod 600 /data/adb/appliance/common.sh.new
mv -f /data/adb/appliance/common.sh.new /data/adb/appliance/common.sh

# For ADB only, use just enable-tcp-adb.sh in this list.
for script in enable-tcp-adb.sh appliance-tuning.sh start-debian.sh charging-inhibit.sh; do
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

`common.sh` is sourced by ADB, tuning, and Debian startup. It contains
`wait_for_android_boot`, which returns failure after three minutes. Keep helpers
outside `service.d` so Magisk runs only the entry scripts. Logs and settings stay
in each entry script. Charging inhibition waits for its control node directly,
since that request should not depend on Android finishing boot.

### Updating from the earlier framework

Replace Debian's launcher and the Android scripts together, then use an
**attended reboot** to retire the old supervisor/monitor processes. Do not start
a second supervisor alongside the old one. The new files ignore
`/data/adb/appliance/config.sh` and `/etc/default/appliance-services`; move any
wanted settings into the scripts themselves. Keep the old backups until verified.

Charging inhibition now lives in `android/data/adb/service.d/` and exits without
touching charging controls when disabled. If you already enabled an earlier
charging policy, review and carry over its intended settings before copying
files, and qualify the replacement using the
[Mona charging guide](../devices/mona/usb-power.md#optional-charging-inhibition).

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
  [service guide](../services/runit.md#keeping-the-phone-awake).
- **Tuning:** edit the USB IDs, Wi-Fi interface, or Wi-Fi switch at the top of
  `appliance-tuning.sh`. Magisk BusyBox's `uevent` listener triggers USB checks
  on add, driver-bind, and change events. Each listener start also scans devices
  already attached. Only matching `USB_IDS` get `power/control=on`; the listener
  restarts after five seconds if it exits.
  Wi-Fi uses the original link-event monitor: apply at startup, then reapply and
  verify two seconds after `state UP`; restart the monitor after five seconds
  if it exits. Events and Wi-Fi results go to `appliance-tuning.log`.
  To stop applying tuning, remove executable permission and reboot. Re-enable
  Doze with `cmd deviceidle enable` if needed, and restore your chosen Battery
  Saver settings/threshold in Android. The threshold setting persists across
  reboots; deleting a script does not restore it. If you used the old framework,
  its `tuning-baseline` directory may contain your earlier values.
- **Charging:** `ENABLE_CHARGING_INHIBIT=0` skips the request on future runs.
  Clearing an already-applied vote requires the manual rollback in the
  [charging guide](../devices/mona/usb-power.md#optional-charging-inhibition).

USB monitoring requires the Magisk BusyBox `uevent` applet. Check it in an
Android root shell with `/data/adb/magisk/busybox uevent --help`. This is a
separate kernel-event listener; Android's own device manager keeps running.
The script uses [BusyBox's per-event callback](https://github.com/mirror/busybox/blob/master/util-linux/uevent.c)
to filter USB events before requesting a scan. It does not use a periodic USB
scan, so a later policy write to `power/control` without a USB event will not
be corrected automatically. Check the actual adapter after unplug/replug and
confirm its `power/control` reports `on`.

Rollback means restoring the saved scripts and helper together and doing
another attended reboot. A reboot clears this launcher's wake lock.
There is no custom start/stop/status
interface or saved-settings database in the simplified scripts.

## Validation status

The earlier simplified scripts at `103bb35` passed ShellCheck, shell syntax
checks, and a temporary runit start/restart/stop/logging exercise. The current
revision adds the shared boot helper and root environment and moves charging
inhibition into the normal Android layout. The shell files passed
ShellCheck and syntax checks with BusyBox ash and host sh. Temporary host checks
covered an already-completed boot, delayed boot, the timeout, and the disabled
charging script. They used stubs for Android properties and sleep.

The restored Wi-Fi monitor passed temporary checks for link-up handling,
readback failures, restart, and its disable switch. USB checks covered existing
and newly attached devices, driver-bind/change events, VID:PID filtering,
missing control nodes, ignored events, and listener restart. These used host
fixtures. On Mona, the Magisk BusyBox `uevent` applet was confirmed and a passive
five-second listener opened without error; no events arrived during that sample.
Actual USB unplug/replug validation remains pending.

Phone installation and reboot checks remain pending. The earlier ADB-script
deployment on Mona is recorded in
[Mona validation](../devices/mona/validation.md).
