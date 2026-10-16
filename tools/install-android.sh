#!/system/bin/sh
# Run on Android as root from an extracted checkout. Does not start services.
set -eu
[ "$(id -u)" = 0 ] || { echo 'Run as root on Android.' >&2; exit 1; }
REPO=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
case "${1:-}" in
    --adb-only) scripts=enable-tcp-adb.sh ;;
    --all) scripts='enable-tcp-adb.sh appliance-tuning.sh start-debian.sh charging-inhibit.sh' ;;
    *) echo 'Usage: install-android.sh --adb-only|--all' >&2; exit 2 ;;
esac
[ -x /data/adb/magisk/busybox ] || { echo 'Magisk BusyBox is required.' >&2; exit 1; }
umask 077
backup="/data/adb/appliance/backups/$(date +%Y%m%dT%H%M%S)-$$"
mkdir -p "$backup" /data/adb/appliance /data/adb/service.d
install_file() {
    source=$1 destination=$2 mode=$3
    [ ! -e "$destination" ] || cp -p "$destination" "$backup/${destination##*/}"
    cp "$source" "$destination.new"
    chown 0:0 "$destination.new"
    chmod "$mode" "$destination.new"
    mv -f "$destination.new" "$destination"
}
install_file "$REPO/android/data/adb/appliance/common.sh" /data/adb/appliance/common.sh 600
if [ ! -f /data/adb/appliance/config.sh ]; then
    install_file "$REPO/android/data/adb/appliance/config.sh" /data/adb/appliance/config.sh 600
fi
for script in $scripts; do
    install_file "$REPO/android/data/adb/service.d/$script" "/data/adb/service.d/$script" 755
done
printf 'Installed %s. Backup: %s\n' "$scripts" "$backup"
printf 'No services started. Review /data/adb/appliance/config.sh before reboot.\n'
