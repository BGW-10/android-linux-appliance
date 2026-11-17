# Host Deployment Script

[`deploy.py`](deploy.py) mirrors the repository's `android/` and `debian/` trees
onto a rooted Android device over ADB (USB or TCP) and applies the expected
ownership and file permissions.

## Prerequisites

- Python 3.8+ on the host (uses only the Python standard library).
- Authorized ADB connection over USB (`adb devices`) or TCP (`PHONE_IP:5555`).
- Magisk root (`su` grants `uid=0(root)`).
- Existing Debian chroot directory on Android (default:
  `/data/local/chroot-distro/debian-trixie`).
- Phone unlocked at least once after boot so `/data` is decrypted.
- LF line endings on shell scripts (enforced by `.gitattributes`).

## Usage

Preview destination paths and permissions locally with `--dry-run` (does not
require a connected device):

```sh
# Linux / macOS / WSL2
python3 scripts/deploy.py --dry-run
python3 scripts/deploy.py

# TCP ADB (defaults to port 5555)
python3 scripts/deploy.py -t PHONE_IP

# Custom ADB binary or Debian chroot path
python3 scripts/deploy.py -s SERIAL --adb adb.exe --debian-root /data/local/chroot-distro/debian-trixie
```

```powershell
# Windows (PowerShell or Command Prompt)
py scripts\deploy.py --dry-run
py scripts\deploy.py -t PHONE_IP
```

In WSL2, `deploy.py` automatically falls back to Windows `adb.exe` when Linux
`adb` has no ready devices. Run `python3 scripts/deploy.py --help` (or
`py scripts\deploy.py --help` on Windows) for all options.

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

- **First-time `sshd` setup:** `deploy.py` copies `/etc/sv/sshd` into the Debian
  rootfs, but does not create `/etc/service/sshd` automatically. See
  [boot-services.md](../docs/setup/boot-services.md#1-prepare-debian) to switch
  from packaged `ssh` to runit `sshd`.
- **Disabled `service.d` scripts:** Mirroring sets `service.d/*` to mode `700`.
  If you intentionally disabled a boot script with `chmod 600` on the phone,
  re-apply `chmod 600` after mirroring (or edit the script settings).
- **Printer safety:** Mirroring files does not reboot the phone or restart
  running services; reboot or restart services with `sv` only while idle with
  heaters off.
