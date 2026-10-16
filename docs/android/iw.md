# Build and install Android ARM64 iw

[Documentation index](../README.md) · [Boot tuning](../setup/boot-services.md)

The earlier Mona build used AOSP `iw`/`libnl`, their Makefiles, and NDK r30. It
produced an ARM64 PIE executable targeting API 29, with `libc.so`/`libdl.so`
dependencies and static libnl. Mona accepted `get power_save` and
`set power_save off`. Other drivers still need their own test. This consolidation
does not claim a new build of the moving AOSP sources.

## 1. Host tools and NDK

Run in **Bash on x86-64 Linux/WSL**, with sources on the Linux filesystem:

```bash
sudo apt update
sudo apt install git curl python3 build-essential unzip autoconf automake \
    libtool pkg-config file
mkdir -p ~/android-ndk
cd ~/android-ndk
curl -fL --retry 3 -o android-ndk-r30-linux.zip \
    https://dl.google.com/android/repository/android-ndk-r30-linux.zip
echo '5107f898313790e449e87eee2183d9a20602dee9  android-ndk-r30-linux.zip' | sha1sum -c -
unzip -q android-ndk-r30-linux.zip
export NDK="$HOME/android-ndk/android-ndk-r30"
export TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin"
"$TOOLCHAIN/aarch64-linux-android29-clang" --version
```

