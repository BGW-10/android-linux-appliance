# Appliance documentation

[Repository home](../README.md)

Start with [the setup sequence](getting-started.md). Each procedure names the
shell it uses: build host, Android root shell, or Debian root. Debian services
and SSH use `root`, with application files under `/root`.
Use the page for your exact device when handling ROMs, kernels, or partitions.

**AI usage:** These guides were created, consolidated, or revised with AI
assistance. See [sources and validation](reference/sources.md#ai-usage).

## Devices

| Device | Start here | Device-specific work |
| --- | --- | --- |
| Moto G Stylus 5G (2025), `mona` | [Mona](devices/mona/README.md) | Android 16 kernel, manual fake SOC, XL4015 power, USB-C protection, GX12/printed cover, cooling. |
| OnePlus 5, `cheeseburger` | [OnePlus 5](devices/oneplus5/README.md) | LineageOS 22.2/root, MSM8998 kernel, USB serial/CAN/webcam support, recovery. |

## Shared setup and operation

| Guide | Use it for |
| --- | --- |
| [How the system fits together](architecture.md) | Android versus Debian responsibilities, mounts, networking, and runit. |
| [Debian installation](setup/debian.md) | Termux/chroot-distro, ARM64 rootfs, Android groups, SSH keys, PAM/fscrypt troubleshooting. |
| [Boot scripts](setup/boot-services.md) | Install/update scripts and the shared helper, persistent ADB, verification, and rollback. |
| [Runit services](services/runit.md) | Add a service, enable/disable it, inspect logs, and manage the wake lock. |
| [ADB and network access](android/adb.md) | USB/root shells, TCP 5555, address changes, and recovery. |
| [Build/install Android iw](android/iw.md) | NDK build and the existing Magisk binary overlay. |
| [Android package trimming](android/debloat.md) | Reversible package changes and the historical OnePlus package list. |
| [Sources and revisions](reference/sources.md) | Imported documentation, source snapshots, validation scope, and old page locations. |

Kernel instructions run in the corresponding **kernel checkout**. The scripts
and service definitions live in this repository. Hardware proposals and old
observations are labeled separately from steps already validated on a phone.
