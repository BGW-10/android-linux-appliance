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

# Android still owns CPU scaling, thermal protection, and charging safety.
/system/bin/cmd deviceidle disable || echo 'Could not disable Doze'
/system/bin/cmd power set-mode 0 || echo 'Could not disable Battery Saver'
/system/bin/settings put global low_power_trigger_level 0 || echo 'Could not change Battery Saver threshold'
echo 'Checking selected USB devices and Wi-Fi every 30 seconds'

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
    if [ "$DISABLE_WIFI_POWER_SAVE" = 1 ] && [ -x /system/bin/iw ] &&
       [ -d "/sys/class/net/$WIFI_INTERFACE" ]; then
        /system/bin/iw dev "$WIFI_INTERFACE" set power_save off >/dev/null 2>&1 ||
            /system/bin/log -p w -t appliance-tuning 'Could not disable Wi-Fi power saving'
    fi
    sleep 30
done
