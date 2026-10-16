#!/system/bin/sh
. "${APPLIANCE_HOME:-/data/adb/appliance}/common.sh"
app_init charging-inhibit || exit 1
case "${1:-}" in
    --stop) touch "$APP_RUN/charging.stop"; exit 0 ;;
    ''|--once) ;;
    *) echo 'Usage: charging-inhibit.sh [--once|--stop]' >&2; exit 2 ;;
esac
[ "$ENABLE_CHARGING_INHIBIT" = 1 ] || exit 0
app_lock || exit 0
rm -f "$APP_RUN/charging.stop"
if [ "$CHARGING_HARDWARE_QUALIFIED" != 1 ] ||
   [ "$("$ANDROID_BIN/getprop" ro.product.device)" != mona ]; then
    app_log 'ERROR: charging inhibit requires Mona and qualified hardware protection'
    exit 1
fi
CHARGER="$APPLIANCE_SYS/class/power_supply/battery/device"
attempt=0
# Do not wait for Android boot completion; apply once the driver appears.
while [ ! -w "$CHARGER/force_charging_disable" ] && [ "$attempt" -lt 60 ]; do
    sleep 2
    attempt=$((attempt + 1))
done
if [ ! -w "$CHARGER/force_charging_disable" ]; then
    app_log 'ERROR: Motorola charging-disable node did not appear'
    exit 1
fi
previous=
trap 'exit 0' TERM INT HUP
while [ ! -e "$APP_RUN/charging.stop" ]; do
    forced=$(app_read "$CHARGER/force_charging_enable")
    if [ "$forced" != 0 ]; then
        app_log "ERROR: conflicting or unavailable forced-charging state ($forced)"
        exit 1
    fi
    if ! printf '1\n' > "$CHARGER/force_charging_disable"; then
        app_log 'ERROR: charging-disable request failed; hardware protection is required'
        exit 1
    fi
    sample="status=$(app_read "$APPLIANCE_SYS/class/power_supply/battery/status") voltage_uv=$(app_read "$APPLIANCE_SYS/class/power_supply/battery/voltage_now") current_ua=$(app_read "$APPLIANCE_SYS/class/power_supply/battery/current_now") usb_online=$(app_read "$APPLIANCE_SYS/class/power_supply/usb/online") role=$(app_read "$APPLIANCE_SYS/class/typec/port0/power_role")"
    if [ "$sample" != "$previous" ]; then
        app_log "Disable requested, NOT electrically verified: $sample"
        previous=$sample
    fi
    [ "${1:-}" != --once ] || break
    # Recheck attach/recovery on the next poll. Same-value writes may be cached;
    # never toggle charging on to refresh, or clear the write-only vote on exit.
    sleep "$POLL_SECONDS" &
    wait "$!"
done
