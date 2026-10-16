# Root-owned configuration, sourced by Magisk late_start scripts.
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
# Realtek Ethernet, CP210x, CH340. Add the printer's actual VID:PID as needed.
USB_KEEP_AWAKE_IDS='0bda:8153 10c4:ea60 1a86:7523'
# Opt in only after qualifying reverse-current blocking AND rail voltage.
ENABLE_CHARGING_INHIBIT=0
CHARGING_HARDWARE_QUALIFIED=0
