"""Host-side failure-path tests; temporary fake Android interfaces, real runit.

Run: python3 -m unittest discover -s tests -v
Place runsvdir, runsv and sv in PATH for the Debian integration tests.
"""
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
ANDROID = ROOT / 'android/data/adb'
SUPERVISOR = ROOT / 'debian/usr/local/bin/start-services'
STUB = r'''#!/usr/bin/env python3
import json, os, pathlib, sys
p = pathlib.Path(os.environ['FIXTURE'])
s = json.loads((p / 'state.json').read_text())
a = sys.argv[1:]
name = pathlib.Path(sys.argv[0]).name
with (p / 'calls').open('a') as f:
    f.write(name + ' ' + ' '.join(a) + '\n')
if name == 'sleep':
    sys.exit(0)
if name == 'getprop':
    print(s['props'].get(a[0], ''))
elif name == 'setprop':
    if s.get('fail_setprop'): sys.exit(1)
    s['props'][a[0]] = a[1]
    if a == ['ctl.restart', 'adbd']:
        s['props']['init.svc.adbd'] = 'running'
        if not s.get('no_listener'):
            (p / 'proc/net/tcp6').write_text('0: 0000000000000000:15B3 0000:0000 0A\n')
elif name == 'cmd':
    if s.get('fail_cmd'): sys.exit(1)
    if a[:2] == ['deviceidle', 'enabled']: print(s[a[2]])
    elif a[0] == 'deviceidle': s[a[2]] = 1 if a[1] == 'enable' else 0
    elif a[:2] == ['power', 'set-mode']: s['settings']['low_power'] = a[2]
elif name == 'settings':
    if a[0] == 'get': print(s['settings'].get(a[2], 'null'))
    elif a[0] == 'put': s['settings'][a[2]] = a[3]
    elif a[0] == 'delete': s['settings'].pop(a[2], None)
elif name == 'iw':
    if a[2] == 'get': print('Power save: ' + s['wifi'])
    else: s['wifi'] = a[4]
elif name == 'chroot-distro':
    if a[0] == 'mount' and s.get('mount_fails'): sys.exit(7)
    if a[0] == 'command' and s.get('command_fails'): sys.exit(8)
(p / 'state.json').write_text(json.dumps(s))
'''


class AndroidTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.p = Path(self.tmp.name)
        self.home = self.p / 'home'
        self.home.mkdir()
        shutil.copy(ANDROID / 'appliance/common.sh', self.home)
        (self.p / 'bin').mkdir()
        for name in ('getprop', 'setprop', 'cmd', 'settings', 'iw', 'sleep', 'chroot-distro'):
            f = self.p / 'bin' / name
            f.write_text(STUB)
            f.chmod(0o755)
        for name in ('net/tcp', 'net/tcp6', 'sys/kernel/random/boot_id'):
            f = self.p / 'proc' / name
            f.parent.mkdir(parents=True, exist_ok=True)
            f.write_text('test-boot\n' if name.endswith('boot_id') else '')
        self.state = {'props': {'sys.boot_completed': '1', 'ro.adb.secure': '1',
                               'init.svc.adbd': 'running', 'ro.product.device': 'mona'},
                      'settings': {'low_power': '1', 'low_power_trigger_level': '15'},
                      'deep': 1, 'light': 0, 'wifi': 'on'}
        self.save()
        self.env = dict(os.environ, FIXTURE=str(self.p), APPLIANCE_HOME=str(self.home),
                        ANDROID_BIN=str(self.p / 'bin'), APPLIANCE_PROC=str(self.p / 'proc'),
                        APPLIANCE_SYS=str(self.p / 'sys'),
                        PATH=str(self.p / 'bin') + ':' + os.environ['PATH'])
        self.config()

    def config(self, extra=''):
        (self.home / 'config.sh').write_text(
            f'BOOT_WAIT_SECONDS=2\nPOLL_SECONDS=1\nCHROOT_DISTRO={self.p}/bin/chroot-distro\n' + extra)

    def save(self):
        (self.p / 'state.json').write_text(json.dumps(self.state))

    def load(self):
        return json.loads((self.p / 'state.json').read_text())

    def calls(self):
        f = self.p / 'calls'
        return f.read_text() if f.exists() else ''

    def run_script(self, name, *args):
        return subprocess.run(['sh', str(ANDROID / 'service.d' / name), *args],
                              env=self.env, capture_output=True, text=True, timeout=10)

    def node(self, path, value):
        f = self.p / 'sys' / path
        f.parent.mkdir(parents=True, exist_ok=True)
        f.write_text(value + '\n')
        return f

    def test_adb_enable_and_idempotence(self):
        self.assertEqual(self.run_script('enable-tcp-adb.sh').returncode, 0)
        self.assertEqual(self.run_script('enable-tcp-adb.sh').returncode, 0)
        self.assertEqual(self.calls().count('setprop ctl.restart adbd'), 1)
        self.assertEqual(self.load()['props']['service.adb.tcp.port'], '5555')
        self.assertNotIn('persist.adb', self.calls())
        self.assertNotIn('setprop ro.', self.calls())

    def test_adb_refuses_insecure_or_override(self):
        for prop, value in [('ro.adb.secure', '0'), ('service.adb.listen_addrs', 'tcp:7777')]:
            with self.subTest(prop=prop):
                original = self.state['props'].copy()
                self.state['props'][prop] = value
                self.save()
                self.assertNotEqual(self.run_script('enable-tcp-adb.sh').returncode, 0)
                self.assertNotIn('setprop ', self.calls())
                self.state['props'] = original

    def test_adb_boot_timeout_and_disabled(self):
        self.state['props']['sys.boot_completed'] = '0'
        self.save()
        self.assertNotEqual(self.run_script('enable-tcp-adb.sh').returncode, 0)
        self.assertNotIn('setprop ', self.calls())
        self.config('ADB_TCP_ENABLED=0\n')
        self.assertEqual(self.run_script('enable-tcp-adb.sh').returncode, 0)

    def test_adb_property_failure_never_restarts(self):
        self.state['fail_setprop'] = True
        self.save()
        self.assertNotEqual(self.run_script('enable-tcp-adb.sh').returncode, 0)
        self.assertNotIn('ctl.restart', self.calls())

    def test_adb_listener_failure_only_one_restart(self):
        self.state['no_listener'] = True
        self.save()
        self.assertNotEqual(self.run_script('enable-tcp-adb.sh').returncode, 0)
        self.assertEqual(self.calls().count('ctl.restart'), 1)

    def test_failed_mount_never_launches_debian(self):
        self.state['mount_fails'] = True
        self.save()
        self.assertNotEqual(self.run_script('start-debian.sh').returncode, 0)
        self.assertEqual(self.calls().count('chroot-distro mount'), 3)
        self.assertNotIn('chroot-distro command', self.calls())

    def test_supervisor_failure_is_propagated_without_retry(self):
        self.state['command_fails'] = True
        self.save()
        self.assertEqual(self.run_script('start-debian.sh').returncode, 8)
        self.assertEqual(self.calls().count('chroot-distro command'), 1)

    def test_tuning_restore_and_selective_usb(self):
        selected = self.node('bus/usb/devices/1-1/power/control', 'auto')
        self.node('bus/usb/devices/1-1/idVendor', '10c4')
        self.node('bus/usb/devices/1-1/idProduct', 'ea60')
        other = self.node('bus/usb/devices/1-2/power/control', 'auto')
        self.node('bus/usb/devices/1-2/idVendor', '1234')
        self.node('bus/usb/devices/1-2/idProduct', '5678')
        (self.p / 'sys/class/net/wlan0').mkdir(parents=True)
        for _ in range(2):
            r = self.run_script('appliance-tuning.sh', '--once')
            self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(selected.read_text().strip(), 'on')
        self.assertEqual(other.read_text().strip(), 'auto')
        self.assertEqual(self.load()['wifi'], 'off')
        r = self.run_script('appliance-tuning.sh', '--restore')
        self.assertEqual(r.returncode, 0, r.stderr)
        restored = self.load()
        self.assertEqual((restored['deep'], restored['light']), (1, 0))
        self.assertEqual(restored['settings'], self.state['settings'])
        self.assertEqual(restored['wifi'], 'on')
        self.assertEqual(selected.read_text().strip(), 'auto')

    def test_charging_opt_in_conflict_and_no_release(self):
        inhibit = self.node('class/power_supply/battery/device/force_charging_disable', 'untouched')
        forced = self.node('class/power_supply/battery/device/force_charging_enable', '0')
        self.assertEqual(self.run_script('charging-inhibit.sh', '--once').returncode, 0)
        self.assertEqual(inhibit.read_text().strip(), 'untouched')
        self.config('ENABLE_CHARGING_INHIBIT=1\n')
        self.assertNotEqual(self.run_script('charging-inhibit.sh', '--once').returncode, 0)
        self.assertEqual(inhibit.read_text().strip(), 'untouched')
        self.config('ENABLE_CHARGING_INHIBIT=1\nCHARGING_HARDWARE_QUALIFIED=1\n')
        forced.write_text('1\n')
        self.assertNotEqual(self.run_script('charging-inhibit.sh', '--once').returncode, 0)
        self.assertEqual(inhibit.read_text().strip(), 'untouched')
        forced.write_text('0\n')
        self.assertEqual(self.run_script('charging-inhibit.sh', '--once').returncode, 0)
        self.assertEqual(inhibit.read_text().strip(), '1')
        self.assertEqual(self.run_script('charging-inhibit.sh', '--stop').returncode, 0)
        self.assertEqual(inhibit.read_text().strip(), '1')
        self.assertFalse((self.p / 'sys/class/qcom-battery/fake_soc').exists())

    def test_rotating_logger_preserves_failure_status(self):
        cmd = '. "$APPLIANCE_HOME/common.sh"; app_init logtest; app_run_logged sh -c \'i=0; while [ "$i" -lt 2000 ]; do echo "a sufficiently long log line to exercise rotation"; i=$((i+1)); done; exit 7\''
        r = subprocess.run(['sh', '-c', cmd], env=self.env, timeout=20)
        self.assertEqual(r.returncode, 7)
        log = self.home / 'log/logtest.log'
        self.assertTrue(log.with_suffix('.log.1').exists())
        self.assertLess(log.stat().st_size, 68000)
        self.assertLess(log.with_suffix('.log.1').stat().st_size, 68000)


