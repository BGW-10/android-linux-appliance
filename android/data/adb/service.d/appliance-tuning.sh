#!/system/bin/sh
. "${APPLIANCE_HOME:-/data/adb/appliance}/common.sh"
app_init appliance-tuning || exit 1
BASELINE="$APPLIANCE_HOME/tuning-baseline"
STOP="$APP_RUN/tuning.stop"
case "${1:-}" in
    --stop) touch "$STOP"; exit 0 ;;
    --restore)
        touch "$STOP"
        exec 9>"$APP_RUN/$APP_NAME.lock"
        # Magisk BusyBox flock has no -w option; bound nonblocking retries.
        remaining=$((POLL_SECONDS + 10))
        until flock -n 9; do
            [ "$remaining" -gt 0 ] || exit 1
            sleep 1
            remaining=$((remaining - 1))
        done
        ;;
    ''|--once)
        [ "$ENABLE_TUNING" = 1 ] || exit 0
        app_lock || exit 0
        rm -f "$STOP"
        ;;
    *) echo 'Usage: appliance-tuning.sh [--once|--stop|--restore]' >&2; exit 2 ;;
esac
app_wait_boot || exit 1
mkdir -p "$BASELINE/usb"
save_value() {
    # Keep the first observed value until an explicit operator reset.
    [ -f "$BASELINE/$1" ] || printf '%s\n' "$2" > "$BASELINE/$1"
}
restore() {
    for mode in deep light; do
        [ -f "$BASELINE/doze-$mode" ] || continue
        case "$(cat "$BASELINE/doze-$mode")" in
            1) action=enable ;; 0) action=disable ;; *) continue ;;
        esac
        app_run_logged "$ANDROID_BIN/cmd" deviceidle "$action" "$mode" || return 1
    done
    if [ -f "$BASELINE/low_power" ]; then
        app_run_logged "$ANDROID_BIN/cmd" power set-mode "$(cat "$BASELINE/low_power")" || return 1
    fi
    if [ -f "$BASELINE/low_power_trigger_level" ]; then
        value=$(cat "$BASELINE/low_power_trigger_level")
        if [ "$value" = null ]; then
            app_run_logged "$ANDROID_BIN/settings" delete global low_power_trigger_level || return 1
        else
            app_run_logged "$ANDROID_BIN/settings" put global low_power_trigger_level "$value" || return 1
        fi
    fi
    if [ -f "$BASELINE/wifi-$WIFI_INTERFACE" ]; then
        app_run_logged "$ANDROID_BIN/iw" dev "$WIFI_INTERFACE" set power_save \
            "$(cat "$BASELINE/wifi-$WIFI_INTERFACE")" || return 1
    fi
    for record in "$BASELINE"/usb/*; do
        [ -d "$record" ] || continue
        device="$APPLIANCE_SYS/bus/usb/devices/${record##*/}"
        [ "$(app_read "$device/idVendor"):$(app_read "$device/idProduct")" = "$(cat "$record/id")" ] || continue
        cat "$record/control" > "$device/power/control" || return 1
    done
    app_log 'Saved tuning settings restored; baseline retained for review'
}
if [ "${1:-}" = --restore ]; then restore; exit "$?"; fi
for mode in deep light; do
    value=$("$ANDROID_BIN/cmd" deviceidle enabled "$mode" 2>/dev/null)
    case "$value" in
        0|1)
            save_value "doze-$mode" "$value"
            if app_run_logged "$ANDROID_BIN/cmd" deviceidle disable "$mode"; then
                app_log "Doze $mode disabled"
            else app_log "ERROR: could not disable Doze $mode"; fi
            ;;
        *) app_log "WARNING: cannot read Doze $mode state; leaving it unchanged" ;;
    esac
done
value=$("$ANDROID_BIN/settings" get global low_power)
case "$value" in
    0|1)
        save_value low_power "$value"
        if app_run_logged "$ANDROID_BIN/cmd" power set-mode 0; then
            app_log 'Battery Saver disabled'
        else app_log 'ERROR: could not disable Battery Saver'; fi
        ;;
    *) app_log 'WARNING: cannot read Battery Saver state; leaving it unchanged' ;;
esac
value=$("$ANDROID_BIN/settings" get global low_power_trigger_level)
case "$value" in
    null|0|[1-9]|[1-9][0-9]|100)
        save_value low_power_trigger_level "$value"
        app_run_logged "$ANDROID_BIN/settings" put global low_power_trigger_level 0 ||
            app_log 'ERROR: could not disable automatic Battery Saver threshold'
        ;;
    *) app_log 'WARNING: unexpected low-power threshold; leaving it unchanged' ;;
esac
tune_devices() {
    for device in "$APPLIANCE_SYS"/bus/usb/devices/*; do
        [ -r "$device/idVendor" ] && [ -r "$device/idProduct" ] || continue
        usb_id="$(cat "$device/idVendor"):$(cat "$device/idProduct")"
        case " $USB_KEEP_AWAKE_IDS " in *" $usb_id "*) ;; *) continue ;; esac
        [ -w "$device/power/control" ] || continue
        value=$(cat "$device/power/control")
        [ "$value" = auto ] || continue
        record="$BASELINE/usb/${device##*/}"
        if [ ! -f "$record/id" ] || [ "$(cat "$record/id")" != "$usb_id" ]; then
            mkdir -p "$record"
            printf '%s\n' "$usb_id" > "$record/id"
            printf '%s\n' "$value" > "$record/control"
        fi
        if printf 'on\n' > "$device/power/control"; then
            app_log "Disabled autosuspend for USB $usb_id (${device##*/})"
        else app_log "ERROR: USB power/control write failed for $usb_id"; fi
    done
    if [ "$DISABLE_WIFI_POWER_SAVE" = 1 ] && [ -x "$ANDROID_BIN/iw" ] &&
       [ -d "$APPLIANCE_SYS/class/net/$WIFI_INTERFACE" ]; then
        value=$("$ANDROID_BIN/iw" dev "$WIFI_INTERFACE" get power_save 2>/dev/null)
        case "$value" in
            *'Power save: on'*) value=on ;;
            *'Power save: off'*) value=off ;;
            *) return ;;
        esac
        save_value "wifi-$WIFI_INTERFACE" "$value"
        [ "$value" = on ] || return 0
        if app_run_logged "$ANDROID_BIN/iw" dev "$WIFI_INTERFACE" set power_save off; then
            app_log "Disabled Wi-Fi power saving on $WIFI_INTERFACE"
        else app_log 'ERROR: Wi-Fi power-save write failed'; fi
    fi
}
trap 'exit 0' TERM INT HUP
while [ ! -e "$STOP" ]; do
    tune_devices
    [ "${1:-}" != --once ] || break
    sleep "$POLL_SECONDS" &
    wait "$!"
done
app_log 'Tuning monitor stopped; use --restore to restore saved settings'
