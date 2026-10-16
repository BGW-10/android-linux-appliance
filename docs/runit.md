# Adding and managing runit services

[Documentation index](README.md) · [Installation](mona-appliance.md)

Run these commands **inside Debian as root**. Runit watches `/etc/service`;
service definitions live in `/etc/sv`. An enabled service is simply a symlink
between them. Android's boot scripts stay the same when you add a service.

## A service is an executable run file

Run `mkdir -p /etc/sv/my-service`, then create `/etc/sv/my-service/run`:

```sh
#!/bin/sh
set -eu
exec 2>&1
cd /path/to/application
exec /path/to/program --foreground
```

Replace the paths and foreground option with the application's actual command.
Use `exec` so runit signals the application directly. Let runit restart the
process; keep shell backgrounding (`&`), `nohup`, and daemon mode out of `run`.

```sh
chmod 755 /etc/sv/my-service/run
mkdir -p /etc/service
ln -s /etc/sv/my-service /etc/service/my-service
# Discovery can take about five seconds.
sv status /etc/service/my-service
```

Runit starts it and restarts it if it exits. To link it **without starting it**,
create `/etc/sv/my-service/down` before making the link, then use `sv up` when
ready. Remove `down` when it should also start on future boots.
[How runsvdir discovers services](https://smarden.org/runit/runsvdir.8).

## Daily commands

```sh
sv status /etc/service/*
sv up /etc/service/my-service
sv -w 20 down /etc/service/my-service
sv -w 20 restart /etc/service/my-service
```

`down` stops the service for the current supervision session. To keep it down
across reboots:

```sh
touch /etc/sv/my-service/down
sv -w 20 down /etc/service/my-service
```

To enable startup again, remove `down` and run `sv up`. To remove a service
entirely from supervision, first stop it successfully, then remove its
`/etc/service/my-service` symlink. Keep the definition in `/etc/sv` for later.
[Runit service control](https://smarden.org/runit/runsv.8).

## Logging

An executable `log/run` alongside `run` gives the service a supervised logger.
Run `mkdir -p /etc/sv/my-service/log`, then create its `run` file:

```sh
#!/bin/sh
set -eu
umask 027
logdir=/var/log/my-service
mkdir -p "$logdir"
printf 's1048576\nn5\n' > "$logdir/config"
exec /usr/bin/svlogd -tt "$logdir"
```

Make it executable before enabling the service. This keeps about 1 MiB per file
and five old files. Read the current output with
`tail -f /var/log/my-service/current`. `exec 2>&1` in the application `run` file
sends errors there too. See the supplied SSH service for a working example.
[svlogd documentation](https://smarden.org/runit/svlogd.8).

## Klipper and Moonraker examples

The [example directories](../examples/runit/) contain ordinary `run` and
`log/run` files. They assume:

- A Debian user/group named `klipper`, with home `/home/klipper`.
- Source checkouts at `~/klipper` and `~/moonraker`.
- Virtualenvs at `~/klippy-env` and `~/moonraker-env`, with dependencies installed.
- The user's writable `~/printer_data/{config,comms,logs,gcodes}` directories,
  and existing, reviewed `printer.cfg` and `moonraker.conf` files.

These files launch existing installations; prepare the applications and account
first. Adjust paths and the `chpst` user/group list to your actual setup.
For example, to stage Klipper without starting it:

```sh
repo=/path/to/klipper-android-appliance-scripts
cp -a "$repo/examples/runit/klipper" /etc/sv/
touch /etc/sv/klipper/down
# Edit /etc/sv/klipper/run now.
chmod 755 /etc/sv/klipper/run /etc/sv/klipper/log/run
ln -s /etc/sv/klipper /etc/service/klipper
# When configured, with the printer idle and heaters off:
sv up /etc/service/klipper
sv status /etc/service/klipper
# Once verified, enable it for future boots:
rm /etc/sv/klipper/down
```

Repeat with `moonraker` using its example. Watch `/var/log/klipper/current` and
`/var/log/moonraker/current` for startup errors. Application logs remain in
`~/printer_data/logs/` for normal Klipper/Moonraker diagnostics; monitor their
size separately from the bounded runit logs.

### Users, groups, and the serial device

`chpst -u` clears inherited supplementary groups. The examples explicitly list
`klipper`, `dialout` for Klipper, and `aid_inet` for Android networking. Check
these exist with `getent group`; `aid_inet` must map to Android GID 3003. If that
GID already has another name, use that name. Match serial access to the actual
Android device-node owner/group (`ls -ln /dev/ttyUSB*`), which may differ from
Debian's `dialout`. The scripts do not change device permissions or SELinux.
[chpst group handling](https://smarden.org/runit/chpst.8).

### Moonraker without systemd

Merge this snippet into the existing `moonraker.conf`, preserving your other
settings, including authentication:

```ini
[server]
klippy_uds_address: /home/klipper/printer_data/comms/klippy.sock

[machine]
provider: none
validate_service: False
```

The socket matches Klipper's `-a` argument. Moonraker reconnects when Klipper
becomes available; there is no custom startup-order wrapper. Runit service
start/stop/restart buttons are not provided by Moonraker's `none` provider;
use `sv` over SSH or ADB. The web application's service/update workflows may
assume systemd, so initially perform application updates manually while idle.
[Klipper API socket](https://www.klipper3d.org/API_Server.html),
[Moonraker machine configuration](https://moonraker.readthedocs.io/en/latest/configuration/#machine),
[Moonraker installation and command line](https://moonraker.readthedocs.io/en/latest/installation/).

## Keeping the phone awake

`start-services` takes the named `klipper-appliance` kernel wake lock, then uses
`flock` to allow one launcher and starts `runsvdir`. A write failure to the wake
lock stops startup. There are no custom PID records or shutdown traps.

The wake lock deliberately lasts until reboot or an explicit release, including
when individual services are stopped. This keeps the dedicated appliance awake
and uses more power. For maintenance, stop all services from an **ADB/local
shell** (this includes SSH), verify they stopped, then release the lock:

```sh
sv -w 20 down /etc/service/*
# Only after successful shutdown and confirming the printer is idle:
printf 'klipper-appliance\n' > /sys/power/wake_unlock
```

Before starting services again, reacquire it:
`printf 'klipper-appliance\n' > /sys/power/wake_lock`. Normally leave the
supervisor running and control individual services with `sv`. If the supervisor
unexpectedly dies, inspect `ps` and `sv status` for surviving `runsv` processes;
resolve those before starting another supervisor, or do an attended reboot.
The file lock prevents duplicate launches through this script, not an unrelated
legacy launcher. Reboot is the simplest migration from the older framework.
