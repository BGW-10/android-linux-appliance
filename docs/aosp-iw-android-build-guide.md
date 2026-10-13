# Build AOSP `iw` for Android ARM64 using the repositories' Makefiles

This guide documents the **working Makefile-based build** completed for a rooted Moto G Stylus 2025 running ARM64 Android. It uses the Android Open Source Project (AOSP) source repositories for `iw` and `libnl`, Google's Android NDK r30, and each repository's existing build machinery.

> **What this is:** a manual Android NDK cross-build using AOSP source code and the projects' Makefiles.
>
> **What this is not:** a full AOSP/Soong module build or Android OS build. We fetched only `external/iw` and `external/libnl`, built the two `libnl` libraries `iw` needs, then used `iw`'s existing Makefile for the final executable.

## Verified result

The final Makefile-built executable was successfully transferred to the Moto and worked with its Qualcomm Wi-Fi driver. `file` reported an Android ARM64 PIE executable targeting API 29. `llvm-readelf` reported these dynamic dependencies:

```text
Class:   ELF64
Machine: AArch64
NEEDED:  libdl.so
NEEDED:  libc.so
```

There was no `libnl.so` dependency because `libnl` was statically linked. On the phone, `iw dev wlan0 get power_save` worked, and `iw dev wlan0 set power_save off` was accepted.

## 1. Prerequisites

The instructions assume:

- Windows with Debian or Ubuntu under WSL 2 on an x86-64 PC.
- Android platform-tools (`adb`) installed on Windows for the final device test.
- Source and build directories stored in the WSL Linux filesystem, for example `/home/barry/...`, rather than under `/mnt/c`.

Install the Linux build tools in WSL:

```bash
sudo apt update
sudo apt install -y git curl python3 build-essential bc bison flex \
    libssl-dev libncurses-dev libelf-dev rsync unzip zip \
    autoconf automake libtool pkg-config
```

A JDK and a full Android OS build are not required for this workflow.

Source and tool references:

