#!/system/bin/sh
. "${APPLIANCE_HOME:-/data/adb/appliance}/common.sh"
app_init start-debian || exit 1
[ "$ENABLE_DEBIAN" = 1 ] || exit 0
app_lock || exit 0
app_wait_boot || exit 1
if [ ! -x "$CHROOT_DISTRO" ]; then
    app_log "ERROR: chroot-distro unavailable at $CHROOT_DISTRO"
    exit 1
fi
# Retry only before launch. Never unmount or restart an active printing stack.
attempt=1
mounted=0
while [ "$attempt" -le 3 ]; do
    app_log "Mounting $DISTRO (attempt $attempt/3)"
    if app_run_logged timeout -k 5 "$MOUNT_TIMEOUT_SECONDS" "$CHROOT_DISTRO" mount "$DISTRO"; then
        mounted=1
        break
    fi
    app_log 'ERROR: mount failed or timed out'
    [ "$attempt" -eq 3 ] || sleep "$((attempt * 5))"
    attempt=$((attempt + 1))
done
[ "$mounted" = 1 ] || exit 1
app_log 'Starting Debian supervisor; it owns the appliance wake lock'
app_run_logged "$CHROOT_DISTRO" command "$DISTRO" /usr/local/bin/start-services
rc=$?
app_log "Debian supervisor command exited ($rc); inspect services before restarting"
exit "$rc"