The recorded NDK is `30.0.16248370`; the checksum above matches Google's
[r30 Linux download listing](https://developer.android.com/ndk/downloads).
Stop on a checksum mismatch. Use the matching official checksum if changing
releases. API 29 is the executable's target, not the phone's Android version.

## 2. Fetch only the two AOSP projects

Install Repo if absent, then initialize its workspace:

```bash
mkdir -p ~/bin
curl -fL https://storage.googleapis.com/git-repo-downloads/repo -o ~/bin/repo
chmod +x ~/bin/repo
export PATH="$HOME/bin:$PATH"
mkdir -p ~/aosp-iw
cd ~/aosp-iw
repo init --partial-clone -b android-latest-release \
    -u https://android.googlesource.com/platform/manifest
repo sync -c -j2 platform/external/iw platform/external/libnl
repo manifest -r -o manifest-lock.xml
```

The checkout paths are `external/iw` and `external/libnl`. Keep the resolved
manifest because `android-latest-release` advances. This procedure downloads
those projects rather than a full Android build tree.

## 3. Build Android libnl archives

In the same **host Bash** session:

```bash
export AR="$TOOLCHAIN/llvm-ar"
export RANLIB="$TOOLCHAIN/llvm-ranlib"
export CC="$TOOLCHAIN/clang --target=aarch64-linux-android29"
mkdir -p ~/aosp-iw-build
cd ~/aosp-iw/external/libnl
if [ ! -x ./configure ]; then ./autogen.sh; fi
./configure --host=aarch64-linux-android \
    --prefix="$HOME/aosp-iw-build/android-prefix" --enable-static --disable-shared
make clean
make -j2 \
    default_includes='-I./include -I./include -I./third_party/c-list/src' \
    lib/libnl-3.la lib/libnl-genl-3.la
test -f lib/.libs/libnl-3.a
test -f lib/.libs/libnl-genl-3.a
```

The include override omits `include/linux-private`, which conflicted with
Android's networking headers in the recorded build. Build only these two
libraries: the default target also builds unrelated qdisc sources that failed
there. The `.la` targets live under `lib/`; their archives appear in `lib/.libs/`.

## 4. Build iw and inspect the artifact

```bash
set -e
IW="$HOME/aosp-iw/external/iw"
NL="$HOME/aosp-iw/external/libnl"
CC="$TOOLCHAIN/aarch64-linux-android29-clang"
cd "$IW"
make NO_PKG_CONFIG=1 clean
make -j2 V=1 CC="$CC" NO_PKG_CONFIG=1 \
    EXTRA_CFLAGS="-DCONFIG_LIBNL30 -I$NL/include -I$NL/lib/route" \
    LDFLAGS='-Wl,--no-gc-sections' \
    LIBS="$NL/lib/.libs/libnl-genl-3.a $NL/lib/.libs/libnl-3.a -ldl"
file iw
"$TOOLCHAIN/llvm-readelf" -h iw | grep -E 'Class:|Machine:'
"$TOOLCHAIN/llvm-readelf" -d iw | grep NEEDED
sha256sum iw
```

`NO_PKG_CONFIG=1` is needed even for `clean`, because the Makefile parses host
library detection then. Archive order matters: generic netlink before core.
Expect AArch64/ELF64, Android's `linker64`, and no dynamic `libnl.so` dependency.

## 5. Test on Android

From a host with ADB: `adb push ~/aosp-iw/external/iw/iw /data/local/tmp/iw`.
If ADB is on Windows, first copy the binary from WSL to a Windows folder, then
use that Windows path with `adb push`. Open `adb shell`, then `su`.

**Android root shell:**

```sh
chmod 755 /data/local/tmp/iw
/data/local/tmp/iw --version
/data/local/tmp/iw dev wlan0 get power_save
/data/local/tmp/iw dev wlan0 set power_save off
/data/local/tmp/iw dev wlan0 get power_save
```

Record the previous state before changing it. Restore `on` if that was the
original state and this is only a test. A successful build does not guarantee
driver support; investigate an ioctl/netlink error before automating the command.

## 6. Install through the existing Magisk binary overlay

Use the repository's [extra_system_binaries module](../../android/data/adb/modules/extra_system_binaries/module.prop).
If another module already provides `/system/bin/iw`, choose one owner first.
The commands assume the checkout was pushed as in the boot-script guide.

**Android root shell:**

```sh
set -e
repo=/data/local/tmp/klipper-android-appliance-scripts
module=/data/adb/modules/extra_system_binaries
mkdir -p "$module/system/bin"
if [ ! -f "$module/module.prop" ]; then
    cp "$repo/android/data/adb/modules/extra_system_binaries/module.prop" "$module/module.prop"
fi
cp /data/local/tmp/iw "$module/system/bin/iw"
chown 0:0 "$module" "$module/system" "$module/module.prop"
chmod 755 "$module" "$module/system"
chmod 644 "$module/module.prop"
chown 0:2000 "$module/system/bin" "$module/system/bin/iw"
chmod 755 "$module/system/bin" "$module/system/bin/iw"
chcon u:object_r:system_file:s0 "$module/system/bin" "$module/system/bin/iw"
```

Reboot during maintenance, then verify `/system/bin/iw --version` and the
power-save query. `appliance-tuning.sh` applies and verifies power-save off at
startup, then uses `/system/bin/ip monitor link dev wlan0` to watch link events
(or the interface set by `WIFI_INTERFACE`). Each `state UP` event triggers a
two-second delay followed by another apply/readback. If the monitor exits, it
restarts after five seconds. Inspect `/data/local/tmp/appliance-tuning.log` for
the events and readback results. Retire a separate `disable-wifi-powersave.sh`
if it duplicates that policy. The overlay follows
[Magisk module layout](https://topjohnwu.github.io/Magisk/guides.html).

Disable the overlay by creating `$module/disable` and rebooting, or use the
Magisk app. This affects every binary in that module. Keep the compiled binary
and source manifest outside Git unless intentionally distributing a release.

## Troubleshooting

| Error | Fix/check |
| --- | --- |
| Host libnl not found | Pass `NO_PKG_CONFIG=1` to both iw make invocations. |
| `in_addr_t` or networking header conflict | Retain the libnl `default_includes` override. |
| Errors in `lib/route/qdisc/` | Build only the two named `.la` targets. |
| Missing `lib/genl/libnl-genl-3.la` target | Correct target: `lib/libnl-genl-3.la`. |
| Android `Permission denied` | Check mode 755 and SELinux context; do not disable SELinux. |
| Power-save operation fails | Verify interface name/root access and driver support. |

Source projects: [AOSP iw](https://android.googlesource.com/platform/external/iw/),
[AOSP libnl](https://android.googlesource.com/platform/external/libnl/),
[kernel wireless iw documentation](https://wireless.docs.kernel.org/en/latest/en/users/documentation/iw.html).
