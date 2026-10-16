# Android Appliance Userspace

Android boot scripts and a Debian overlay for a rooted phone running Klipper
and related appliance services. The current targets are a Moto G Stylus 5G
(2025), `mona`, on Android 16 and a OnePlus 5 on LineageOS.

Start with the [Mona deployment guide](docs/mona-appliance.md). The
[documentation index](docs/README.md) also links the existing rooting, chroot,
kernel, and Android build guides. Printer configuration lives under
[`klipper/ender3-v3-ke/`](klipper/ender3-v3-ke/).

## Startup and ownership

```text
Android init + Magisk late_start
├── enable-tcp-adb.sh      authenticated TCP 5555, bounded readiness check
├── appliance-tuning.sh    Doze/Battery Saver, selected USB devices, Wi-Fi
├── charging-inhibit.sh   optional Motorola vote; disabled by default
└── start-debian.sh        bounded mount attempts, one launch
    └── Debian start-services
        ├── owns klipper-appliance kernel wake lock
        └── runsvdir /etc/service
            └── runsv → foreground service + optional svlogd
```

Android owns hardware, thermal management, charging safety, SELinux, CPU
scaling, and networking. Runit supervises Debian services without replacing
Android's PID 1. The scripts preserve the stock CPU governor and thermal
policy. Fake SOC is a separate manual kernel operation.

## Files and defaults

The `android/` and `debian/` trees mirror their installation paths.

| Path under its tree | Purpose |
| --- | --- |
| `android/data/adb/appliance/config.sh` | Root-owned settings; preserved by the installer on upgrades. |
| `android/data/adb/appliance/common.sh` | Boot readiness, process locks, bounded logging. |
| `android/data/adb/service.d/enable-tcp-adb.sh` | Enables authenticated ADB on TCP 5555 at each boot. |
| `android/data/adb/service.d/appliance-tuning.sh` | Saves original settings, applies tuning, handles USB/Wi-Fi changes. |
| `android/data/adb/service.d/start-debian.sh` | Mounts `debian-trixie`, then invokes its supervisor. |
| `android/data/adb/service.d/charging-inhibit.sh` | Opt-in Mona charging inhibition after hardware qualification. |
| `debian/etc/default/appliance-services` | Service directory, wake-lock name, shutdown timeout. |
| `debian/usr/local/bin/start-services` | `start`, `status`, and `stop`, with duplicate-start protection. |
| `debian/etc/sv/sshd/` | Foreground SSH daemon and rotated logging. |

ADB, Debian startup, and tuning are enabled in the supplied configuration.
Charging inhibition is disabled. Existing USB serial/CP210x support comes
from the kernel; these scripts do not install or modify kernel modules.

The Android profile disables Doze and Battery Saver, and sets USB
`power/control=on` only for configured VID:PID pairs. It does not globally
change USB autosuspend. It checks those devices and Wi-Fi power saving every
30 seconds. Original values are saved for rollback; a setting already disabled
before installation is restored to that disabled state.

## Installation

Prerequisites: Magisk, a working `chroot-distro` installation, a Debian chroot,
and an authorized ADB host. In Debian, install `runit`, `openssh-server`, and
`util-linux` (provides `flock`). Keep SSH keys and private configuration out of
this repository.

Copy an extracted checkout to the phone, for example under
`/data/local/tmp/klipper-android-appliance-scripts`. In an **Android root shell**:

```sh
# Only persistent ADB startup:
sh /data/local/tmp/klipper-android-appliance-scripts/tools/install-android.sh --adb-only

# Or all Android startup files, after reviewing the deployment guide:
sh /data/local/tmp/klipper-android-appliance-scripts/tools/install-android.sh --all
```

Both modes back up replaced files under `/data/adb/appliance/backups/`, retain
an existing `config.sh`, and leave service startup to the operator or next boot.
Use the repository's [Debian installer](tools/install-debian.sh) **inside the
chroot**, with the checkout accessible there:

```sh
sh /path/to/checkout/tools/install-debian.sh
```

Choose exactly one SSH service definition. Debian's package may already enable
`/etc/service/ssh`; this repository supplies `sshd`. The installer does not
change those links. See [migration](docs/mona-appliance.md#debian-migration).
Do not restart a printer host during a print.

The service.d layout follows [Magisk's late_start boot-script support](https://topjohnwu.github.io/Magisk/guides.html#boot-scripts).
Invoke Android scripts manually through the same shell Magisk uses:

```sh
ASH_STANDALONE=1 /data/adb/magisk/busybox sh /data/adb/service.d/enable-tcp-adb.sh
```

## Operation

From an authorized workstation:

```sh
adb connect PHONE_IP:5555
adb shell
su
```

The script keeps ADB key authentication enabled and leaves `adbd` privilege
dropping intact; use `su` for root. TCP 5555 should be reachable only on a
trusted management network. It is the legacy TCP transport, not Android's
paired TLS wireless-debugging mode. Reserve the phone's DHCP address.

Inside Debian:

```sh
/usr/local/bin/start-services status
sv status /etc/service/*
# When the printer is idle and heaters are off:
/usr/local/bin/start-services stop
# Start again in the foreground, or use Android's start-debian.sh launcher:
/usr/local/bin/start-services start
```

Individual services remain managed by `sv up`, `sv down`, and `sv restart`.
Service `run` scripts must `exec` a foreground program. Use `chpst -u klipper`
for a dedicated unprivileged Klipper account when adding its service; retain
printer MCU shutdown/watchdog behavior. No new printer service or motion/heater
configuration is installed by this change.

Android logs live at `/data/adb/appliance/log/`: each script retains its current
log (about 64 KiB) plus one rotated file. SSH logs live at
`/var/log/appliance/sshd/`, with roughly 1 MiB per file and five rotated files.
Review backups and free space periodically; deployment backups are not deleted
automatically.

## Validation

```sh
python3 -m unittest discover -s tests -v
```

The tests mock Android properties and sysfs in temporary directories. Debian
integration tests run real `runsvdir`, `runsv`, and `sv` when available in `PATH`;
otherwise they report a skip. They cover ADB failures/idempotence, mount failure,
settings restoration, charging guards, log rotation, wake-lock ownership,
duplicate starts, supervisor death, and failed shutdown.

See [Mona validation and rollback](docs/mona-appliance.md) for the remaining
phone reboot, screen-off, USB, and electrical checks. Passing host tests does
not establish safe unattended batteryless operation.
