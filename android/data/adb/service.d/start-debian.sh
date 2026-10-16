#!/system/bin/sh
# Edit these two values if your chroot installation differs.
DISTRO=debian-trixie
CHROOT_DISTRO=/system/bin/chroot-distro

umask 077
exec >/data/local/tmp/start-debian.log 2>&1
# shellcheck source=../appliance/common.sh
. /data/adb/appliance/common.sh || exit 1
wait_for_android_boot || exit 1

# One mount attempt, then one supervisor. Do not restart the printer stack here.
echo "Mounting $DISTRO"
timeout -k 5 60 "$CHROOT_DISTRO" mount "$DISTRO" || {
    echo 'Mount failed; inspect the chroot before trying again'
    exit 1
}
echo 'Starting runit; manage individual services with sv inside Debian'
exec "$CHROOT_DISTRO" command "$DISTRO" /usr/local/bin/start-services
