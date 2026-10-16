# Android appliance scripts

Small shell scripts and a Debian overlay for a rooted Android phone running
SSH, Klipper, Moonraker, and related services. The current phone is a Moto G
Stylus 5G (2025), `mona`, with Magisk and a `debian-trixie` chroot.

## Start here

- [Install or update the scripts](docs/mona-appliance.md)
- [Add and manage runit services](docs/runit.md)
- [All documentation](docs/README.md)
- [Batteryless power and printed-cover hardware](https://github.com/BGW-10/moto-g-stylus-2025-kernel/blob/mona-appliance/docs/mona/hardware.md)

## How it works

```text
Magisk service.d
├── enable-tcp-adb.sh     enable authenticated ADB on TCP 5555
├── appliance-tuning.sh   disable Doze/Battery Saver; keep selected USB/Wi-Fi awake
└── start-debian.sh       mount Debian and run start-services
    └── runsvdir /etc/service
        └── one runsv per enabled service: sshd, klipper, moonraker, ...
```

Edit settings at the top of the relevant script. Each Android script stands
alone. Adding a Debian service requires no change to the Android boot scripts.
The Debian launcher takes a kernel wake lock so screen-off does not suspend
the appliance; it stays held until reboot or a deliberate manual release.

| Directory | What belongs here |
| --- | --- |
| `android/` | Files copied to the matching Android paths. |
| `debian/` | Files copied to the matching paths inside Debian. |
| `examples/runit/` | Klipper and Moonraker service examples; edit before enabling. |
| `examples/android/` | Optional charging-inhibit experiment, disabled by default. |
| `klipper/ender3-v3-ke/` | Existing printer configuration. |

## Adding a service

Create an executable `/etc/sv/my-service/run` that ends with
`exec /path/to/program --foreground`. Enable it with:

```sh
ln -s /etc/sv/my-service /etc/service/my-service
```

Runit discovers it automatically and restarts it if it exits. The
[service guide](docs/runit.md) includes a complete example, logging, disabling
services, and the Klipper/Moonraker setup.

## Everyday commands

Inside Debian, as root:

```sh
sv status /etc/service/*
sv up /etc/service/klipper
sv -w 20 down /etc/service/klipper
sv -w 20 restart /etc/service/moonraker
```

Use stop/restart commands only when the printer is idle and heaters are off.
Android keeps its CPU, thermal, charging, and SELinux policies. Fake SOC remains
manual. Persistent ADB keeps host-key authentication and belongs on a trusted
management network.
