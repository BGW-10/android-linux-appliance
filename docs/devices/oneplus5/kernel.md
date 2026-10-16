# OnePlus 5 kernel: build, package, test, recover

[OnePlus index](README.md) · [Maintenance](kernel-maintenance.md) · [Sources](../../reference/sources.md)

For `cheeseburger` on the matching LineageOS 22.2 firmware, already unlocked,
rooted, and booting normally. This fork adds CDC ACM; CH341, CP210x, FTDI,
PL2303 serial; CAN/gs_usb/SLCAN; UVC; UAS; and optional ACM gadget support.
If the required device node already works, a custom kernel is unnecessary for
that peripheral alone. No new build/flash was performed for this documentation.

## 1. Build on x86-64 Linux/WSL

Keep sources on the Linux filesystem. Install host dependencies:

```bash
sudo apt update
sudo apt install bc bison build-essential ca-certificates cpio curl file flex \
    git libelf-dev libncurses-dev libssl-dev make python3 rsync unzip wget zip
mkdir -p ~/phone-appliance
cd ~/phone-appliance
git clone -b appliance-docs git@github.com:BGW-10/android_kernel_oneplus_msm8998.git
cd android_kernel_oneplus_msm8998
export WORKSPACE="$PWD/../oneplus5-build"
mkdir -p "$WORKSPACE/toolchains" "$WORKSPACE/package" "$WORKSPACE/backups"
git rev-parse HEAD
cat toolchains.conf
./scripts/setup-toolchains.sh
```

The `appliance-docs` review branch is based on `usb-serial-enable`; its changes
centralize documentation. Use your existing checkout if already cloned.
The script supports `WORKSPACE`; without it, downloads default to
`~/op5-kernel/toolchains`. Keep this Bash session and `WORKSPACE` for the
remaining host steps.

### Check the actual toolchain revisions

At reviewed commit `e1d4edd7`, `toolchains.conf` records Clang `clang-r530567`,
two GCC hashes, and a build-tools hash. **The setup script clones GCC's
`lineage-19.1` branches and does not check out those GCC hashes.** For the
recorded revisions, explicitly fetch/check out each hash before building:

```bash
. ./toolchains.conf
git -C "$WORKSPACE/toolchains/gcc64" fetch origin "$AARCH64_GCC_HASH"
git -C "$WORKSPACE/toolchains/gcc64" checkout --detach "$AARCH64_GCC_HASH"
git -C "$WORKSPACE/toolchains/gcc32" fetch origin "$ARM_GCC_HASH"
git -C "$WORKSPACE/toolchains/gcc32" checkout --detach "$ARM_GCC_HASH"
git -C "$WORKSPACE/toolchains/gcc64" rev-parse HEAD
git -C "$WORKSPACE/toolchains/gcc32" rev-parse HEAD
"$WORKSPACE/toolchains/$LLVM_TAG/bin/clang" --version
```

If a fetch or checkout fails, resolve it before building. Changing a recorded
compiler revision requires new validation. These are documentation corrections;
the upstream setup script has not been changed here. The old kernel uses Clang
but still expects both Android GCC 4.9 cross-tool prefixes.

### Build and inspect the resolved config

```bash
./scripts/build.sh
file out/arch/arm64/boot/Image.gz-dtb
sha256sum out/arch/arm64/boot/Image.gz-dtb
grep -E '^CONFIG_(USB_ACM|USB_SERIAL|USB_SERIAL_CH341|USB_SERIAL_CP210X|USB_SERIAL_FTDI_SIO|USB_SERIAL_PL2303|CAN_GS_USB|MEDIA_USB_SUPPORT|VIDEO_DEV|VIDEO_V4L2|USB_VIDEO_CLASS|USB_UAS)=' out/.config
```

The script regenerates `lineage_oneplus5_defconfig`, checks required resolved
options, then builds. Its artifact is **a kernel payload**, not a complete
Android `boot.img`; do not flash it directly. For a separate clean output tree:
`OUT="$WORKSPACE/out-clean" ./scripts/build.sh` (adjust later artifact paths).

## 2. Back up the installed boot image

Confirm `adb shell getprop ro.product.device` reports `cheeseburger` and record
the firmware fingerprint. Keep matching recovery/ROM files and an off-phone
boot backup before any flash. Open `adb shell`, then `su`.

**Android root shell:**

```sh
id
ls -l /dev/block/bootdevice/by-name/boot
dd if=/dev/block/bootdevice/by-name/boot of=/sdcard/Download/op5-boot-known-good.img bs=4M
```

