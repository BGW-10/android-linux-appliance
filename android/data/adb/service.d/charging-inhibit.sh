#!/system/bin/sh
# Mona only. Read docs/devices/mona/usb-power.md before enabling.
ENABLE_CHARGING_INHIBIT=0
CHARGING_HARDWARE_QUALIFIED=0
[ "$ENABLE_CHARGING_INHIBIT" = 1 ] || exit 0

umask 077
exec >/data/local/tmp/charging-inhibit.log 2>&1
[ "$CHARGING_HARDWARE_QUALIFIED" = 1 ] || {
    echo 'Qualify the power hardware before enabling charging inhibition'
    exit 1
}
[ "$(/system/bin/getprop ro.product.device)" = mona ] || {
    echo 'Charging inhibition is supported here only on Mona'
    exit 1
}

# Request inhibition as soon as this control exists; do not wait for full boot.
charger=/sys/class/power_supply/battery/device
remaining=60
while [ ! -w "$charger/force_charging_disable" ]; do
    [ "$remaining" -gt 0 ] || { echo 'Charging control unavailable'; exit 1; }
    sleep 2
    remaining=$((remaining - 1))
done
[ "$(cat "$charger/force_charging_enable")" = 0 ] || {
    echo 'Conflicting or unreadable forced-charging state'
    exit 1
}
# One request; this does not monitor USB events or prove firmware enforcement.
printf '1\n' > "$charger/force_charging_disable" || exit 1
echo 'Charging disable requested; measure current direction and rail voltage'
