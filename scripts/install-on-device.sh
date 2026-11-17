#!/system/bin/sh
# On-device installer run as root on Android (typically pushed to /data/local/tmp
# by scripts/deploy.sh or scripts/deploy.ps1).
#
# Mirrors staged android/ and debian/ trees directly onto the device filesystem:
#   android/ -> /           (appliance/* 600, service.d/* 700, modules/*/system/bin/* 755, other 644)
#   debian/  -> DEBIAN_ROOT (executables/scripts 755, other 644)
#
# Placeholder .gitkeep files are skipped. Does not mount or enter the chroot;
# Debian's rootfs directory is written directly from Android root, so /data must
# already be decrypted (phone unlocked after boot) and the chroot must exist.
set -eu

STAGE_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DEBIAN_ROOT=/data/local/chroot-distro/debian-trixie
DRY_RUN=0

usage() {
    cat <<'EOF'
Usage: install-on-device.sh [options]
  --debian-root PATH      Debian rootfs path (default: /data/local/chroot-distro/debian-trixie)
  --dry-run               Print destination paths and modes without modifying files
  -h, --help              Show this help
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --debian-root)
            [ "$#" -ge 2 ] || { echo 'Missing value for --debian-root' >&2; exit 2; }
            DEBIAN_ROOT=$2
            shift
            ;;
        --dry-run)
            DRY_RUN=1
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

[ "$(id -u)" -eq 0 ] || { echo 'install-on-device.sh must run as root' >&2; exit 1; }
[ -d "$STAGE_DIR/android" ] || { echo "Missing $STAGE_DIR/android" >&2; exit 1; }
[ -d "$STAGE_DIR/debian" ] || { echo "Missing $STAGE_DIR/debian" >&2; exit 1; }
[ -d "$DEBIAN_ROOT" ] || {
    echo "Debian rootfs not found: $DEBIAN_ROOT (pass --debian-root PATH if different)" >&2
    exit 1
}

# Reject CRLF on shell/text scripts so BusyBox ash and /bin/sh never fail on \r.
# Do not run this on compiled ELF binaries (e.g. Magisk module system/bin/*).
check_lf() {
    if [ "$(tr -cd '\r' < "$1" | wc -c)" -ne 0 ]; then
        echo "CRLF line endings detected in $1; use LF before deploying" >&2
        exit 1
    fi
}

# Replace destination files atomically via .new + mv -f with root:root ownership.
copy_file() {
    src=$1
    dst=$2
    mode=$3

    if [ "$DRY_RUN" = 1 ]; then
        echo "[dry-run] $dst (mode $mode)"
        return 0
    fi

    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst.new"
    chmod "$mode" "$dst.new"
    chown 0:0 "$dst.new"
    mv -f "$dst.new" "$dst"
    echo "$dst (mode $mode)"
}

for src in $(find "$STAGE_DIR/android" -type f | sort); do
    rel=${src#"$STAGE_DIR/android/"}
    case "$(basename "$rel")" in
        .gitkeep) continue ;;
    esac
    case "$rel" in
        data/adb/service.d/*)
            check_lf "$src"
            mode=700
            ;;
        data/adb/appliance/*)
            check_lf "$src"
            mode=600
            ;;
        data/adb/modules/*/system/bin/*)
            mode=755
            ;;
        *)
            mode=644
            ;;
    esac
    copy_file "$src" "/$rel" "$mode"
done

for src in $(find "$STAGE_DIR/debian" -type f | sort); do
    rel=${src#"$STAGE_DIR/debian/"}
    case "$(basename "$rel")" in
        .gitkeep) continue ;;
    esac
    case "$rel" in
        usr/local/bin/*|etc/sv/*/run|etc/sv/*/log/run|*.sh)
            check_lf "$src"
            mode=755
            ;;
        *)
            mode=644
            ;;
    esac
    copy_file "$src" "$DEBIAN_ROOT/$rel" "$mode"
done