- [AOSP `external/iw`](https://android.googlesource.com/platform/external/iw/)
- [AOSP `external/libnl`](https://android.googlesource.com/platform/external/libnl/)
- [Android NDK downloads](https://developer.android.com/ndk/downloads)
- [Upstream `iw` documentation](https://wireless.docs.kernel.org/en/latest/en/users/documentation/iw.html)

## 2. Download and verify the Android NDK

This build was made with NDK r30, version `30.0.16248370`. Download the Linux x86-64 archive from Google's official distribution and verify its SHA-1 checksum before extracting it.

```bash
mkdir -p ~/android-ndk
cd ~/android-ndk

curl -fL --retry 3 \
    -o android-ndk-r30-linux.zip \
    https://dl.google.com/android/repository/android-ndk-r30-linux.zip

echo "5107f898313790e449e87eee2183d9a20602dee9  android-ndk-r30-linux.zip" \
    | sha1sum -c -

unzip -q android-ndk-r30-linux.zip
```

The checksum command should report:

```text
android-ndk-r30-linux.zip: OK
```

Google lists this checksum on its [NDK downloads page](https://developer.android.com/ndk/downloads). If using a different NDK release, check the official page and update the archive name, checksum, and directory path.

Set the compiler variables in any WSL terminal used for the build:

```bash
export NDK="$HOME/android-ndk/android-ndk-r30"
export TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin"
export CC="$TOOLCHAIN/aarch64-linux-android29-clang"
```

Confirm the compiler is available:

```bash
"$CC" --version
```

The output should identify a target like `aarch64-unknown-linux-android29`. API level 29 is the binary's Android API target; the Moto runs a newer Android release.

## 3. Fetch just the two AOSP repositories

Install Google's `repo` launcher:

```bash
mkdir -p ~/bin
curl -fL https://storage.googleapis.com/git-repo-downloads/repo \
    -o ~/bin/repo
chmod +x ~/bin/repo
export PATH="$HOME/bin:$PATH"

repo --version
```

Initialize a minimal Repo workspace:

```bash
mkdir -p ~/aosp-iw
cd ~/aosp-iw

repo init --partial-clone \
    -b android-latest-release \
    -u https://android.googlesource.com/platform/manifest
```

Sync only the two projects, not the full Android source tree:

```bash
cd ~/aosp-iw
repo sync -c -j2 platform/external/iw platform/external/libnl
```

Repo's project names differ from the checkout paths. The local paths are:

```text
~/aosp-iw/external/iw
~/aosp-iw/external/libnl
```

Optional: record the exact source revisions used for repeatability:

```bash
repo manifest -r -o ~/aosp-iw/manifest-lock.xml
```

The `android-latest-release` manifest branch can advance. Retaining a revision-pinned manifest helps reproduce the same source revisions later.

## 4. Configure `libnl` for Android

AOSP's `external/libnl` source includes Autotools files. Use its `autogen.sh`, `configure`, and Makefile, but configure it for the Android NDK target.

```bash
export NDK="$HOME/android-ndk/android-ndk-r30"
export TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin"
export AR="$TOOLCHAIN/llvm-ar"
export RANLIB="$TOOLCHAIN/llvm-ranlib"
export CC="$TOOLCHAIN/clang --target=aarch64-linux-android29"

mkdir -p "$HOME/aosp-iw-build"
cd "$HOME/aosp-iw/external/libnl"

# The checkout has configure.ac and autogen.sh. Generate configure if absent.
if [ ! -x ./configure ]; then
    ./autogen.sh
fi

./configure \
    --host=aarch64-linux-android \
    --prefix="$HOME/aosp-iw-build/android-prefix" \
    --enable-static \
    --disable-shared
```

The `CC` setting intentionally includes the NDK Clang path and `--target` option. `AR` and `RANLIB` point to the NDK's LLVM tools so the archives contain Android ARM64 objects.

The `--prefix` selects a staging path in the generated configuration. This workflow uses the generated archives directly and does not require `make install`.

## 5. Build only the two `libnl` libraries `iw` needs

Do **not** build the default `libnl` target. It includes routing and traffic-control components that `iw` does not need. During this project, the all-target build failed in unrelated queue-discipline (`qdisc`) sources, so we built only the core and generic-netlink libraries.

One other important detail: Autotools' default include list adds `include/linux-private`. That directory caused conflicts with Android's Bionic/NDK networking headers and errors such as `unknown type name 'in_addr_t'`. Override `default_includes` to omit `include/linux-private` for this Android build.

Run:

```bash
cd ~/aosp-iw/external/libnl

make clean
make -j2 \
    default_includes='-I./include -I./include -I./third_party/c-list/src' \
    lib/libnl-3.la \
    lib/libnl-genl-3.la
```

The successful output included:

```text
CC       lib/libnl_3_la-addr.lo
...
CC       lib/genl/libnl_genl_3_la-ctrl.lo
...
CCLD     lib/libnl-3.la
CCLD     lib/libnl-genl-3.la
```

Check for the static archives:

```bash
find lib -type f \
    \( -name 'libnl-3.a' -o -name 'libnl-genl-3.a' \) -print
```

Expected paths:

```text
lib/.libs/libnl-3.a
lib/.libs/libnl-genl-3.a
```

The Make targets end in `.la` and are in `lib/`. The resulting static `.a` archives are located in `lib/.libs/`. No `make install` is necessary.

## 6. Build `iw` with its existing Makefile

The upstream `iw` Makefile normally calls `pkg-config` to locate host-installed `libnl`. That is inappropriate for this cross-build because we must link the Android-target archives built in the previous step. Set `NO_PKG_CONFIG=1` and provide the include paths and archive paths explicitly.

Run this complete block:

```bash
set -e

IW="$HOME/aosp-iw/external/iw"
NL="$HOME/aosp-iw/external/libnl"
NDK="$HOME/android-ndk/android-ndk-r30"
TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin"
CC="$TOOLCHAIN/aarch64-linux-android29-clang"

test -f "$NL/lib/.libs/libnl-3.a"
test -f "$NL/lib/.libs/libnl-genl-3.a"

cd "$IW"

# NO_PKG_CONFIG is also required for clean: the Makefile runs dependency
# detection while parsing, even for the clean target.
make NO_PKG_CONFIG=1 clean

make -j2 V=1 \
    CC="$CC" \
    NO_PKG_CONFIG=1 \
    EXTRA_CFLAGS="-DCONFIG_LIBNL30 -I$NL/include -I$NL/lib/route" \
    LDFLAGS="-Wl,--no-gc-sections" \
    LIBS="$NL/lib/.libs/libnl-genl-3.a $NL/lib/.libs/libnl-3.a -ldl"
```

This uses `iw`'s Makefile to discover and compile its source files, generate version information, and link the executable. No hand-maintained C source list is needed.

The link order is intentional: `libnl-genl-3.a` comes before `libnl-3.a` because generic netlink uses symbols supplied by the core library. `-ldl` supplies dynamic-loader symbols.

On success, the executable is:

```text
~/aosp-iw/external/iw/iw
```

## 7. Verify the executable before installing it

From any WSL terminal, set `TOOLCHAIN` if necessary, then run:

```bash
NDK="$HOME/android-ndk/android-ndk-r30"
TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin"
cd ~/aosp-iw/external/iw

file iw

"$TOOLCHAIN/llvm-readelf" -h iw | grep -E 'Class:|Machine:'
"$TOOLCHAIN/llvm-readelf" -d iw | grep NEEDED
```

Expected properties:

- `ELF 64-bit LSB pie executable`
- `ARM aarch64`
- Android interpreter `/system/bin/linker64`
- Android API target 29
- Dynamic dependencies `libdl.so` and `libc.so`
- No `libnl.so` dependency, because `libnl` is statically linked

The Makefile-built binary was verified to have these properties. Exact file size can vary with build flags and source revisions.

## 8. Copy to Windows and push it to the phone

From WSL, copy the binary to the Windows Downloads folder. Change `/mnt/c/Users/barry` if the Windows profile folder differs:

```bash
cp ~/aosp-iw/external/iw/iw /mnt/c/Users/barry/Downloads/iw
sha256sum ~/aosp-iw/external/iw/iw
```

In Windows PowerShell, with the Moto connected and USB debugging enabled:

```powershell
adb devices
adb push "$env:USERPROFILE\Downloads\iw" /data/local/tmp/iw
adb shell
```

Make sure `adb devices` shows the phone as `device`, not `unauthorized`. In the phone shell, run:

```sh
su
chmod 755 /data/local/tmp/iw
/data/local/tmp/iw --version
/data/local/tmp/iw dev wlan0 get power_save
/data/local/tmp/iw dev wlan0 set power_save on
/data/local/tmp/iw dev wlan0 get power_save
/data/local/tmp/iw dev wlan0 set power_save off
/data/local/tmp/iw dev wlan0 get power_save
```

The tested Moto accepted these commands and reported `Power save: off` after the final command. The first attempt to execute the pushed binary returned `Permission denied`; running `chmod 755` fixed it.

If a command fails on another device, don't automate it yet. A correctly compiled executable does not guarantee that every kernel or Wi-Fi driver supports every operation.

## 9. Optional: install the binary for Magisk

Only do this after you have tested the new binary manually. In the phone's shell, as root:

```sh
cp /data/local/tmp/iw /data/adb/iw
chown 0:0 /data/adb/iw
chmod 755 /data/adb/iw
mkdir -p /data/adb/service.d
```

Create a Magisk service script to wait for `wlan0`, then disable power saving:

```sh
cat > /data/adb/service.d/disable-wifi-powersave.sh <<'SERVICE_SCRIPT_EOF'
#!/system/bin/sh

IW=/data/adb/iw

# Wait up to 120 seconds for wlan0 to become available.
i=0
while [ "$i" -lt 60 ]; do
    if "$IW" dev wlan0 info >/dev/null 2>&1; then
        "$IW" dev wlan0 set power_save off
        exit $?
    fi

    sleep 2
    i=$((i + 1))
done

exit 0
SERVICE_SCRIPT_EOF

chown 0:0 /data/adb/service.d/disable-wifi-powersave.sh
chmod 755 /data/adb/service.d/disable-wifi-powersave.sh
```

After reboot, verify the state:

```sh
su
/data/adb/iw dev wlan0 get power_save
```

This simple script applies the setting once during boot. It does **not** reapply the setting after every Wi-Fi disconnect/reconnect. Toggle Wi-Fi off and on and check again; if the driver resets power saving on reconnect, a separate interface-event mechanism may be needed.

## 10. Troubleshooting

### `Cannot find development files for any supported version of libnl`

Pass `NO_PKG_CONFIG=1` to **both** `make clean` and the actual `make` invocation in `external/iw`. The Makefile checks for dependencies while parsing, even when the requested target is only `clean`.

### `in_addr_t` undeclared in `arpa/inet.h`

The `libnl` Autotools build normally places `include/linux-private` first in its include path. This private header directory conflicted with the Android NDK networking headers. The `default_includes` override in section 5 omits that directory.

### Errors from `lib/route/qdisc/*.c`

These occurred when building `libnl`'s default target, which includes unrelated traffic-control components. Build only `lib/libnl-3.la` and `lib/libnl-genl-3.la` instead.

### `No rule to make target 'lib/genl/libnl-genl-3.la'`

The correct target is `lib/libnl-genl-3.la`, not `lib/genl/libnl-genl-3.la`. The source files are under `lib/genl/`, but the Make target is in `lib/`.

### `iw: can't execute: Permission denied`

After pushing the executable, run `chmod 755 /data/local/tmp/iw` from the phone shell as root.

### `iw` builds but a command fails on the phone

Test as root and inspect the precise error. Build success verifies architecture and linkage, not kernel-driver support for every operation.

## 11. Successful workflow summary

1. Fetch AOSP's `external/iw` and `external/libnl` with Repo.
2. Configure `external/libnl` for NDK Clang targeting `aarch64-linux-android29`.
3. Use `libnl`'s Makefile to build only `lib/libnl-3.la` and `lib/libnl-genl-3.la`, overriding `default_includes` to omit the conflicting private Linux headers.
4. Use `iw`'s Makefile with `NO_PKG_CONFIG=1` and the Android static archives to build `iw`.
5. Verify the executable using `file` and `llvm-readelf`.
6. Push it to the phone, set its executable bit, and test the Wi-Fi power-save operation.

This procedure uses AOSP's source repositories and their existing Makefiles, avoids downloading the full Android source tree, and avoids maintaining a custom source-file list.

## Install `iw` at `/system/bin/iw` with a Magisk systemless module

This optional step makes `iw` available at the conventional Android system path. It assumes the tested ARM64 executable has already been pushed to `/data/local/tmp/iw`.

### 1. Create the module

Connect to the phone and open a root shell:

```sh
adb shell
su
```

Run the following commands on the phone:

```sh
set -e

MODID=iw_system_bin
MODDIR="/data/adb/modules/$MODID"
IW_SOURCE=/data/local/tmp/iw

# Confirm that the tested binary exists.
test -f "$IW_SOURCE"

# Create the module's system overlay directory.
mkdir -p "$MODDIR/system/bin"

# Install the executable into the overlay.
cp "$IW_SOURCE" "$MODDIR/system/bin/iw"

# Define the module metadata.
cat > "$MODDIR/module.prop" <<'EOF'
id=iw_system_bin
name=iw System Binary
version=6.17
versionCode=61700
author=Local
description=Provides native ARM64 iw at /system/bin/iw
EOF

# Set module directory permissions.
chown 0:0 "$MODDIR" "$MODDIR/system"
chmod 0755 "$MODDIR" "$MODDIR/system"

# Match conventional Android system/bin ownership and permissions.
chown 0:2000 "$MODDIR/system/bin" "$MODDIR/system/bin/iw"
chmod 0755 "$MODDIR/system/bin"
chmod 0755 "$MODDIR/system/bin/iw"

# Apply the standard Android system-file SELinux context.
chcon u:object_r:system_file:s0 "$MODDIR/system/bin"
chcon u:object_r:system_file:s0 "$MODDIR/system/bin/iw"

# Secure the module metadata.
chown 0:0 "$MODDIR/module.prop"
chmod 0644 "$MODDIR/module.prop"

echo "Module created at $MODDIR"
```

### 2. Reboot and verify

Reboot the phone:

```sh
reboot
```

After the phone restarts, open a root shell and test the executable:

```sh
su

/system/bin/iw --version
/system/bin/iw dev wlan0 get power_save
```

The version command should report `iw version 6.17`. The power-save query should report the current state; it should say `Power save: off` if your Wi-Fi power-saving script has successfully disabled it.

You can also verify that the module is active in the Magisk app.

### 3. Use the conventional path in scripts

Your existing script can now call:

```sh
/system/bin/iw dev wlan0 set power_save off
```

You no longer need to specify `/data/adb/iw` or `/data/local/tmp/iw`.

### 4. Disable or remove the module

To disable it without deleting its files:

```sh
su
touch /data/adb/modules/iw_system_bin/disable
reboot
```

To remove it completely instead:

```sh
su
rm -rf /data/adb/modules/iw_system_bin
reboot
```

This module only exposes the `iw` executable through Magisk's system overlay. It does not modify the original `/system` partition.
