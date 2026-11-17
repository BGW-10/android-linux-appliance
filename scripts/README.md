# Host Deployment Scripts

These scripts mirror the repository's `android/` and `debian/` trees onto a
rooted Android device over ADB (USB or TCP) and apply the expected ownership and
file permissions.

## Files

| Script | Role |
| --- | --- |
| `deploy.sh` | Host wrapper for Linux, macOS, and WSL2 (auto-falls back to Windows `adb.exe` when WSL has no USB device). |
| `deploy.ps1` | Host wrapper for Windows PowerShell 5.1+ and PowerShell 7+. |
| `install-on-device.sh` | On-device POSIX `sh` installer pushed to `/data/local/tmp` and executed as `root` via `su`. |

## Prerequisites

- Authorized ADB connection over USB (`adb devices`) or TCP (`PHONE_IP:5555`).
- Magisk root (`su` grants `uid=0(root)`).
- Existing Debian chroot directory on Android (default:
  `/data/local/chroot-distro/debian-trixie`).
- Phone unlocked at least once after boot so `/data` is decrypted.
- LF line endings on shell scripts (enforced by `.gitattributes`).

## Usage

Preview destination paths and permissions first with `--dry-run` / `-DryRun`:

```sh
# Linux / macOS / WSL2 (connected USB device)
./scripts/deploy.sh --dry-run
./scripts/deploy.sh

# TCP ADB (defaults to port 5555)
./scripts/deploy.sh -t PHONE_IP

# Custom ADB binary or Debian chroot path
./scripts/deploy.sh -s SERIAL --adb adb.exe --debian-root /data/local/chroot-distro/debian-trixie
```

```powershell
# Windows PowerShell (connected USB device)
.\scripts\deploy.ps1 -DryRun
.\scripts\deploy.ps1

# TCP ADB (defaults to port 5555)
.\scripts\deploy.ps1 -Target PHONE_IP

# PowerShell built-in help
Get-Help .\scripts\deploy.ps1 -Full
```

## Destination and Permission Mapping

All installed files are written atomically (`.new` + `mv -f`) with `chown 0:0`.
Placeholder `.gitkeep` files are skipped, and `klipper/` configs are left
untouched.

| Repository path | Device destination | Mode |
| --- | --- | --- |
| `android/data/adb/appliance/*` | `/data/adb/appliance/*` | `600` |
| `android/data/adb/service.d/*` | `/data/adb/service.d/*` | `700` |
| `android/data/adb/modules/*/system/bin/*` | `/data/adb/modules/*/system/bin/*` | `755` |
| Other files under `android/` (e.g. `module.prop`) | `/...` | `644` |
| `debian/usr/local/bin/*`, `debian/etc/sv/*/run`, `debian/etc/sv/*/log/run`, `debian/**/*.sh` | `$DEBIAN_ROOT/...` | `755` |
| Other files under `debian/` | `$DEBIAN_ROOT/...` | `644` |

## Notes

- **First-time `sshd` setup:** `install-on-device.sh` copies `/etc/sv/sshd` into
  the Debian rootfs, but does not create `/etc/service/sshd` automatically. See
  [boot-services.md](../docs/setup/boot-services.md#1-prepare-debian) to switch
  from packaged `ssh` to runit `sshd`.
- **Disabled `service.d` scripts:** Mirroring sets `service.d/*` to mode `700`.
  If you intentionally disabled a boot script with `chmod 600` on the phone,
  re-apply `chmod 600` after mirroring (or edit the script settings).
- **Printer safety:** Mirroring files does not reboot the phone or restart
  running services; reboot or restart services with `sv` only while idle with
  heaters off.
