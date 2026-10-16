# Debian ARM64 and SSH

[Documentation index](../README.md) · [Next: boot scripts](boot-services.md)

Start with a rooted, booting phone and working ADB. These steps apply to the
shared userspace; use your [device guide](../README.md#devices) for ROM/kernel
work. An existing working `debian-trixie` installation can skip rootfs creation.
All Debian commands and services here run as root, with application files under
`/root`. The initial Termux package commands run in Termux before entering `su`.

## 1. Android tools and chroot-distro

Install Termux from [F-Droid or its official releases](https://github.com/termux/termux-app#installation).
Use the same distribution source for Termux and its add-ons. In **Termux**:

```sh
pkg update
pkg upgrade
pkg install git curl wget nano
su
id
```

Install **BusyBox for Android NDK** and **chroot-distro** through Magisk's module
installer, then reboot. Use the releases linked by the
[chroot-distro project](https://github.com/Magisk-Modules-Alt-Repo/chroot-distro).
It recommends the NDK BusyBox module; Magisk's embedded BusyBox is also what
runs our boot scripts. These are separate roles.

In an **Android root shell**:

```sh
command -v busybox
command -v chroot-distro
chroot-distro help
chroot-distro list
```

The boot scripts default to `/system/bin/chroot-distro`; edit that path if your
installation differs. Mona was inspected with chroot-distro 2.1.0. Check the
installed version's help before applying commands from a different release.

## 2. Create the rootfs

Choose a dated Debian **trixie / arm64 / default** rootfs from the
[Linux Containers image server](https://images.linuxcontainers.org/images/debian/trixie/arm64/default/).
Record its build directory and verify its published checksum/signature. Keep
that record with your backups; “latest” is not a reproducible rootfs identifier.

In an **Android root shell**, replacing the URL with that exact rootfs:

```sh
chroot-distro add debian-trixie
chroot-distro download debian-trixie 'https://images.linuxcontainers.org/images/debian/trixie/arm64/default/BUILD/rootfs.tar.xz'
chroot-distro install debian-trixie
chroot-distro login debian-trixie
```

Skip `add`/`install` if the distro already exists. Installation is not an upgrade
command. Inside **Debian root**:

```sh
cat /etc/os-release
uname -m
whoami
```

Expect Debian Trixie, `aarch64`, and `root`. The default Android backing path is
`/data/local/chroot-distro/debian-trixie`; the chroot binds real kernel interfaces
including `/dev`, `/proc`, and `/sys`.

## 3. Network groups and packages

On the documented Android kernels, applications may need GID 3003 for network
sockets. Inspect first, then create only missing groups, as **Debian root**:

```sh
getent group 3003 || groupadd -g 3003 aid_inet
getent group 3004 || groupadd -g 3004 aid_net_raw
getent group aid_inet
getent group aid_net_raw
```

If either numeric GID already has another name, use that name in subsequent
commands and service files. Do not assign an unrelated existing group a new GID.
GID 3004 is for raw networking, such as diagnostic ping.

```sh
usermod -aG aid_inet,aid_net_raw root
# APT downloads as _apt; this was required on the recorded OnePlus setup.
usermod -g aid_inet _apt
id _apt
apt update
apt full-upgrade
apt install git curl wget nano ca-certificates openssh-server usbutils \
    iproute2 procps locales less runit util-linux
```

Use a new login session for changed group memberships. If APT still fails,
distinguish DNS, clock/TLS, and permission errors from a missing network route;
changing groups cannot fix an offline phone.

## 4. Verify root file access

Inside **Debian root**:

```sh
id
touch /root/write-test
rm /root/write-test
```

The runit services inherit root from the launcher and set `HOME=/root`.
Keep application files under `/root` and add their dependencies when you install
each service.

## 5. SSH keys and first login

From the **host**, create a key if needed with `ssh-keygen -t ed25519`. Copy the
public key text from your `.pub` file. In **Debian root**:

```sh
ssh-keygen -A
install -d -m 755 /run/sshd
install -d -m 700 /root/.ssh
nano /root/.ssh/authorized_keys
chown root:root /root/.ssh /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
```

Append your public key to `authorized_keys`, preserving any existing keys.
For root SSH with a key, review `/etc/ssh/sshd_config` and included files so
these settings take effect:

```text
PubkeyAuthentication yes
PermitRootLogin prohibit-password
```

`prohibit-password` allows root key authentication while disabling root password
and keyboard-interactive login. Keep the Android root shell available during
setup. Check effective settings with `/usr/sbin/sshd -T`, then validate and test
in the foreground. [OpenSSH settings](https://man.openbsd.org/sshd_config#PermitRootLogin).

```sh
/usr/sbin/sshd -t
/usr/sbin/sshd -D -e
```

From a **second host terminal**: `ssh root@PHONE_IP`. Test `id`, network
access, and `touch ~/write-test && rm ~/write-test`. Return to the foreground
SSHD terminal and press Ctrl-C before handing SSH to runit. A daemon left on
port 22 will conflict with the supervised instance.

## Troubleshooting: Required key not available

The historical OnePlus setup encountered Android fscrypt access failures after
PAM ran `pam_keyinit.so force revoke`. This is a diagnosis for that symptom,
not a reason to remove PAM generally. Keep a working Android root shell open.

Inspect `/etc/pam.d/` for active `pam_keyinit.so` session lines. Back up the
specific affected files, then comment those keyring-changing lines if they
reproduce the problem. Preserve the authentication/account modules. The earlier
setup also used `UsePAM no` for SSH; that disables PAM account/session processing
as well, so review the implications for your login policy and run `sshd -t`.

With all Debian services and login sessions stopped, exit to **Android root**:

```sh
chroot-distro unmount debian-trixie
chroot-distro login debian-trixie
```

Retest root shell and SSH file writes. Do not force-unmount an active printing
stack. If the symptom persists, inspect the actual mount/keyring state instead
of broadly deleting authentication configuration.

Continue with [boot-script installation](boot-services.md), then
[add your own runit services](../services/runit.md).
