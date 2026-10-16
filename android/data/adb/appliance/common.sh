#!/system/bin/sh
# shellcheck disable=SC2034
# Configuration variables are consumed by the scripts sourcing this library.
# Explicit Android command paths bypass Magisk's BusyBox standalone applets.
APPLIANCE_HOME=${APPLIANCE_HOME:-/data/adb/appliance}
ANDROID_BIN=${ANDROID_BIN:-/system/bin}
APPLIANCE_SYS=${APPLIANCE_SYS:-/sys}
APPLIANCE_PROC=${APPLIANCE_PROC:-/proc}
ADB_TCP_ENABLED=1
ENABLE_DEBIAN=1
ENABLE_TUNING=1
DISTRO=debian-trixie
CHROOT_DISTRO=/system/bin/chroot-distro
BOOT_WAIT_SECONDS=180
MOUNT_TIMEOUT_SECONDS=60
POLL_SECONDS=30
WIFI_INTERFACE=wlan0
DISABLE_WIFI_POWER_SAVE=1
USB_KEEP_AWAKE_IDS='0bda:8153 10c4:ea60 1a86:7523'
ENABLE_CHARGING_INHIBIT=0
CHARGING_HARDWARE_QUALIFIED=0
[ ! -f "$APPLIANCE_HOME/config.sh" ] || . "$APPLIANCE_HOME/config.sh"

app_init() {
    umask 077
    APP_NAME=$1
    APP_LOG="$APPLIANCE_HOME/log/$APP_NAME.log"
    APP_RUN="$APPLIANCE_HOME/run/$(cat "$APPLIANCE_PROC/sys/kernel/random/boot_id")"
    mkdir -p "$APPLIANCE_HOME/log" "$APP_RUN" || return 1
    for app_number in "$BOOT_WAIT_SECONDS" "$MOUNT_TIMEOUT_SECONDS" "$POLL_SECONDS"; do
        case "$app_number" in ''|*[!0-9]*) return 1 ;; esac
        [ "$app_number" -ge 1 ] && [ "$app_number" -le 3600 ] || return 1
    done
}

app_log() {
    # Reopen for each message so rotation leaves no writer on an old inode.
    if [ -f "$APP_LOG" ] && [ "$(wc -c < "$APP_LOG")" -ge 65536 ]; then
        mv -f "$APP_LOG" "$APP_LOG.1"
    fi
    printf '%s %.2048s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >> "$APP_LOG"
}

app_lock() {
    exec 9>"$APP_RUN/$APP_NAME.lock"
    flock -n 9
}

app_wait_boot() {
    app_elapsed=0
    while [ "$app_elapsed" -lt "$BOOT_WAIT_SECONDS" ]; do
        [ "$("$ANDROID_BIN/getprop" sys.boot_completed)" = 1 ] && return 0
        sleep 2
        app_elapsed=$((app_elapsed + 2))
    done
    app_log "ERROR: Android boot readiness timed out after $BOOT_WAIT_SECONDS seconds"
    return 1
}

app_run_logged() {
    # Preserve the command status, not the exit code of the log reader.
    app_result=$(mktemp "$APP_RUN/result.XXXXXX") || return 1
    (
        "$@" 9>&- 2>&1
        printf '%s\n' "$?" > "$app_result"
    ) | while IFS= read -r app_line || [ -n "$app_line" ]; do
        app_log "$app_line"
    done
    app_rc=$(cat "$app_result")
    rm -f "$app_result"
    case "$app_rc" in ''|*[!0-9]*) return 1 ;; esac
    return "$app_rc"
}

app_read() {
    if [ -r "$1" ]; then cat "$1"; else printf 'unavailable\n'; fi
}
