# How the appliance works

[Documentation index](README.md)

Both phones run Android and Debian on the **same Linux kernel**. Debian is a
root chroot, with native ARM64 processes; it is not a VM or CPU emulator.
The boot scripts and Debian services run as root; application files live in
Debian's `/root`.

```text
Phone hardware
└── Android/LineageOS kernel
    ├── Android: display, Wi-Fi, USB roles, charging, thermal policy, SELinux
    │   └── Magisk service.d: ADB, tuning, chroot startup
    └── Debian chroot
        └── runsvdir /etc/service
            ├── runsv → sshd
            └── runsv → each service you add
```

| Component | Responsibility |
| --- | --- |
| Device kernel | Hardware drivers, scheduling, USB serial nodes, power and thermal interfaces. |
| Magisk | Root access, systemless binary overlay, and late-start boot scripts. |
| Termux | Convenient Android maintenance shell; not the Debian service supervisor. |
| chroot-distro | Root filesystem and `/dev`, `/proc`, `/sys`, `/dev/pts` mounts. |
| Debian | Packages, root SSH access, Python environments, and printer applications. |
| runit | Keep each enabled foreground process running and optionally rotate its output. |

The rootfs is normally under `/data/local/chroot-distro/debian-trixie/` on
Android. Inside the chroot it appears as `/`. A path visible to Android is not
automatically visible in Debian. Copy/clone this repository into each environment
as the installation guide describes instead of assuming shared `/data` paths.

Debian does not boot its own PID 1. Use `sv`, not `systemctl`, for these services.
The launcher takes `klipper-appliance` through `/sys/power/wake_lock`; this
prevents suspend while leaving CPU frequency scaling and the display independent.
It persists until reboot or manual release. Disabling Doze alone is insufficient.

Android permissions still apply to Debian processes, including root. Some
installations need GID 3003 for networking; check access to the actual USB serial
node and diagnose SELinux denials if they occur.
Encrypted Android storage can also interact with PAM keyring changes. See
[Debian setup](setup/debian.md) for symptom-based diagnosis.

A larger heatsink can improve sustained stock performance, but it does not fix
supply droop or missing drivers. Battery capacity overrides, charging policy,
and physical supply protection solve different problems; see the Mona guides
before combining them.