@unittest.skipUnless(all(shutil.which(x) for x in ('runsvdir', 'runsv', 'sv')), 'runit not in PATH')
class SupervisorTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.p = Path(self.tmp.name)
        self.service = self.p / 'services/demo'
        self.service.mkdir(parents=True)
        run = self.service / 'run'
        run.write_text('#!/bin/sh\nexec sleep 300\n')
        run.chmod(0o755)
        for name in ('wake_lock', 'wake_unlock'):
            (self.p / name).touch()
        self.env = dict(os.environ, SERVICE_DIR=str(self.p / 'services'), STATE_DIR=str(self.p / 'state'),
                        WAKE_LOCK=str(self.p / 'wake_lock'), WAKE_UNLOCK=str(self.p / 'wake_unlock'),
                        APPLIANCE_SERVICES_CONFIG=str(self.p / 'absent'), STOP_TIMEOUT='2')
        self.proc = None
        self.addCleanup(self.cleanup_processes)

    def command(self, *args):
        return subprocess.run(['sh', str(SUPERVISOR), *args], env=self.env,
                              capture_output=True, text=True, timeout=20)

    def wait_for(self, test):
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            if test(): return
            time.sleep(0.05)
        self.fail('Timed out waiting for supervisor/service')

    def service_up(self):
        r = subprocess.run(['sv', 'status', str(self.service)], capture_output=True, text=True)
        return r.returncode == 0 and r.stdout.startswith('run:')

    def start(self):
        self.proc = subprocess.Popen(['sh', str(SUPERVISOR)], env=self.env,
                                     stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        self.wait_for(self.service_up)

    def cleanup_processes(self):
        if self.proc is not None:
            if self.proc.poll() is None:
                self.proc.terminate()
                self.proc.wait(timeout=10)
        subprocess.run(['sv', '-w', '1', 'force-stop', str(self.service)], capture_output=True)
        subprocess.run(['sv', '-w', '1', 'exit', str(self.service)], capture_output=True)
        if self.proc is not None:
            self.proc.communicate(timeout=5)

    def test_duplicate_start_and_clean_stop(self):
        self.start()
        self.assertEqual((self.p / 'wake_lock').read_text().strip(), 'klipper-appliance')
        duplicate = self.command()
        self.assertEqual(duplicate.returncode, 0)
        self.assertIn('already running', duplicate.stdout)
        stop = self.command('stop')
        self.assertEqual(stop.returncode, 0, stop.stdout + stop.stderr)
        self.proc.wait(timeout=10)
        self.assertEqual((self.p / 'wake_unlock').read_text().strip(), 'klipper-appliance')
        self.assertFalse(self.service_up())

    def test_missing_wake_lock_refuses_start(self):
        (self.p / 'wake_lock').unlink()
        r = self.command()
        self.assertNotEqual(r.returncode, 0)
        self.assertFalse(self.service_up())
        self.assertFalse((self.p / 'state/owner').exists())

    def test_failed_shutdown_retains_wake_lock(self):
        (self.service / 'run').write_text("#!/bin/sh\ntrap '' TERM\nexec sleep 300\n")
        self.start()
        stop = self.command('stop')
        self.assertNotEqual(stop.returncode, 0)
        self.proc.wait(timeout=10)
        self.assertEqual((self.p / 'wake_unlock').read_text(), '')
        self.assertEqual((self.p / 'state/stop-result').read_text().strip(), '1')

    def test_runsvdir_death_stops_children_and_releases_wake_lock(self):
        self.start()
        pid = int((self.p / 'state/runsvdir').read_text().split()[0])
        os.kill(pid, signal.SIGTERM)
        self.proc.wait(timeout=10)
        self.assertFalse(self.service_up())
        self.assertEqual((self.p / 'wake_unlock').read_text().strip(), 'klipper-appliance')


if __name__ == '__main__':
    unittest.main()
