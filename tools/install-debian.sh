#!/bin/sh
# Run inside Debian with the checkout accessible. Does not restart services.
set -eu
[ "$(id -u)" = 0 ] || { echo 'Run as root inside Debian.' >&2; exit 1; }
REPO=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
for tool in runsvdir runsv sv svlogd flock; do command -v "$tool" >/dev/null; done
backup="/var/backups/appliance/$(date +%Y%m%dT%H%M%S)-$$"
mkdir -p "$backup" /etc/default /usr/local/bin /etc/sv/sshd/log
for path in usr/local/bin/start-services etc/sv/sshd/run etc/sv/sshd/log/run etc/sv/sshd/log/config; do
    mkdir -p "$backup/$(dirname "$path")"
    [ ! -e "/$path" ] || cp -p "/$path" "$backup/$path"
    install -o root -g root -m 755 "$REPO/debian/$path" "/$path.new"
    mv -f "/$path.new" "/$path"
done
chmod 644 /etc/sv/sshd/log/config
if [ ! -f /etc/default/appliance-services ]; then
    install -o root -g root -m 600 "$REPO/debian/etc/default/appliance-services" /etc/default/appliance-services
fi
printf 'Installed files. Backup: %s\n' "$backup"
printf 'Choose one SSH definition (ssh OR sshd). No links changed; no services restarted.\n'
