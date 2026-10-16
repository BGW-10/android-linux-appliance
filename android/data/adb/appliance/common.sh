#!/system/bin/sh
# Sourced by service.d scripts. Keep shared Android helpers here.

# Give Android up to three minutes to boot. The subshell keeps variables local.
wait_for_android_boot() (
    remaining=90
    while [ "$(/system/bin/getprop sys.boot_completed)" != 1 ]; do
        [ "$remaining" -gt 0 ] || { echo 'Android boot timed out'; return 1; }
        sleep 2
        remaining=$((remaining - 1))
    done
)
