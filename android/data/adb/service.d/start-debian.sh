#!/system/bin/sh
# Edit these two values if your chroot installation differs.
DISTRO=debian-trixie
CHROOT_DISTRO=/system/bin/chroot-distro

umask 077
exec >/data/local/tmp/start-debian.log 2>&1
remaining=90
while [ "$(/system/bin/getprop sys.boot_completed)" != 1 ]; do
    [ "$remaining" -gt 0 ] || { echo 'Android boot timed out'; exit 1; }
    sleep 2
    remaining=$((remaining - 1))
done

# One mount attempt, then one supervisor. Do not restart the printer stack here.
echo "Mounting $DISTRO"
timeout -k 5 60 "$CHROOT_DISTRO" mount "$DISTRO" || {
    echo 'Mount failed; inspect the chroot before trying again'
    exit 1
}
echo 'Starting runit; manage individual services with sv inside Debian'
exec "$CHROOT_DISTRO" command "$DISTRO" /usr/local/bin/start-services
