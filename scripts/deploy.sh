#!/usr/bin/env bash
# Host deployment wrapper for Linux, macOS, and WSL2.
#
# Stages android/, debian/, and scripts/install-on-device.sh into /data/local/tmp
# via ADB (USB or TCP), then invokes install-on-device.sh as root via `su`
# because adbd runs as the unprivileged `shell` user. Cleans up both local and
# device staging directories on exit.
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)

ADB_BIN=${ADB:-}
SERIAL=
TARGET=
INSTALL_ARGS=()

usage() {
    cat <<'EOF'
Usage: deploy.sh [options]

Options:
  -s, --serial SERIAL       ADB device serial (USB serial or HOST:PORT)
  -t, --target HOST[:PORT]  Connect via TCP ADB first (default port: 5555)
      --adb PATH            Path to adb executable (e.g. adb.exe from WSL2)
      --debian-root PATH    Debian rootfs path (default: /data/local/chroot-distro/debian-trixie)
      --dry-run             Print files and permissions without modifying the device
  -h, --help                Show this help

Examples:
  ./scripts/deploy.sh --dry-run
  ./scripts/deploy.sh -t 192.168.1.50:5555
  ./scripts/deploy.sh -s ABC123456 --adb adb.exe
EOF
}

# Restrict forwarded path/name arguments to safe characters before embedding in
# the remote `su -c` shell command.
validate_safe_arg() {
    if [[ ! "$2" =~ ^[A-Za-z0-9._:/-]+$ ]]; then
        echo "Invalid characters in $1: $2" >&2
        exit 2
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -s|--serial)
            [[ $# -ge 2 ]] || { echo "Missing value for $1" >&2; exit 2; }
            SERIAL=$2
            shift
            ;;
        -t|--target)
            [[ $# -ge 2 ]] || { echo "Missing value for $1" >&2; exit 2; }
            TARGET=$2
            shift
            ;;
        --adb)
            [[ $# -ge 2 ]] || { echo "Missing value for $1" >&2; exit 2; }
            ADB_BIN=$2
            shift
            ;;
        --debian-root)
            [[ $# -ge 2 ]] || { echo "Missing value for $1" >&2; exit 2; }
            validate_safe_arg "$1" "$2"
            INSTALL_ARGS+=("$1" "$2")
            shift
            ;;
        --dry-run)
            INSTALL_ARGS+=("$1")
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

count_ready_devices() {
    "$1" devices 2>/dev/null | awk 'NR > 1 && $2 == "device" { count++ } END { print count + 0 }'
}

if [[ -z "$ADB_BIN" ]]; then
    if command -v adb >/dev/null 2>&1; then
        ADB_BIN=adb
        # In WSL2, USB devices usually belong to Windows adb.exe unless attached
        # via usbipd; fall back automatically when no explicit target/serial is set.
        if [[ -z "$TARGET" && -z "$SERIAL" ]] &&
           grep -qi microsoft /proc/version 2>/dev/null &&
           command -v adb.exe >/dev/null 2>&1 &&
           [[ "$(count_ready_devices adb)" -eq 0 ]] &&
           [[ "$(count_ready_devices adb.exe)" -gt 0 ]]; then
            echo 'No devices on WSL adb; using Windows adb.exe'
            ADB_BIN=adb.exe
        fi
    elif command -v adb.exe >/dev/null 2>&1; then
        ADB_BIN=adb.exe
    else
        echo 'adb not found on PATH (pass --adb PATH if needed)' >&2
        exit 1
    fi
fi

if [[ -n "$TARGET" ]]; then
    [[ "$TARGET" == *:* ]] || TARGET="$TARGET:5555"
    "$ADB_BIN" connect "$TARGET"
    SERIAL=$TARGET
fi

adb_cmd() {
    if [[ -n "$SERIAL" ]]; then
        "$ADB_BIN" -s "$SERIAL" "$@"
    else
        "$ADB_BIN" "$@"
    fi
}

state=$(adb_cmd get-state 2>/dev/null | tr -d '\r' || true)
if [[ "$state" != device ]]; then
    echo "ADB device not ready (state: ${state:-none}). Pass -s SERIAL or -t HOST[:PORT]." >&2
    "$ADB_BIN" devices -l >&2 || true
    exit 1
fi

su_id=$(adb_cmd shell "su -c id" 2>/dev/null | tr -d '\r' || true)
if [[ "$su_id" != *"uid=0(root)"* ]]; then
    echo "Root access via 'su' failed (got: ${su_id:-empty}). Check Magisk authorization." >&2
    exit 1
fi

local_stage=$(mktemp -d)
remote_stage="/data/local/tmp/appliance-deploy-$$"

cleanup() {
    rm -rf "$local_stage"
    adb_cmd shell "rm -rf '$remote_stage'" >/dev/null 2>&1 || true
}
trap cleanup EXIT

cp -a "$REPO_ROOT/android" "$local_stage/android"
cp -a "$REPO_ROOT/debian" "$local_stage/debian"
cp "$SCRIPT_DIR/install-on-device.sh" "$local_stage/install-on-device.sh"

# Convert the staging directory path when calling Windows adb.exe from WSL2.
push_src=$local_stage
if [[ "$ADB_BIN" == *.exe ]] && command -v wslpath >/dev/null 2>&1; then
    push_src=$(wslpath -w "$local_stage")
fi

adb_cmd push "$push_src" "$remote_stage" >/dev/null

remote_cmd="sh '$remote_stage/install-on-device.sh'"
for arg in ${INSTALL_ARGS[@]+"${INSTALL_ARGS[@]}"}; do
    remote_cmd+=" '$arg'"
done

adb_cmd shell "su -c \"$remote_cmd\""