**Host**, back in the same Bash session:

```bash
backup_dir="$WORKSPACE/backups/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$backup_dir"
adb pull /sdcard/Download/op5-boot-known-good.img "$backup_dir/boot-known-good.img"
adb shell getprop ro.build.fingerprint > "$backup_dir/fingerprint.txt"
sha256sum "$backup_dir/boot-known-good.img"
adb push out/arch/arm64/boot/Image.gz-dtb /sdcard/Download/Image.gz-dtb
```

The backup is the currently installed image, including its Magisk ramdisk if
already rooted. Use a fresh backup after a ROM update; a different build's
ramdisk is not an interchangeable template.

## 3. Repack on the phone

Open `adb shell`, then `su`. All commands in this block run in **Android root**,
not Debian:

```sh
set -e
work=$(mktemp -d /data/local/tmp/op5-boot.XXXXXX)
cd "$work"
cp /sdcard/Download/op5-boot-known-good.img original-boot.img
cp /data/adb/magisk/magiskboot ./magiskboot
chmod 755 ./magiskboot
./magiskboot unpack original-boot.img
test -s kernel
cp /sdcard/Download/Image.gz-dtb kernel
unset PATCHVBMETAFLAG
./magiskboot repack original-boot.img custom-boot.img
test -s custom-boot.img
mkdir verify
(cd verify && ../magiskboot unpack ../custom-boot.img)
ls -lh custom-boot.img verify/
cp custom-boot.img /sdcard/Download/op5-custom-boot.img
chmod 644 /sdcard/Download/op5-custom-boot.img
```

If `magiskboot` is elsewhere, locate the installed binary before proceeding.
Repacking from the current rooted image retains its other boot components;
inspect the unpack/repack output and resulting ramdisk/DT components. A successful
unpack is a structural check, not proof of boot compatibility. Leave Magisk's
compression handling at its defaults. [magiskboot behavior](https://topjohnwu.github.io/Magisk/tools.html).

**Host:**

```bash
adb pull /sdcard/Download/op5-custom-boot.img "$WORKSPACE/package/op5-custom-boot.img"
sha256sum "$WORKSPACE/package/op5-custom-boot.img"
```

## 4. Flash only when ready to test

This step changes the phone's boot partition. Keep the off-phone known-good
image and confirm you can enter fastboot. **Host:**

```bash
adb reboot bootloader
fastboot devices
fastboot flash boot "$WORKSPACE/package/op5-custom-boot.img"
fastboot reboot
```

This is the OnePlus 5's `boot` flow; do not reuse it for Mona's slot/module setup.
If Android fails to boot, enter fastboot with the phone's hardware keys and
restore the exact known-good image:

```bash
fastboot flash boot "$backup_dir/boot-known-good.img"
fastboot reboot
```

If using another terminal, replace variables with the recorded full paths.
Restoring only `boot` does not deliberately erase `/data`, but retain user-data
backups as well.

## 5. Verify the running kernel and peripheral

**Host:** `adb wait-for-device`, `adb shell uname -a`, then `adb shell` and `su`.

**Android root shell**, with the adapter connected through OTG:

```sh
zcat /proc/config.gz | grep -E 'CONFIG_USB_ACM=|CONFIG_USB_SERIAL_CP210X=|CONFIG_USB_VIDEO_CLASS=|CONFIG_CAN_GS_USB=|CONFIG_USB_UAS='
lsusb
dmesg | tail -100
ls -l /dev/ttyUSB* /dev/ttyACM* /dev/video* 2>/dev/null
```

Inspect `/proc/config.gz` only if exposed by the running kernel. Enumeration in
`lsusb` does not prove a matching driver bound. Identify the VID:PID, actual
device node, and permissions before [adding a service](../../services/runit.md).
Test reconnects and screen-off operation, then retain the boot backup.

## Build troubleshooting

| Symptom | Check |
| --- | --- |
| UVC option disappears | Inspect media/V4L2 parent settings in the resolved `.config`; see maintenance. |
| `aarch64-linux-android-gcc: not found` | Verify both GCC compiler paths under `WORKSPACE/toolchains`; retain the exact cross-prefixes used by `build.sh`. |
| `openssl/bio.h` missing | Install host `libssl-dev`. |
| Stack-protector warning with a missing compiler | Fix toolchain discovery first; keep the security option. |
| Immediate second build | Incremental output is expected; use a distinct `OUT` for a clean validation. |
