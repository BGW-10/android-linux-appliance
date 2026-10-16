# From rooted phone to appliance

[Documentation index](README.md)

The end state is Android managing the phone hardware, with Debian running SSH
and your chosen services under runit. Follow the stages in order; skip completed
stages after checking their verification steps.

## 1. Choose the device procedure

- [Mona](devices/mona/README.md): the documented phone already runs rooted
  Android 16 and the USB-serial kernel. Its fake-SOC/module update is pending.
- [OnePlus 5](devices/oneplus5/README.md): install the matching LineageOS/root
  setup, then build the custom kernel only if the required peripherals need it.

Confirm the codename and firmware before using a kernel or partition command.
Unlocking a bootloader wipes user data. Keep the matching recovery/boot files.

## 2. Establish recovery access

Use [ADB](android/adb.md) over USB, authorize the host, enter `adb shell`, then
`su`, and confirm `id` reports root. Keep this route available while configuring
SSH and boot scripts. Do not rely on a future network service to recover itself.

## 3. Install Debian and SSH

Follow [Debian setup](setup/debian.md). Stop when root can write files under
`/root`, use the network, and log in with an SSH key. A chroot shares Android's
kernel; installing Debian does not add a missing USB serial driver.

## 4. Install the boot scripts

Follow [boot-script installation](setup/boot-services.md). Reboot while attended,
then verify TCP ADB, SSH, runit, and the named wake lock with the screen off.
If the rootfs requires first unlock, document that behavior before unattended use.

## 5. Add your services

Install the application you want, then follow [the runit guide](services/runit.md)
to add its foreground command and logging. For printer services, work while
idle with heaters off. Confirm serial communication and the actual printer
configuration before motion or heating; this repository's Ender configuration
is device-specific.

## 6. Qualify continuous operation

On Mona, work through [batteryless power](devices/mona/power.md),
[USB protection](devices/mona/usb-power.md), and [validation](devices/mona/validation.md).
Fake SOC stays manual. On both devices, test screen-off idle, network/USB
reconnection, log growth, and recovery during a maintenance window. Preserve
Android thermal protection and the printer MCU's shutdown/watchdog behavior.
