#!/usr/bin/env python3
"""Cross-platform ADB deployment script for Linux, macOS, WSL2, and Windows.

Requires only the Python 3.8+ standard library.

Workflow:
  1. Walk `android/` and `debian/` locally, skipping `.gitkeep` placeholders,
     assigning target destinations and octal modes, and rejecting CRLF line
     endings on shell scripts before touching the device.
  2. With `--dry-run`, print the resolved plan and exit without requiring ADB.
  3. Otherwise, verify an authorized ADB connection and Magisk `su` root
     access (`adbd` runs as unprivileged `shell`, so `adb push` cannot write
     directly into `/data/adb` or the Debian chroot).
  4. Stage the files alongside a minimal generated POSIX `sh` installer into
     `/data/local/tmp`, execute it once via `su -c` to perform atomic `.new` +
     `mv -f` replacements with `chown 0:0`, and clean up both staging dirs.

Prerequisites:
  - Phone unlocked at least once after boot so `/data` is decrypted.
  - Existing Debian chroot directory on Android (default:
    `/data/local/chroot-distro/debian-trixie`).
  - Magisk root (`su`) and authorized USB or TCP ADB.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from fnmatch import fnmatchcase
import os
from pathlib import Path, PurePosixPath
import shlex
import shutil
import subprocess
import sys
import tempfile

DEFAULT_DEBIAN_ROOT = "/data/local/chroot-distro/debian-trixie"


@dataclass(frozen=True)
class InstallEntry:
    """Single file scheduled to be mirrored onto the device."""

    src: Path
    stage_rel: PurePosixPath
    dest: PurePosixPath
    mode: str
    require_lf: bool


def android_rule(rel: str) -> tuple[str, bool]:
    """Return `(mode, require_lf)` for a path relative to `android/`."""
    if fnmatchcase(rel, "data/adb/service.d/*"):
        return "700", True
    if fnmatchcase(rel, "data/adb/appliance/*"):
        return "600", True
    if fnmatchcase(rel, "data/adb/modules/*/system/bin/*"):
        # Compiled ELF binaries may live here; do not reject `\r` bytes.
        return "755", False
    return "644", False


def debian_rule(rel: str) -> tuple[str, bool]:
    """Return `(mode, require_lf)` for a path relative to `debian/`."""
    if (
        fnmatchcase(rel, "usr/local/bin/*")
        or fnmatchcase(rel, "etc/sv/*/run")
        or fnmatchcase(rel, "etc/sv/*/log/run")
        or fnmatchcase(rel, "*.sh")
    ):
        return "755", True
    return "644", False


def collect_install_plan(repo_root: Path, debian_root: str) -> list[InstallEntry]:
    """Build a sorted install plan and verify LF endings on shell scripts."""
    entries: list[InstallEntry] = []
    specs = [
        ("android", repo_root / "android", PurePosixPath("/"), android_rule),
        ("debian", repo_root / "debian", PurePosixPath(debian_root), debian_rule),
    ]
    for tree_name, tree_dir, dest_root, rule_fn in specs:
        if not tree_dir.is_dir():
            raise FileNotFoundError(f"Missing directory: {tree_dir}")
        files = sorted(
            (p for p in tree_dir.rglob("*") if p.is_file() and p.name != ".gitkeep"),
            key=lambda p: p.relative_to(tree_dir).as_posix(),
        )
        for src in files:
            rel = src.relative_to(tree_dir).as_posix()
            mode, require_lf = rule_fn(rel)
            if require_lf and b"\r" in src.read_bytes():
                raise ValueError(f"CRLF line endings detected in {src}; use LF before deploying")
            entries.append(
                InstallEntry(
                    src=src,
                    stage_rel=PurePosixPath(tree_name) / rel,
                    dest=dest_root / rel,
                    mode=mode,
                    require_lf=require_lf,
                )
            )
    return entries


def build_device_installer(entries: list[InstallEntry], debian_root: str) -> str:
    """Generate the temporary `/system/bin/sh` root installer run on Android.

    Generating one flat list of `install_file` calls keeps on-device shell
    logic minimal, avoids `find`/word-splitting edge cases, and completes all
    copies inside a single `su -c` invocation.
    """
    lines = [
        "#!/system/bin/sh",
        "set -eu",
        'STAGE_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)',
        f"DEBIAN_ROOT={shlex.quote(debian_root)}",
        '[ "$(id -u)" -eq 0 ] || { echo "Installer must run as root" >&2; exit 1; }',
        '[ -d "$DEBIAN_ROOT" ] || {',
        '    echo "Debian rootfs not found: $DEBIAN_ROOT (pass --debian-root PATH if different)" >&2',
        "    exit 1",
        "}",
        # Replace destination files atomically via .new + mv -f as root:root.
        "install_file() {",
        '    src="$STAGE_DIR/$1"',
        '    dst="$2"',
        '    mode="$3"',
        '    mkdir -p "$(dirname "$dst")"',
        '    cp "$src" "$dst.new"',
        '    chmod "$mode" "$dst.new"',
        '    chown 0:0 "$dst.new"',
        '    mv -f "$dst.new" "$dst"',
        '    echo "$dst (mode $mode)"',
        "}",
    ]
    for entry in entries:
        lines.append(
            "install_file "
            f"{shlex.quote(entry.stage_rel.as_posix())} "
            f"{shlex.quote(entry.dest.as_posix())} "
            f"{shlex.quote(entry.mode)}"
        )
    return "\n".join(lines) + "\n"


def is_wsl() -> bool:
    """Return True when running inside Windows Subsystem for Linux."""
    try:
        return "microsoft" in Path("/proc/version").read_text(encoding="utf-8", errors="ignore").lower()
    except OSError:
        return False


def count_ready_devices(adb_bin: str) -> int:
    """Count ADB targets currently in the `device` (authorized) state."""
    try:
        proc = subprocess.run(
            [adb_bin, "devices"],
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError:
        return 0
    if proc.returncode != 0:
        return 0
    lines = proc.stdout.splitlines()[1:]
    return sum(1 for line in lines if len(line.split()) >= 2 and line.split()[1] == "device")


def resolve_adb(explicit_adb: str | None, has_explicit_target: bool) -> str:
    """Pick the `adb` binary, falling back to `adb.exe` on WSL2 if needed."""
    candidate = explicit_adb or os.environ.get("ADB")
    if candidate:
        if shutil.which(candidate) or Path(candidate).is_file():
            return candidate
        print(f"adb executable not found: {candidate}", file=sys.stderr)
        sys.exit(1)

    if shutil.which("adb"):
        # In WSL2, USB devices usually belong to Windows adb.exe unless
        # attached via usbipd; fall back automatically when no explicit
        # target/serial is set.
        if (
            not has_explicit_target
            and is_wsl()
            and count_ready_devices("adb") == 0
            and shutil.which("adb.exe")
            and count_ready_devices("adb.exe") > 0
        ):
            print("No devices on WSL adb; using Windows adb.exe")
            return "adb.exe"
        return "adb"

    if shutil.which("adb.exe"):
        return "adb.exe"

    print("adb not found on PATH (pass --adb PATH if needed)", file=sys.stderr)
    sys.exit(1)


def run_adb(
    adb_bin: str,
    serial: str | None,
    args: list[str],
    *,
    capture: bool = False,
) -> subprocess.CompletedProcess[str]:
    """Invoke `adb` (targeting `serial` when set) with the given arguments."""
    cmd = [adb_bin]
    if serial:
        cmd.extend(["-s", serial])
    cmd.extend(args)
    return subprocess.run(cmd, capture_output=capture, text=True, check=False)


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Mirror android/ and debian/ onto a rooted Android device over ADB.",
        epilog=(
            "Examples:\n"
            "  python3 scripts/deploy.py --dry-run\n"
            "  python3 scripts/deploy.py -t 192.168.1.50:5555\n"
            "  python3 scripts/deploy.py -s ABC123456 --adb adb.exe\n"
            "  py scripts\\deploy.py --dry-run          (Windows)"
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "-s",
        "--serial",
        help="ADB device serial (USB serial or HOST:PORT)",
    )
    parser.add_argument(
        "-t",
        "--target",
        metavar="HOST[:PORT]",
        help="Connect via TCP ADB first (default port: 5555)",
    )
    parser.add_argument(
        "--adb",
        metavar="PATH",
        help="Path to adb executable (or set ADB env var; e.g. adb.exe from WSL2)",
    )
    parser.add_argument(
        "--debian-root",
        default=DEFAULT_DEBIAN_ROOT,
        metavar="PATH",
        help=f"Debian rootfs path on device (default: {DEFAULT_DEBIAN_ROOT})",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print destination paths and permissions locally without touching the device",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)

    if not args.debian_root.startswith("/") or any(c in args.debian_root for c in "\r\n\0"):
        print(f"--debian-root must be an absolute POSIX path: {args.debian_root}", file=sys.stderr)
        return 2

    repo_root = Path(__file__).resolve().parent.parent
    try:
        entries = collect_install_plan(repo_root, args.debian_root)
    except (FileNotFoundError, ValueError) as exc:
        print(exc, file=sys.stderr)
        return 1

    if args.dry_run:
        for entry in entries:
            print(f"[dry-run] {entry.dest.as_posix()} (mode {entry.mode})")
        return 0

    adb_bin = resolve_adb(args.adb, bool(args.target or args.serial))

    serial = args.serial
    if args.target:
        target = args.target if ":" in args.target else f"{args.target}:5555"
        conn = subprocess.run([adb_bin, "connect", target], check=False)
        if conn.returncode != 0:
            return conn.returncode
        serial = target

    state_proc = run_adb(adb_bin, serial, ["get-state"], capture=True)
    state = state_proc.stdout.strip()
    if state_proc.returncode != 0 or state != "device":
        print(
            f"ADB device not ready (state: {state or 'none'}). Pass -s SERIAL or -t HOST[:PORT].",
            file=sys.stderr,
        )
        subprocess.run([adb_bin, "devices", "-l"], stdout=sys.stderr, check=False)
        return 1

    su_proc = run_adb(adb_bin, serial, ["shell", "su -c id"], capture=True)
    su_id = su_proc.stdout.strip()
    if "uid=0(root)" not in su_id:
        print(
            f"Root access via 'su' failed (got: {su_id or 'empty'}). Check Magisk authorization.",
            file=sys.stderr,
        )
        return 1

    remote_stage = f"/data/local/tmp/appliance-deploy-{os.getpid()}"
    installer_script = build_device_installer(entries, args.debian_root)

    with tempfile.TemporaryDirectory(prefix="appliance-deploy-") as tmpdir:
        local_stage = Path(tmpdir)
        for entry in entries:
            staged_file = local_stage / entry.stage_rel
            staged_file.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(entry.src, staged_file)
        (local_stage / "install.sh").write_text(installer_script, encoding="utf-8", newline="\n")

        push_src = str(local_stage)
        # Convert the WSL temp path to a Windows path when invoking Windows adb.exe.
        if adb_bin.lower().endswith(".exe") and is_wsl() and shutil.which("wslpath"):
            wslpath_proc = subprocess.run(
                ["wslpath", "-w", push_src],
                capture_output=True,
                text=True,
                check=True,
            )
            push_src = wslpath_proc.stdout.strip()

        try:
            push_proc = run_adb(adb_bin, serial, ["push", push_src, remote_stage], capture=True)
            if push_proc.returncode != 0:
                detail = (push_proc.stderr or push_proc.stdout or "").strip()
                if detail:
                    print(detail, file=sys.stderr)
                print("adb push failed", file=sys.stderr)
                return push_proc.returncode

            remote_cmd = f"sh {shlex.quote(remote_stage + '/install.sh')}"
            exec_proc = run_adb(adb_bin, serial, ["shell", f"su -c {shlex.quote(remote_cmd)}"])
            return exec_proc.returncode
        finally:
            run_adb(adb_bin, serial, ["shell", f"rm -rf {shlex.quote(remote_stage)}"], capture=True)


if __name__ == "__main__":
    sys.exit(main())
