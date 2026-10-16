#!/system/bin/sh
# Magisk runs this once per boot. Use "adb shell", then "su", for root.
umask 077
exec >/data/local/tmp/enable-tcp-adb.log 2>&1

# Give Android up to three minutes to boot.
remaining=90
while [ "$(/system/bin/getprop sys.boot_completed)" != 1 ]; do
    [ "$remaining" -gt 0 ] || { echo 'Android boot timed out'; exit 1; }
    sleep 2
    remaining=$((remaining - 1))
done

[ "$(/system/bin/getprop ro.adb.secure)" = 1 ] || {
    echo 'Expected authenticated ADB; leaving adbd unchanged'
    exit 1
}
[ -z "$(/system/bin/getprop service.adb.listen_addrs)" ] || {
    echo 'service.adb.listen_addrs overrides the TCP port; inspect that setting'
    exit 1
}
if [ "$(/system/bin/getprop service.adb.tcp.port)" = 5555 ] &&
   [ "$(/system/bin/getprop init.svc.adbd)" = running ]; then
    echo 'ADB is already configured for TCP 5555'
    exit 0
fi

# This per-boot property does not change ADB authentication or USB configuration.
/system/bin/setprop service.adb.tcp.port 5555 || exit 1
/system/bin/setprop ctl.restart adbd || exit 1
echo 'Requested ADB on TCP 5555; verify with adb connect PHONE_IP:5555'
