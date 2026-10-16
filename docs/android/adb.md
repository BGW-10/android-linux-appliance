# ADB, root shells, and network access

[Documentation index](../README.md) · [Boot-script installation](../setup/boot-services.md)

## USB first

Install official [Android Platform Tools](https://developer.android.com/tools/releases/platform-tools),
enable USB debugging, and accept the host-key prompt. **Host commands**:

```sh
adb devices -l
adb shell
```

Then, in the **Android shell**:

```sh
su
id
getprop ro.product.device
getprop ro.build.fingerprint
```

Magisk authorization should produce `uid=0(root)`. This is Android, not Debian;
enter Debian with `chroot-distro login debian-trixie` when needed. If multiple
phones are connected, add `-s SERIAL` to host ADB commands.

## Persistent TCP 5555

Install [enable-tcp-adb.sh](../../android/data/adb/service.d/enable-tcp-adb.sh)
and [common.sh](../../android/data/adb/appliance/common.sh) using the
[ADB-only copy option](../setup/boot-services.md#2-install-the-android-boot-scripts).
After an attended reboot, from the **host**:

```sh
adb connect PHONE_IP:5555
adb -s PHONE_IP:5555 shell
```

Use `su` inside that shell. The script retains ADB host-key authentication and
requests TCP 5555 once Android finishes booting. Reserve the phone's DHCP
address, and check Ethernet/Wi-Fi addresses separately. Legacy TCP ADB is not
Android's TLS-paired wireless-debugging mode; restrict access to a trusted
management network. [ADB transport documentation](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/docs/dev/adb_wifi.md).

## Recovery and disabling

If TCP fails, return to USB, inspect
`/data/local/tmp/enable-tcp-adb.log`, and read `service.adb.tcp.port`,
`service.adb.listen_addrs`, and `ro.adb.secure` with `getprop`. Magisk and Android
must reach the script before it can help; it does not run in the bootloader.

To stop enabling TCP on future boots, remove executable permission from its
service.d file. To close the current TCP listener, run `adb usb` through an
authorized USB connection. Keep SSH for ordinary Debian administration.
