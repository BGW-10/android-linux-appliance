#!/system/bin/sh
. "${APPLIANCE_HOME:-/data/adb/appliance}/common.sh"
app_init enable-tcp-adb || exit 1
[ "$ADB_TCP_ENABLED" = 1 ] || exit 0
app_lock || exit 0
app_wait_boot || exit 1

adb_listening() {
    # 5555 = 0x15B3; 0A = LISTEN. Android may use an IPv6 wildcard socket.
    awk '$2 ~ /:15B3$/ && $4 == "0A" {found=1} END {exit !found}' \
        "$APPLIANCE_PROC/net/tcp" "$APPLIANCE_PROC/net/tcp6" 2>/dev/null
}

if [ "$("$ANDROID_BIN/getprop" ro.adb.secure)" != 1 ]; then
    app_log 'ERROR: expected authenticated ADB (ro.adb.secure=1); leaving ADB unchanged'
    exit 1
fi
if [ -n "$("$ANDROID_BIN/getprop" service.adb.listen_addrs)" ]; then
    app_log 'ERROR: service.adb.listen_addrs overrides the port; inspect its owner'
    exit 1
fi
if [ "$("$ANDROID_BIN/getprop" service.adb.tcp.port)" = 5555 ] &&
   [ "$("$ANDROID_BIN/getprop" init.svc.adbd)" = running ] && adb_listening; then
    app_log 'Authenticated ADB already listening on TCP 5555; no restart needed'
    exit 0
fi

# A per-boot property keeps rollback simple. Do not change authentication,
# root-adbd policy, USB gadget composition, or authorized host keys.
if ! "$ANDROID_BIN/setprop" service.adb.tcp.port 5555 ||
   [ "$("$ANDROID_BIN/getprop" service.adb.tcp.port)" != 5555 ]; then
    app_log 'ERROR: failed to set service.adb.tcp.port'
    exit 1
fi
app_log 'Restarting adbd once for TCP 5555; existing ADB sessions may disconnect'
"$ANDROID_BIN/setprop" ctl.restart adbd || exit 1
attempt=0
while [ "$attempt" -lt 15 ]; do
    if [ "$("$ANDROID_BIN/getprop" init.svc.adbd)" = running ] && adb_listening; then
        app_log 'ADB running with TCP 5555 listener; verify from an authorized host'
        exit 0
    fi
    sleep 2
    attempt=$((attempt + 1))
done
app_log 'ERROR: TCP 5555 listener did not appear; no further restarts attempted'
exit 1
