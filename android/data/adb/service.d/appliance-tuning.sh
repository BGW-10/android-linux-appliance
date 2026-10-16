#!/system/bin/sh
# Edit these values for your devices: Realtek Ethernet, CP210x, CH340.
USB_IDS='0bda:8153 10c4:ea60 1a86:7523'
WIFI_INTERFACE=wlan0
DISABLE_WIFI_POWER_SAVE=1

# Only one copy of this small USB/Wi-Fi monitor should run.
umask 077
exec 9>/data/local/tmp/appliance-tuning.lock
flock -n 9 || exit 0
exec >/data/local/tmp/appliance-tuning.log 2>&1
# shellcheck source=../appliance/common.sh
. /data/adb/appliance/common.sh || exit 1
wait_for_android_boot || exit 1

disable_wifi_power_save() {
    [ -d "/sys/class/net/$WIFI_INTERFACE" ] || return 1
    if ! /system/bin/iw dev "$WIFI_INTERFACE" set power_save off >/dev/null 2>&1; then
        echo "WARNING: Could not disable Wi-Fi power saving on $WIFI_INTERFACE"
        return 1
    fi

    state=$(/system/bin/iw dev "$WIFI_INTERFACE" get power_save 2>/dev/null)
    case "$state" in
        *'Power save: off'*) echo "Wi-Fi power save disabled on $WIFI_INTERFACE" ;;
        *) echo "WARNING: Wi-Fi power save state: ${state:-unknown}"; return 1 ;;
    esac
}

# Android still owns CPU scaling, thermal protection, and charging safety.
/system/bin/cmd deviceidle disable || echo 'Could not disable Doze'
/system/bin/cmd power set-mode 0 || echo 'Could not disable Battery Saver'
/system/bin/settings put global low_power_trigger_level 0 || echo 'Could not change Battery Saver threshold'

# Apply once, then reapply after link-up events as in the original monitor.
if [ "$DISABLE_WIFI_POWER_SAVE" = 1 ]; then
    if [ -x /system/bin/iw ]; then
        disable_wifi_power_save
        if [ -x /system/bin/ip ]; then
            (
                while true; do
                    echo "Starting $WIFI_INTERFACE link monitor"
                    /system/bin/ip monitor link dev "$WIFI_INTERFACE" |
                    while IFS= read -r event; do
                        case "$event" in
                            *'state UP'*)
                                echo "$WIFI_INTERFACE reached state UP; checking Wi-Fi power save"
                                sleep 2
                                disable_wifi_power_save
                                ;;
                        esac
                    done
                    echo 'Wi-Fi link monitor exited; restarting in 5 seconds'
                    sleep 5
                done
            ) &
        else
            echo 'WARNING: /system/bin/ip missing; Wi-Fi link monitoring unavailable'
        fi
    else
        echo 'WARNING: /system/bin/iw missing; Wi-Fi power saving left unchanged'
    fi
fi

echo 'Checking selected USB devices every 30 seconds'
while true; do
    for device in /sys/bus/usb/devices/*; do
        [ -r "$device/idVendor" ] && [ -r "$device/idProduct" ] || continue
        id="$(cat "$device/idVendor"):$(cat "$device/idProduct")"
        case " $USB_IDS " in *" $id "*) ;; *) continue ;; esac
        [ -w "$device/power/control" ] || continue
        [ "$(cat "$device/power/control")" = auto ] || continue
        printf 'on\n' > "$device/power/control" ||
            /system/bin/log -p w -t appliance-tuning "Could not keep USB $id awake"
    done
    sleep 30
done
