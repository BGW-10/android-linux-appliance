# Mona kernel, modules, and manual fake SOC

[Mona index](README.md) · [Sources](../../reference/sources.md)

This covers building the base `Image`, boot-image repacking, flashing and
recovery, rebuilding an individual compatible in-tree module (such as
`qti_battery_charger.ko`), and configuring/verifying
[manual fake SOC](#9-manual-fake-soc). **It does not build or package Motorola's
complete out-of-tree `vendor_dlkm` module distribution.** The source repo lacks
the complete Motorola Bazel/vendor workspace.

Run host commands in **Bash on x86-64 Linux/WSL**, with sources on the Linux
filesystem. Clone the review branch beside your appliance checkout if needed:

```bash
mkdir -p ~/phone-appliance
cd ~/phone-appliance
git clone -b mona-appliance git@github.com:BGW-10/moto-g-stylus-2025-kernel.git
cd moto-g-stylus-2025-kernel
```

Use the existing checkout if already cloned. Commands below that refer to
kernel source run in this kernel repository, not the appliance repository.

## 1. Record what is checked out

From the Mona kernel repository:

```bash
# inspect the checkout; these commands do not change it.
git status --short --branch
git log -1 --format='%H%n%s'
git describe --tags --always
head -n 5 Makefile
```

The reviewed source is `533a0b4f7464` on `mona-appliance`, based on
`mona-android16` and Linux 6.6.118. Record your own checkout revision. Match the
phone's full firmware release; `android15-6.6` in `build.config.common` names
the common kernel branch, not the phone's Android version.

This checkout has the Mona config but lacks the vendor DT tree and full Bazel
workspace required for Motorola's distribution target. Section 3 builds only
`Image` and does not compile DTBs or external modules.

## 2. Get the matching GKI build environment

Use a **64-bit x86 Linux host**. The `android15-6.6-2026-01` kernel manifest
downloads the Clang toolchain and build tools used below. It requires network
access and several gigabytes of disk space.

On Debian/Ubuntu, install the host programs and headers first:

```bash
# install host packages.
sudo apt update
sudo apt install git repo build-essential bc bison flex libelf-dev libssl-dev \
  libncurses-dev dwarves python3 curl ca-certificates rsync cpio lz4 zstd file unzip adb fastboot
# confirm Repo is available.
repo version
```

`dwarves` supplies `pahole` for BTF. If `repo` is unavailable through your
package manager, use the [official Repo installation instructions](https://source.android.com/docs/setup/start/requirements#install-repo).

Create a separate AOSP kernel checkout beside this repository:

```bash
# create and populate the separate GKI environment checkout.
cd "$HOME/phone-appliance"
mkdir -p android-kernel-env
cd android-kernel-env
repo init -u https://android.googlesource.com/kernel/manifest \
  -b common-android15-6.6-2026-01
repo sync -c -j4
```

Adjust the paths if your workspace is elsewhere. After `repo sync`, check the
required tools:

```bash
# confirm required projects, headers, and compiler are present.
test -f build/kernel/build-tools/sysroot/usr/include/string.h
test -d prebuilts/kernel-build-tools/linux-x86/lib64
test -x prebuilts/clang/host/linux-x86/clang-r510928/bin/clang
prebuilts/clang/host/linux-x86/clang-r510928/bin/clang --version
# write the fetched project revisions to resolved-manifest.xml.
repo manifest -r -o resolved-manifest.xml
```

`resolved-manifest.xml` records the fetched revisions. If the compiler check
fails, inspect `prebuilts/clang/host/linux-x86/` before continuing.

## 3. Build the Parrot/Mona base `Image` with extra driver flags

Motorola's `perf` config order is `gki_defconfig`, `vendor/parrot_perf.config`,
then a fragment containing `moto-parrot.config`, `moto-parrot-mona.config`,
and `moto-parrot-perf.config`. Motorola's published Parrot recipe concatenates
the three Motorola files before invoking Bazel. The commands below use that
order and resolve it with `olddefconfig`. Bazel may apply further build
settings, so this does not establish an identical final `.config`. If you
later obtain a complete Mona Bazel workspace, compare its `.config` with
`$KERNEL_OUT/.config`.

Edit `arch/arm64/configs/vendor/ext_config/moto-parrot-mona.config` in this
repository. Keep its existing settings and add built-in drivers as
`CONFIG_SYMBOL=y`, one per line. Drivers set to `=m` require separate module
builds and deployment. Review the edit with
`git diff -- arch/arm64/configs/vendor/ext_config/moto-parrot-mona.config`.

`CONFIG_VIDEO_V4L2` does not exist in this tree. Use `CONFIG_VIDEO_DEV=y` for
the V4L2 core and `CONFIG_USB_VIDEO_CLASS=y` for USB webcams.

From `android-kernel-env`, run:

```bash
# define source, output, and toolchain paths for this shell.
set -euo pipefail
KERNEL_SRC="$PWD/../moto-g-stylus-2025-kernel"
KERNEL_OUT="$PWD/out/mona-parrot-image"
CLANG_BIN="$PWD/prebuilts/clang/host/linux-x86/clang-r510928/bin"
HOST_SYSROOT="$PWD/build/kernel/build-tools/sysroot"
HOST_TOOLS="$PWD/prebuilts/kernel-build-tools/linux-x86"
HOST_CFLAGS="--sysroot=$HOST_SYSROOT -I$HOST_TOOLS/include"
HOST_LDFLAGS="--sysroot=$HOST_SYSROOT -L$HOST_TOOLS/lib64 -fuse-ld=lld --rtlib=compiler-rt"
MOTO_CONFIG_DIR="$KERNEL_SRC/arch/arm64/configs/vendor/ext_config"
MONA_CONFIG="$MOTO_CONFIG_DIR/moto-parrot-mona.config"
MOTO_FRAGMENT="$KERNEL_OUT/moto_fragment.config"
# fail early if required source and toolchain files are missing.
test -f "$KERNEL_SRC/arch/arm64/configs/gki_defconfig"
test -x "$CLANG_BIN/clang"
test -f "$HOST_SYSROOT/usr/include/string.h"
test -s "$MONA_CONFIG"
# select host tools.
export PATH="$CLANG_BIN:$PWD/build/kernel/build-tools/path/linux-x86:$PATH"
export LD_LIBRARY_PATH="$HOST_TOOLS/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
# confirm selected host tools resolve in PATH.
command -v clang
command -v ld.lld
command -v pahole
# create build directories and point temporary files there.
mkdir -p "$KERNEL_OUT"
mkdir -p "$KERNEL_OUT/tmp"
export TMPDIR="$KERNEL_OUT/tmp" TEMP="$KERNEL_OUT/tmp" TMP="$KERNEL_OUT/tmp"
# merge the Parrot/Mona fragments and write the final .config.
for fragment in \
  "$MOTO_CONFIG_DIR/moto-parrot.config" \
  "$MONA_CONFIG" \
  "$MOTO_CONFIG_DIR/moto-parrot-perf.config"; do
  cat "$fragment"
  printf '\n'
done > "$MOTO_FRAGMENT"
KCONFIG_CONFIG="$KERNEL_OUT/.config" \
  "$KERNEL_SRC/scripts/kconfig/merge_config.sh" -m -r -y \
  "$KERNEL_SRC/arch/arm64/configs/gki_defconfig" \
  "$KERNEL_SRC/arch/arm64/configs/vendor/parrot_perf.config" \
  "$MOTO_FRAGMENT"
make -C "$KERNEL_SRC" O="$KERNEL_OUT" ARCH=arm64 LLVM=1 \
  HOSTCFLAGS="$HOST_CFLAGS" HOSTLDFLAGS="$HOST_LDFLAGS" olddefconfig
# verify that required Mona settings survived configuration.
grep -qx 'CONFIG_ARCH_PARROT=y' "$KERNEL_OUT/.config"
grep -qx 'CONFIG_MMI_DEVICE_DTBS=y' "$KERNEL_OUT/.config"
grep -qx 'CONFIG_MONA_DTB=y' "$KERNEL_OUT/.config"
grep -qx 'CONFIG_SCSI_SKHID=y' "$KERNEL_OUT/.config"
while IFS= read -r setting; do
  grep -Fqx "$setting" "$KERNEL_OUT/.config" || {
    echo "Mona setting did not survive olddefconfig: $setting" >&2
    exit 1
  }
done < <(grep -E '^CONFIG_[A-Za-z0-9_]+=' "$MONA_CONFIG")
# compile the kernel and write arch/arm64/boot/Image under KERNEL_OUT.
make -C "$KERNEL_SRC" O="$KERNEL_OUT" ARCH=arm64 LLVM=1 \
  HOSTCFLAGS="$HOST_CFLAGS" HOSTLDFLAGS="$HOST_LDFLAGS" -j4 Image
# identify the resulting file.
file "$KERNEL_OUT/arch/arm64/boot/Image"
```

The artifact is `$KERNEL_OUT/arch/arm64/boot/Image`. The verification loop
checks that each `CONFIG_...=` assignment in the Mona fragment survived
`olddefconfig`; inspect `.config` separately for any `# CONFIG_... is not set`
lines you edited. The separator `printf` preserves fragment boundaries even
when a source fragment lacks a final newline.

If the build fails, save the **first** error. Check disk space and confirm
both `make` commands received the same toolchain flags. Rerun the failing
target with `-j1 V=1` for detailed output. The host sysroot flags avoid a
`libbpf.c` compile error caused by newer host glibc headers; keep them in
both `make` commands.

## 4. Match the phone and firmware

With USB debugging enabled, record:

```bash
# read phone identity, firmware, kernel, and active slot.
adb devices
adb shell getprop ro.product.device
adb shell getprop ro.product.model
adb shell getprop ro.build.version.release
adb shell getprop ro.build.fingerprint
adb shell getprop ro.build.version.incremental
adb shell uname -a
adb shell getprop ro.boot.slot_suffix
```

Confirm the device is Mona and match its full firmware build to the source
release and stock boot image. Android and kernel version numbers alone are
insufficient; carrier and monthly releases may differ.

Motorola typically names source tags `MMI-<build ID>`. Query the exact build:

```bash
# query the phone's build ID and remote tag list; no files are changed.
BUILD_ID="$(adb shell getprop ro.build.id | tr -d '\r')"
git ls-remote --tags https://github.com/MotorolaMobilityLLC/kernel-msm.git \
  "refs/tags/MMI-${BUILD_ID}"
```

If no tag is returned, do not assume a similar tag matches. Check the
[Motorola build instructions](https://github.com/MotorolaMobilityLLC/readme)
for that release as well.

## 5. Where Motorola's separate build tasks fit

[Motorola's Parrot recipe](https://github.com/MotorolaMobilityLLC/readme/blob/master/W1VT36H.22-20.txt)
uses `portov` as its example product and builds the kernel distribution,
device trees, Qualcomm modules, and Motorola modules in separate tasks. The
`make ... Image` path above selects Mona and performs only the base kernel
build. It uses the listed config fragments without requiring the vendor DT
tree or Bazel product files absent from the kernel checkout.

Use vendor and Motorola modules from the **same stock firmware** as the boot
image. Kernel interface changes can break those modules even when `Image`
builds. A driver needing a new module, DTB/DTBO property, or firmware file
requires deployment beyond an `Image` replacement.

## 6. Replace only the kernel payload in a copy of the phone's boot image

Use the `Image` from section 3 only after matching the phone's firmware and
checking that the drivers need no other files. Repacking preserves the other
extracted boot components but changes image metadata and invalidates the OEM
AVB signature.

### Get `magiskboot` on the Linux host

Download an official [Magisk APK](https://github.com/topjohnwu/Magisk/releases)
to the Linux host and set `MAGISK_APK` below to its path. Run all section 6
blocks in the same shell:

```bash
# create a host work directory and extract magiskboot from the APK.
set -euo pipefail
cd "$HOME/phone-appliance"
BOOT_WORK="$(mktemp -d "$PWD/mona-boot-work.XXXXXX")"
mkdir -p "$BOOT_WORK/tools"
cd "$BOOT_WORK"
MAGISK_APK="/absolute/path/to/Magisk.apk"
# confirm the APK contains the expected host binary.
unzip -l "$MAGISK_APK" 'lib/x86_64/libmagiskboot.so'
# write and make the host binary executable.
unzip -p "$MAGISK_APK" 'lib/x86_64/libmagiskboot.so' > "$BOOT_WORK/tools/magiskboot"
chmod 755 "$BOOT_WORK/tools/magiskboot"
MAGISKBOOT="$BOOT_WORK/tools/magiskboot"
# confirm extraction produced a nonempty file.
test -s "$MAGISKBOOT"
```

If the APK lacks this x86-64 library, obtain an x86-64 `magiskboot` from an
official Magisk release/build.

### Pull the active-slot `boot` partition

Pull the active-slot **`boot`** partition. These commands require working
`su` on the phone. If the phone is not rooted, obtain `boot.img` from the
exact matching stock firmware package. Do not substitute `init_boot` or
`vendor_boot`.

```bash
# identify the active slot and its boot block device.
adb devices
SLOT="$(adb shell getprop ro.boot.slot_suffix | tr -d '\r')"
case "$SLOT" in _a|_b) ;; *) echo "Unexpected slot: $SLOT" >&2; exit 1 ;; esac
adb shell "su -c 'ls -l /dev/block/by-name/boot${SLOT}'"
# read the boot partition; write copies to phone Download and BOOT_WORK.
adb shell "su -c 'dd if=/dev/block/by-name/boot${SLOT} of=/sdcard/Download/boot${SLOT}-stock.img bs=4M'"
adb pull "/sdcard/Download/boot${SLOT}-stock.img" "$BOOT_WORK/boot-stock.img"
# confirm the copied file has Android boot image magic.
test "$(head -c 8 "$BOOT_WORK/boot-stock.img")" = 'ANDROID!'
# write checksum, slot, and fingerprint files beside the copy.
sha256sum "$BOOT_WORK/boot-stock.img" > "$BOOT_WORK/boot-stock.img.sha256"
printf '%s\n' "$SLOT" > "$BOOT_WORK/active-slot.txt"
adb shell getprop ro.build.fingerprint > "$BOOT_WORK/phone-fingerprint.txt"
```

The `dd` command reads the boot partition and writes a copy to the phone's
Download directory; `adb pull` copies it to the host. If `su` or the boot
magic check fails, stop. Pull a fresh image after an OTA or slot change.

### Unpack, replace, and repack

Set `IMAGE` to the section 3 artifact. Keep the original extraction for
comparison; replace only `modified/kernel`.

```bash
# confirm the built kernel Image exists.
IMAGE="$HOME/phone-appliance/android-kernel-env/out/mona-parrot-image/arch/arm64/boot/Image"
test -s "$IMAGE"
# unpack stock boot, replace its kernel, and write boot-custom.img.
mkdir -p "$BOOT_WORK/original" "$BOOT_WORK/modified" "$BOOT_WORK/verified"
(cd "$BOOT_WORK/original" && "$MAGISKBOOT" unpack "$BOOT_WORK/boot-stock.img")
# confirm stock boot yielded a kernel.
test -s "$BOOT_WORK/original/kernel"
# copy all components, replace only kernel, and rebuild the image.
cp -a "$BOOT_WORK/original/." "$BOOT_WORK/modified/"
cp "$IMAGE" "$BOOT_WORK/modified/kernel"
(cd "$BOOT_WORK/modified" && env -u PATCHVBMETAFLAG "$MAGISKBOOT" repack \
  "$BOOT_WORK/boot-stock.img" "$BOOT_WORK/boot-custom.img")
# confirm a repacked image was written.
test -s "$BOOT_WORK/boot-custom.img"
```

Do not use `unpack -n` or `repack -n`; they change compression handling.
Leaving `PATCHVBMETAFLAG` unset avoids requesting Magisk's vbmeta-disable
behavior.

### Verify the repacked payload before using it

The repacked kernel must equal `Image`; all other extracted components must
equal those from the stock image.

```bash
# unpack boot-custom.img into BOOT_WORK/verified for comparison.
(cd "$BOOT_WORK/verified" && "$MAGISKBOOT" unpack "$BOOT_WORK/boot-custom.img")
# compare the repacked kernel with the built Image.
cmp "$IMAGE" "$BOOT_WORK/verified/kernel"
# write component lists, compare them, then compare each component.
(cd "$BOOT_WORK/original" && find . -maxdepth 1 -type f ! -name kernel -printf '%f\n' | sort) \
  > "$BOOT_WORK/original-components.txt"
(cd "$BOOT_WORK/verified" && find . -maxdepth 1 -type f ! -name kernel -printf '%f\n' | sort) \
  > "$BOOT_WORK/verified-components.txt"
diff -u "$BOOT_WORK/original-components.txt" "$BOOT_WORK/verified-components.txt"
while IFS= read -r part; do
  cmp "$BOOT_WORK/original/$part" "$BOOT_WORK/verified/$part" || exit 1
done < "$BOOT_WORK/original-components.txt"
sha256sum "$BOOT_WORK/boot-custom.img"
```

If any comparison fails, do not use `boot-custom.img`. Inspect `magiskboot`
output for warnings. These checks cannot prove bootloader acceptance or
compatibility with installed vendor modules. Keep `boot-stock.img` for recovery.

## 7. Test-boot, flash, and recover `boot-custom.img`

Before any boot or flash attempt, verify the exact firmware match, active slot,
partition size, and unlocked bootloader state. Back up user data before unlocking
the bootloader. Keep `$BOOT_WORK/boot-stock.img` (and matching stock firmware
images) for recovery, and **do not relock the bootloader with custom images
installed**.

### Pre-flash checks on the Linux host

If you opened a new terminal, set `BOOT_WORK` to the `mona-boot-work.*` directory
created in section 6 before running these checks:

```bash
test -s "$BOOT_WORK/boot-stock.img"
test -s "$BOOT_WORK/boot-custom.img"
SLOT="$(tr -d '\r\n' < "$BOOT_WORK/active-slot.txt")"
case "$SLOT" in _a|_b) ;; *) echo "Unexpected slot: $SLOT" >&2; exit 1 ;; esac
test "$(stat -c %s "$BOOT_WORK/boot-custom.img")" -le "$(stat -c %s "$BOOT_WORK/boot-stock.img")"
```

### Enter fastboot and check slot state

```bash
adb reboot bootloader
fastboot devices
fastboot getvar current-slot
fastboot getvar unlocked
```

Confirm `current-slot` matches `SLOT` (`_a` -> `a`, `_b` -> `b`) and the
bootloader reports unlocked before writing anything. On WSL, if `fastboot`
cannot see the phone in bootloader mode, attach the fastboot USB device to WSL
with `usbipd` or run the `fastboot` commands from Windows using copies of
`boot-custom.img` and `boot-stock.img`.

### Optional one-shot test-boot

If supported by your bootloader, test-boot `boot-custom.img` in memory without
modifying the `boot` partition:

```bash
fastboot boot "$BOOT_WORK/boot-custom.img"
```

A reboot returns to the installed image if the test boot fails or hangs. Some
Motorola bootloaders reject `fastboot boot` with unsigned/repacked payloads or
do not pass the same boot arguments as a partition boot; if `fastboot boot` is
refused, proceed to flashing only once you are ready to recover via fastboot.

### Flash the active slot and verify

Flash the exact active-slot `boot` partition backed up in section 6 (do not
substitute `init_boot` or `vendor_boot`):

```bash
fastboot flash "boot${SLOT}" "$BOOT_WORK/boot-custom.img"
fastboot reboot
```

Once Android boots, confirm the new kernel, active slot, loaded modules, and
attached USB peripherals:

```bash
adb wait-for-device
adb shell uname -a
adb shell getprop ro.boot.slot_suffix
```

In an **Android root shell** (`adb shell`, then `su`), verify config flags and
module loading:

```sh
zcat /proc/config.gz 2>/dev/null | grep -E 'CONFIG_(USB_ACM|USB_SERIAL_CH341|USB_SERIAL_CP210X|USB_SERIAL_FTDI_SIO|USB_SERIAL_PL2303|VIDEO_DEV|USB_VIDEO_CLASS)='
lsmod | head -n 30
dmesg | tail -n 60
```

Confirm stock vendor modules (including `qti_battery_charger` and display/radio
drivers) still load cleanly alongside the custom `Image`. Keep
`$BOOT_WORK/boot-stock.img` off the phone.

### Roll back to stock

If Android fails to boot or required vendor modules fail to load, enter
fastboot with the phone's hardware keys (or `adb reboot bootloader` if ADB is
reachable) and restore the stock image:

```bash
fastboot devices
fastboot flash "boot${SLOT}" "$BOOT_WORK/boot-stock.img"
fastboot reboot
```

If running from another terminal, substitute the actual `_a` or `_b` slot and
the full path to `boot-stock.img`.

## 8. Rebuild an individual in-tree module (`qti_battery_charger.ko`)

**An `Image`-only replacement is insufficient for fake SOC.** Because
`CONFIG_QTI_BATTERY_CHARGER=m`, `drivers/power/supply/qti_battery_charger.c` is
loaded from `/vendor_dlkm/lib/modules/qti_battery_charger.ko`.

When `# CONFIG_MODULE_SIG_FORCE is not set` and `CONFIG_MODVERSIONS=y` on the
running kernel (confirmed on Mona build `W1VAS36.62-22-26-7-2-3`), an unsigned
in-tree module can be rebuilt against the running kernel's `/proc/config.gz`
and tested live without reflashing `boot` or `/vendor_dlkm`. With
`CONFIG_MODVERSIONS=y` and a `__versions` CRC table present, Linux's module
loader ignores the `UTS_RELEASE` prefix before the first space in `vermagic`
(such as `6.6.118-android15-8-maybe-dirty-4k`) and enforces the trailing flags
plus symbol CRCs.

### Check module requirements on the phone

In an **Android root shell** (`adb shell`, then `su`):

```sh
modinfo /vendor_dlkm/lib/modules/qti_battery_charger.ko
lsmod | grep -E 'qti_battery|mmi_charger|glink'
zcat /proc/config.gz 2>/dev/null | grep -E 'MODULE_SIG|MODVERSIONS|RANDSTRUCT|QTI_PMIC_GLINK_CLIENT_DEBUG|QTI_BATTERY_CHARGER'
```

On the inspected phone, `qti_battery_charger.ko` reported:

- `vermagic`: `6.6.118-android15-8-maybe-dirty-4k SMP preempt mod_unload modversions aarch64`
- `depends`: `qti_pmic_glink,panel_event_notifier`
- Active dependents in `lsmod`: `leds_qpnp_flash_v2`, `qcom_hv_haptics`, `qcom_spmi_wled`
- `# CONFIG_MODULE_SIG_FORCE is not set`, `CONFIG_MODVERSIONS=y`

If `CONFIG_MODULE_SIG_FORCE=y` or `CONFIG_RANDSTRUCT_FULL=y` on a later build,
a standalone `.ko` build will not load onto the stock `Image`, and you must
rebuild and package the matching kernel and full module set together instead.

### Pull the running `.config` and stock `.ko`

On the Linux/WSL host:

```bash
mkdir -p ~/phone-appliance/mona-mod
cd ~/phone-appliance/mona-mod
adb pull /vendor_dlkm/lib/modules/qti_battery_charger.ko ./qti_battery_charger.stock.ko
adb shell "su -c 'zcat /proc/config.gz'" > running.config
```

### Compile `qti_battery_charger.ko` and verify CRCs

In the Mona kernel repository (`moto-g-stylus-2025-kernel`, `mona-appliance`
branch), `arch/arm64/configs/vendor/ext_config/moto-parrot-mona.config` already
sets `CONFIG_QTI_PMIC_GLINK_CLIENT_DEBUG=y`. To match your running `Image`'s
symbol CRCs directly, start from `running.config` inside `android-kernel-env`
(using the same `KERNEL_SRC`, `KERNEL_OUT`, `HOST_CFLAGS`, `HOST_LDFLAGS`,
`PATH`, and `LD_LIBRARY_PATH` environment from section 3) and enable
`QTI_PMIC_GLINK_CLIENT_DEBUG`:

```bash
mkdir -p "$KERNEL_OUT/tmp"
cp ~/phone-appliance/mona-mod/running.config "$KERNEL_OUT/.config"
"$KERNEL_SRC/scripts/config" --file "$KERNEL_OUT/.config" --enable QTI_PMIC_GLINK_CLIENT_DEBUG

make -C "$KERNEL_SRC" O="$KERNEL_OUT" ARCH=arm64 LLVM=1 \
  HOSTCFLAGS="$HOST_CFLAGS" HOSTLDFLAGS="$HOST_LDFLAGS" olddefconfig

grep -E 'CONFIG_(RPMSG|DEBUG_FS|QTI_PMIC_GLINK|QTI_PMIC_GLINK_CLIENT_DEBUG|QTI_BATTERY_CHARGER)=' "$KERNEL_OUT/.config"

make -C "$KERNEL_SRC" O="$KERNEL_OUT" ARCH=arm64 LLVM=1 \
  HOSTCFLAGS="$HOST_CFLAGS" HOSTLDFLAGS="$HOST_LDFLAGS" -j"$(nproc)" Image modules
```

Expect:

```text
CONFIG_RPMSG=y
CONFIG_DEBUG_FS=y
CONFIG_QTI_PMIC_GLINK=m
CONFIG_QTI_PMIC_GLINK_CLIENT_DEBUG=y
CONFIG_QTI_BATTERY_CHARGER=m
```

`CONFIG_QTI_PMIC_GLINK_CLIENT_DEBUG` depends only on `QTI_PMIC_GLINK && DEBUG_FS`
and selects no additional options.

Before loading on the phone, compare `vermagic` and imported symbol CRCs
against the stock `.ko` on the host:

```bash
modinfo "$KERNEL_OUT/drivers/power/supply/qti_battery_charger.ko" | grep -E 'vermagic|depends'
diff -u \
  <(modprobe --dump-modversions ~/phone-appliance/mona-mod/qti_battery_charger.stock.ko | sort) \
  <(modprobe --dump-modversions "$KERNEL_OUT/drivers/power/supply/qti_battery_charger.ko" | sort)
```

Confirm the trailing `vermagic` tokens are `SMP preempt mod_unload modversions aarch64`
and that shared imported symbol CRCs match.

### Live-test on the phone without modifying `/vendor_dlkm`

Because `leds_qpnp_flash_v2`, `qcom_hv_haptics`, and `qcom_spmi_wled` hold
references to `qti_battery_charger`, unload them first, swap
`qti_battery_charger.ko`, and reload them. A reboot reverts back to the stock
`/vendor_dlkm` module cleanly:

```sh
adb push "$KERNEL_OUT/drivers/power/supply/qti_battery_charger.ko" /data/local/tmp/qti_battery_charger.ko
adb shell
su

# Inspect exact .ko filenames under /vendor_dlkm/lib/modules/ before reloading.
ls /vendor_dlkm/lib/modules/*flash* /vendor_dlkm/lib/modules/*haptics* /vendor_dlkm/lib/modules/*wled*

rmmod leds_qpnp_flash_v2 qcom_hv_haptics qcom_spmi_wled
rmmod qti_battery_charger
insmod /data/local/tmp/qti_battery_charger.ko

# Reload the three dependent modules using their exact filenames from the ls output:
insmod /vendor_dlkm/lib/modules/<leds-flash>.ko
insmod /vendor_dlkm/lib/modules/<haptics>.ko
insmod /vendor_dlkm/lib/modules/<wled>.ko
```

If `insmod` fails, inspect `dmesg | tail -n 30`. Once loaded, run the verification
steps in section 9 below.

## 9. Manual fake SOC

Enabling `CONFIG_QTI_PMIC_GLINK_CLIENT_DEBUG=y` activates the existing capacity
override and `power_supply_changed()` notification in
`drivers/power/supply/qti_battery_charger.c`. No driver changes or boot-time
writes are needed; the driver initializes `fake_soc` to `-EINVAL` (`-22`), so
normal reporting remains the default.

### Additional debug controls

`CONFIG_QTI_PMIC_GLINK_CLIENT_DEBUG` covers more than fake SOC. Kconfig
explicitly warns against enabling it on production devices because writes can
change physical parameters and cause instability. In this tree it also enables:

- `battery_debug/votables/<name>/override` (debugfs, mode `0600`) in
  `qti_battery_debug.c`: writes send charging-vote overrides to firmware.
- `altmode/send_pan_en` and `altmode/send_pan_ack` (debugfs, mode `0200`) in
  `altmode-glink.c`: writes trigger USB alternate-mode protocol messages.

Both associated drivers are already configured as modules. The controls appear
when rebuilt drivers probe successfully and debugfs is accessible. Enabling the
flag does not itself write overrides, but these privileged interfaces expand what
a process with sufficient access can change. Leave them unused; preserve SELinux
and existing debugfs access restrictions. `battery_charger/block_tx` is already
gated by `DEBUG_FS` independently of this option, and `QTI_PMIC_GLINK_DEBUG` is
a separate existing option.

This config flag is used because it activates Qualcomm's existing implementation
without source patches; a fake-SOC-only Kconfig option would require a separate
driver patch if the extra debug controls are unacceptable.

### Verify and operate `fake_soc`

Before setting an override, confirm `fake_soc` reads `-22`. Record battery
`capacity`, `voltage_now`, `current_now`, and `temp` from
`/sys/class/power_supply/battery/`:

```sh
adb shell "su -c 'echo 80 > /sys/class/qcom-battery/fake_soc'"
adb shell "su -c 'cat /sys/class/qcom-battery/fake_soc'"
adb shell "su -c 'cat /sys/class/power_supply/battery/capacity'"
adb shell dumpsys battery
adb shell "su -c 'cat /sys/class/power_supply/battery/voltage_now /sys/class/power_supply/battery/current_now /sys/class/power_supply/battery/temp'"
```

Expect `fake_soc` and kernel capacity to read `80`, and Android's level to
update to `80`. Voltage, current, and temperature retain their existing
measurement paths and may vary between samples. Android's health stack must
consume this power supply for the Android level to follow it. If only `fake_soc`
changes, verify the loaded charger module was rebuilt; if kernel capacity
changes but Android's level does not, inspect the health HAL's source (including
`mmi_battery`) and any active Android battery simulation.

Restore normal reporting and repeat the capacity/Android checks:

```sh
adb shell "su -c 'echo -22 > /sys/class/qcom-battery/fake_soc'"
```

Only values from `0` through `100` activate the override; `-22` restores the
default sentinel. A reboot leaves the override inactive, and no automatic boot
activation is supplied by default.

This changes reported Linux capacity, **not** firmware fuel-gauge state or
charging status (`Discharging`). Thermal, charging, and low-voltage protection
code is unchanged. Firmware shutdowns can still occur, and other consumers of
reported capacity can change behavior. The capacity getter still reads firmware
before applying the override, so fake SOC is not a bypass for GLINK read
failures.

The 2026-10-16 phone inspection also found `bcl_soc`, which computes battery
depletion as `100 - battery/capacity`. A working override of `80` therefore
reports `20` in the `socd` thermal zone and affects depletion-based mitigation.
Separate voltage/current BCL protection remains active. See
[battery-replacement power](power.md) for live observations, XL4015
power-delivery considerations, and recovery.

## References

- [Android: Build kernels](https://source.android.com/docs/setup/build/building-kernels)
- [Android: AOSP host setup and Repo installation](https://source.android.com/docs/setup/start/requirements)
- [Android kernel manifest: `common-android15-6.6-2026-01`](https://android.googlesource.com/kernel/manifest/+/refs/heads/common-android15-6.6-2026-01)
- [Kernel documentation: LLVM builds](https://docs.kernel.org/kbuild/llvm.html)
- [Android: Kernel branches and build systems](https://source.android.com/docs/setup/reference/bazel-support)
- [Android: Generic boot partition](https://source.android.com/docs/core/architecture/partitions/generic-boot)
- [Magisk: `magiskboot` tools and repack behavior](https://topjohnwu.github.io/Magisk/tools.html)
- [Magisk: official releases](https://github.com/topjohnwu/Magisk/releases)
- [Motorola: published Parrot build recipe (example product)](https://github.com/MotorolaMobilityLLC/readme/blob/master/W1VT36H.22-20.txt)
- [Android: Lock and unlock the bootloader](https://source.android.com/docs/core/architecture/bootloader/locking_unlocking)
