# Adding and managing runit services

[Documentation index](../README.md) · [Installation](../setup/boot-services.md)

Run these commands **inside Debian as root**. Runit watches `/etc/service`;
service definitions live in `/etc/sv`. An enabled service is simply a symlink
between them. Android's boot scripts stay the same when you add a service.
Services inherit root and `HOME=/root` from the launcher. Install each
application and verify its foreground command before enabling supervision.

## A service is an executable run file

Run `mkdir -p /etc/sv/my-service`, then create `/etc/sv/my-service/run`:

```sh
#!/bin/sh
set -eu
exec 2>&1
cd /root/my-application
exec /root/my-application/program --foreground
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

## Check device access

For a service using USB serial, inspect `/dev/ttyUSB*` and `/dev/ttyACM*` in
Android and Debian after connecting the adapter. The chroot uses the same
kernel device nodes. Confirm the adapter identity and driver binding before
choosing a path; Android may not create `/dev/serial/by-id/` symlinks.
Recheck after reconnecting multiple devices. Root processes still need SELinux
access; diagnose denials instead of disabling enforcement.

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
