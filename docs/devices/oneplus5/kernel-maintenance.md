# Maintaining the OnePlus kernel fork

[OnePlus index](README.md) · [Build and recovery](kernel.md)

Run these commands in `android_kernel_oneplus_msm8998`, not the appliance repo.
The prepared fork already contains the driver configuration and build scripts;
edit those files rather than recreating scripts from a copied documentation block.

## Files that define the build

| File | Purpose |
| --- | --- |
| `arch/arm64/configs/lineage_oneplus5_defconfig` | Persistent device/peripheral configuration. |
| `scripts/setup-toolchains.sh` | Fetch compiler/build tools into `WORKSPACE/toolchains`. |
| `scripts/build.sh` | Resolve config, check required options, compile, and identify the artifact. |
| `toolchains.conf` | Compiler labels and recorded revisions; see the GCC checkout caveat below. |

Keep generated toolchains, `out/`, boot backups, and packaged images out of Git.
Use separate commits for functional config, toolchain changes, and documentation.

## Configuration and dependencies

The reviewed defconfig contains:

```text
CONFIG_USB_ACM=y
CONFIG_USB_SERIAL=y
CONFIG_USB_SERIAL_GENERIC=y
CONFIG_USB_SERIAL_CH341=y
CONFIG_USB_SERIAL_CP210X=y
CONFIG_USB_SERIAL_FTDI_SIO=y
CONFIG_USB_SERIAL_PL2303=y
CONFIG_CAN=y
CONFIG_CAN_RAW=y
CONFIG_CAN_DEV=y
CONFIG_CAN_GS_USB=y
CONFIG_CAN_SLCAN=y
CONFIG_MEDIA_SUPPORT=y
CONFIG_MEDIA_CAMERA_SUPPORT=y
CONFIG_MEDIA_USB_SUPPORT=y
CONFIG_VIDEO_DEV=y
CONFIG_VIDEO_V4L2=y
CONFIG_USB_VIDEO_CLASS=y
CONFIG_USB_VIDEO_CLASS_INPUT_EVDEV=y
CONFIG_USB_UAS=y
CONFIG_USB_CONFIGFS_ACM=y
```

Replace contradictory disabled entries instead of appending duplicates. The
media/V4L2 parents are necessary for UVC to survive Kconfig resolution in this
4.4 tree. Its symbols differ from Mona's 6.6 tree. Built-in peripheral drivers
avoid adding Android module-loading work for these features.

After changing a setting, run a clean build with the checked toolchain and
inspect the generated `.config`, not just the source defconfig. Add required
new options to `scripts/build.sh`'s config check when extending the fork.

## Toolchains and upstream changes

The setup script at `e1d4edd7` does not enforce its two recorded GCC hashes.
Follow [the explicit checkout step](kernel.md#check-the-actual-toolchain-revisions)
and record actual `git rev-parse HEAD` values plus `clang --version` alongside
the artifact. Changing `toolchains.conf` alone does not update existing downloads.

For upstream work, first inspect `git status` and the configured remotes. Add
`https://github.com/LineageOS/android_kernel_oneplus_msm8998.git` as `upstream`
if absent, then work on a review branch:

```bash
git fetch upstream lineage-22.2
git switch -c review-lineage-update
# Inspect before choosing a merge/rebase:
git log --oneline HEAD..upstream/lineage-22.2
git diff HEAD..upstream/lineage-22.2 -- arch/arm64/configs/lineage_oneplus5_defconfig
```

Resolve updates deliberately; do a clean config/build and device validation
before replacing a known-good image. Preserve the matching ROM and backup boot
image so a regression can be isolated from unrelated userspace changes.

The original fork-creation walkthrough and inspected scripts are linked in
[the source map](../../reference/sources.md); the local build guide is the
operator-facing procedure.
