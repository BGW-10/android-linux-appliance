#!/system/bin/sh
# Optional Mona-only experiment. Read docs/mona-appliance.md before enabling.
ENABLE_CHARGING_INHIBIT=0
CHARGING_HARDWARE_QUALIFIED=0
[ "$ENABLE_CHARGING_INHIBIT" = 1 ] || exit 0
[ "$CHARGING_HARDWARE_QUALIFIED" = 1 ] || exit 1
[ "$(/system/bin/getprop ro.product.device)" = mona ] || exit 1

umask 077
exec >/data/local/tmp/charging-inhibit.log 2>&1
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
