# Moto G Stylus 5G (2025): Mona

[All documentation](../../README.md)

Target: `mona`, Android 16, custom Linux 6.6.118. The observed phone was already
rooted and booting its USB-serial kernel. This documentation does not establish
a new-stock-device unlock/root procedure or compatibility with another firmware.

## Setup path

1. [Confirm ADB/root](../../android/adb.md) and record `ro.build.fingerprint`.
2. [Install Debian](../../setup/debian.md), then [the boot scripts](../../setup/boot-services.md).
3. [Add your own runit services](../../services/runit.md).
4. Use the kernel/power pages below for the batteryless modifications.

| Guide | Scope |
| --- | --- |
| [Kernel build](kernel.md) | Persistent config merging, toolchain/sysroot, base Image, and boot-image repacking. |
| [Manual fake SOC](fake-soc.md) | Debug-option tradeoffs, required charger-module rebuild, manual enable/restore. |
| [Battery-replacement supply](power.md) | XL4015 input/output requirements, original PCB, transients, and recovery. |
| [USB-C power protection](usb-power.md) | Hardware blocker, USB roles, optional one-shot charging policy, and reset limits. |
| [Hardware and printed cover](hardware.md) | Ranked module search terms, required specifications, GX12 wiring, and enclosure design. |
| [Performance](performance.md) | Observed frequency cap, stock governor comparison, cooling, and worker placement. |
| [Validation record](validation.md) | Dated observations, completed checks, and deployment work still pending. |

**Fake SOC is not deployed yet.** The persistent option was validated, but the
loaded `qti_battery_charger.ko` must be rebuilt and packaged with a matching
kernel/module set. An Image-only replacement cannot enable it. Keep fake SOC
inactive until explicitly set; no automatic boot override is supplied.

The hardware candidates and charging inhibition remain electrically unqualified.
See [sources](../../reference/sources.md) for the inspected kernel revision.
