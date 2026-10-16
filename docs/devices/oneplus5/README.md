# OnePlus 5: cheeseburger

[All documentation](../../README.md)

Target: **OnePlus 5**, codename `cheeseburger`, Snapdragon 835/MSM8998,
LineageOS 22.2 and a 4.4 kernel. These boot/recovery commands are specific to this
phone; the OnePlus 5T (`dumpling`) and Mona have different device requirements.

**AI usage:** These guides were consolidated and revised with AI assistance.
See [sources](../../reference/sources.md#ai-usage) and [evidence and limits](#evidence-and-limits).

## Setup path

1. [Install LineageOS and Magisk](lineageos-root.md), or verify the existing setup.
2. Check USB serial enumeration; use [the custom kernel](kernel.md) if required.
3. Follow [shared Debian setup](../../setup/debian.md) and [boot-script installation](../../setup/boot-services.md).
4. [Add your own services](../../services/runit.md) and check long screen-off operation.

The kernel fork enables common serial, CAN, UVC, and storage drivers. It is
independent of the Debian filesystem: Debian packages cannot substitute for
missing kernel drivers. See [kernel maintenance](kernel-maintenance.md) when
changing the defconfig or toolchain.

## Evidence and limits

The earlier notes record successful LineageOS/root/chroot bring-up and an
initial kernel build. The source and build scripts were inspected for this
consolidation at `e1d4edd7e05dabd32a9b8458d3b3c570cd992ba9` on
`usb-serial-enable`. No OnePlus phone was connected and no new kernel build or
flash was performed here. Treat peripheral and reboot checks as steps to run,
not as new test results. [Sources](../../reference/sources.md).

The simplified service scripts require `/sys/power/wake_lock`; verify that
interface on the running OnePlus kernel before adopting the launcher. Mona's
fake-SOC and Motorola charging controls do not apply to this device.
