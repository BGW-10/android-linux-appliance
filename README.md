# Android appliance scripts and documentation

A small Android/Debian setup for using rooted phones as Klipper hosts. Runtime
scripts stay short and readable; this repository also collects the device,
kernel, installation, and operation guides in one place.

Android boot scripts and Debian services run as **root**, with `/root` as the
Debian home directory.

**AI usage:** Parts of the scripts and documentation were created or revised
with AI assistance, including OpenAI Codex and ChatGPT. See
[sources and validation](docs/reference/sources.md#ai-usage) for scope and checks.

## Start here

- [Setup sequence](docs/getting-started.md) — from a rooted phone to running services.
- [Documentation index](docs/README.md) — browse by device or task.
- [Moto G Stylus 2025 / Mona](docs/devices/mona/README.md).
- [OnePlus 5 / cheeseburger](docs/devices/oneplus5/README.md).
- [Add a runit service](docs/services/runit.md).

The `mona-appliance` branch is for review and testing before merging into `main`.
Device observations, host checks, and pending deployment work are identified in
the guides. See [sources and revisions](docs/reference/sources.md).

## Runtime layout

```text
Magisk service.d
├── enable-tcp-adb.sh     authenticated TCP 5555
├── appliance-tuning.sh   Doze/Battery Saver and selected USB/Wi-Fi settings
├── charging-inhibit.sh   Mona charging request; disabled by default
└── start-debian.sh       mount Debian and launch runit
    └── runsvdir /etc/service
        └── one runsv per enabled foreground service
```

| Directory | Contents |
| --- | --- |
| `android/data/adb/service.d/` | Android boot scripts, including optional charging inhibition. |
| `android/data/adb/appliance/common.sh` | Shared Android boot-wait helper; install before the scripts. |
| `android/data/adb/modules/` | Existing Magisk binary overlay. |
| `debian/` | Chroot launcher and SSH runit service; add your own services here. |
| `klipper/ender3-v3-ke/` | Existing printer-specific configuration; review paths and hardware before use. |
| `docs/` | Shared setup, Android tools, services, and device-specific instructions. |

Settings live at the top of each script. Add Debian services by creating an
executable `/etc/sv/NAME/run` and linking it into `/etc/service`; no Android
startup edit is needed. Use `sv status`, `sv up`, `sv down`, and `sv restart`.
Stop/restart printer services only while idle with heaters off.

The runit definitions are installed under `/etc/sv`; only links in
`/etc/service` enable them. Install and verify each application before linking it.

Android retains CPU, thermal, charging, and SELinux policy. The launcher holds
`klipper-appliance` until reboot or explicit release to prevent suspend.
Fake SOC remains manual; electrical protection and firmware recovery are
separate from the reported battery percentage.
