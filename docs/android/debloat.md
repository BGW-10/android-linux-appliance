# Reversible Android package trimming

[Documentation index](../README.md)

Disable only packages whose role you understand and record each change.
Package names vary by ROM/device; this is optional appliance tuning, not a
prerequisite for Debian or Klipper.

In an **Android root shell**, replace `PACKAGE_NAME` with one reviewed package:

```sh
pm list packages -d --user 0
pm disable-user --user 0 PACKAGE_NAME
# Restore that package for the same Android user:
pm enable --user 0 PACKAGE_NAME
```

Recheck network, USB, display, and login behavior after each small group of
changes. Do not disable Android's framework, SystemUI, NetworkStack, thermal,
charging, or hardware-provider services to gain RAM.

To inspect memory in the same shell:

```sh
dumpsys meminfo
ps -A -o PID,USER,RSS,NAME
```

Android's `ps` options differ from GNU `ps`; inspect `ps --help` before using
host-only sorting flags. A lower RAM figure alone is not proof of better
printer timing or less power use.

## Historical OnePlus 5 package list

The earlier LineageOS notes recorded these disabled packages. Review them
individually; do not apply the list wholesale to Mona or another ROM.

| Package | Function |
| --- | --- |
| `org.mozilla.firefox` | Firefox |
| `de.marmaro.krt.ffupdater` | FFUpdater |
| `org.fdroid.fdroid` | F-Droid |
| `com.stevesoltys.seedvault` | Backup |
| `com.android.nfc` | NFC |
| `com.android.deskclock` | Clock |
| `org.lineageos.audiofx` | Audio effects |
| `com.android.dialer` | Dialer |
| `com.android.messaging` | Messaging |

Disabling an updater or backup package also removes that maintenance function.
Keep a deliberate update/backup route for an always-on host.
