# OnePlus 5: LineageOS and Magisk

[OnePlus index](README.md) · [Next: Debian](../../setup/debian.md)

The existing setup used OxygenOS 10.0.1 firmware, LineageOS 22.2, and Magisk.
The official [device metadata](https://github.com/LineageOS/lineage_wiki/blob/main/_data/devices/cheeseburger.yml)
currently identifies the Android 10 firmware requirement and 22.2 branch.
Consult the [LineageOS install guide](https://wiki.lineageos.org/devices/cheeseburger/install/)
for the release you actually download. Keep its ZIP, recovery, and checksums.

## 1. Prepare the host and unlock

Install Google's [Platform Tools](https://developer.android.com/tools/releases/platform-tools).
In Windows PowerShell, run `adb`/`fastboot` from PATH or use `./adb.exe` and
`./fastboot.exe` in the extracted directory. Enable developer options, OEM
unlocking, and USB debugging; authorize your computer on the phone.

**Host:**

```powershell
adb devices -l
adb shell getprop ro.product.device
```

Confirm `cheeseburger` before proceeding. Unlock confirmation wipes user data;
back it up first. Then:

```powershell
adb reboot bootloader
fastboot devices
fastboot oem unlock
```

Finish initial setup and re-enable USB debugging
after the reset.

## 2. Install the matching LineageOS release

Place the matching recovery image and signed installation ZIP on the host.
The following filenames are local names for those exact downloaded artifacts.

**Host:**

```powershell
adb reboot bootloader
fastboot flash recovery recovery.img
```

Boot directly into Lineage Recovery using the bootloader menu. Choose
**Factory Reset → Format data**, then **Apply update → Apply from ADB**.

```powershell
adb sideload lineage-22.2-YOUR_BUILD-cheeseburger-signed.zip
```

Use the actual filename. Finish the release-specific installation steps, boot
LineageOS, and confirm basic hardware operation before modifying the kernel.

## 3. Patch the matching boot image with Magisk

Extract `boot.img` from the **same installed LineageOS ZIP**. Install the official
[Magisk APK](https://github.com/topjohnwu/Magisk/releases) on this phone, then:

**Host:**

```powershell
adb push boot.img /sdcard/Download/boot.img
```

In Magisk, choose **Install → Select and Patch a File** and select that image.
List the result and pull the exact filename; do not rely on a wildcard in
`adb pull`:

```powershell
adb shell ls /sdcard/Download/
adb pull /sdcard/Download/magisk_patched-ACTUAL_NAME.img magisk-patched-boot.img
adb reboot bootloader
fastboot flash boot magisk-patched-boot.img
fastboot reboot
```

Authorize root, then verify in an **Android shell**:

```sh
su
id
```

Expect `uid=0(root)`. Patch on the intended device and preserve the original
image, following [Magisk's installation instructions](https://topjohnwu.github.io/Magisk/install.html).
Do not relock the bootloader with custom images installed.

## 4. Continue

For missing USB-serial drivers, use [the kernel guide](kernel.md). For userspace,
continue with [Debian setup](../../setup/debian.md). The current startup path is
runit; the old standalone `sshd` boot command has been retired.
