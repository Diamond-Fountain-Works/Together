#!/usr/bin/env python3
"""Opt-in synthetic emulator QA: real process death, sealed gift and native SAF export.

Requires the Debug app/test APK and an existing adb reverse to a local test Relay.
Never installs/clears data, touches a Mac store, or operates on a physical device.
"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess
import time
import urllib.parse
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = 'com.together.android.debug'
RUNNER = PACKAGE + '.test/com.together.android.IsolatedAndroidTestRunner'
ACTIVITY = PACKAGE + '/com.together.android.qa.BusinessQaActivity'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--serial', required=True)
    parser.add_argument('--relay', required=True)
    args = parser.parse_args()
    parsed = urllib.parse.urlparse(args.relay)
    if parsed.scheme != 'http' or parsed.hostname not in ('127.0.0.1', 'localhost') or not parsed.port:
        parser.error('Only an explicit loopback test Relay is supported')
    if not re.fullmatch(r'emulator-\d+', args.serial):
        parser.error('Dedicated emulator serial required')
    out = ROOT / 'qa/results/android-phase-b/process-launch'
    out.mkdir(parents=True, exist_ok=True)
    captures = ROOT / 'qa/visual/candidates/android-phase-b/runtime'
    captures.mkdir(parents=True, exist_ok=True)
    sequence = 0

    def adb(*command):
        return subprocess.check_output(['adb', '-s', args.serial, *command], timeout=90)

    adb('wait-for-device')
    assert adb('shell', 'getprop', 'ro.kernel.qemu').strip() == b'1'
    assert b'com.together.android.IsolatedAndroidTestRunner' in adb('shell', 'pm', 'list', 'instrumentation')
    port = f'tcp:{parsed.port}'
    mappings = adb('reverse', '--list').decode().splitlines()
    assert any(line.split()[-2:] == [port, port] for line in mappings), 'Expected existing local Relay reverse'

    def instrument(method, **options):
        command = ['shell', 'am', 'instrument', '-w', '-e', 'class', 'com.together.android.GiftLaunchRuntimeTest#' + method]
        for key, value in options.items():
            command += ['-e', key, str(value)]
        text = adb(*command, RUNNER).decode()
        (out / (method + '.log')).write_text(text)
        assert 'OK (1 test)' in text and 'FAILURES' not in text, text

    def tree():
        nonlocal sequence
        sequence += 1
        raw = adb('exec-out', 'uiautomator', 'dump', '/dev/tty').decode()
        (out / f'ui-{sequence:02d}.xml').write_text(raw)
        return ET.fromstring(raw[raw.index('<?xml'):raw.index('</hierarchy>') + 12])

    def has(value, root):
        return any(value in (node.get('text'), node.get('content-desc'), node.get('resource-id')) for node in root.iter('node'))

    def wait_for(value):
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            current = tree()
            if has(value, current):
                return current
            time.sleep(.3)
        raise AssertionError('Missing native UI target: ' + value)

    def tap(value):
        current = wait_for(value)
        matches = [node for node in current.iter('node') if value in (node.get('text'), node.get('content-desc'), node.get('resource-id'))]
        assert len(matches) == 1, (value, len(matches))
        x1, y1, x2, y2 = map(int, re.findall(r'\d+', matches[0].get('bounds')))
        coordinates = (str((x1 + x2) // 2), str((y1 + y2) // 2))
        adb('shell', 'input', 'tap', *coordinates)
        return coordinates

    def capture(name):
        (captures / (name + '.png')).write_bytes(adb('exec-out', 'screencap', '-p'))

    def launch(plan):
        adb('shell', 'am', 'force-stop', PACKAGE)
        adb('shell', 'am', 'start', '-W', '-n', ACTIVITY, '--es', 'qaNamespace', plan['namespace'], '--es', 'qaClock', plan['clock'])

    disconnected = False
    try:
        instrument('prepareCachedGiftForActualProcessRestart', prepareLaunch='true', relayURL=args.relay)
        plan = json.loads(adb('exec-out', 'run-as', PACKAGE, 'cat', 'files/phase-b-launch.json'))
        (out / 'plan.json').write_text(json.dumps(plan, indent=2))
        adb('shell', 'am', 'force-stop', PACKAGE)
        adb('reverse', '--remove', port)
        disconnected = True
        launch(plan)
        sealed = wait_for('Open Your Gift ♡')
        assert 'Synthetic private gift sentinel' not in ET.tostring(sealed).decode()
        assert not has('Play', sealed) and not has('Save original photo', sealed)
        capture('offline-cached-sealed')
        launch(plan)
        second = wait_for('Together')
        assert not has('Open Your Gift ♡', second)
        assert 'Synthetic private gift sentinel' not in ET.tostring(second).decode()
        adb('shell', 'am', 'force-stop', PACKAGE)
        instrument('inspectPersistedPresentationAfterProcessDeath', inspectLaunch='true')
        launch(plan)
        tap('More actions'); tap('Love gift history'); tap('View gift')
        tap('Open Your Gift ♡')
        opened = wait_for('Save original photo')
        assert has('Play', opened), 'Audio must not autoplay'
        capture('opened-before-save')
        tap('Save original photo')
        wait_for('android:id/button1')
        capture('native-save-panel')
        tap('android:id/button1')
        returned = wait_for('Save original photo')
        assert has('Play', returned)
        assert not has('Cannot read or verify this original file. Retry or choose a supported file.', returned)
        # The native panel's displayed Downloads destination was chosen by this explicit QA action.
        exported = adb('exec-out', 'cat', '/sdcard/Download/' + plan['photoFilename'])
        assert hashlib.sha256(exported).hexdigest() == plan['photoHash'] and len(exported) == plan['photoBytes']
        # uiautomator waits for UI idle; a three-second fixture can finish before a new
        # tree is returned. Toggle the same tree-located control, then inspect the result.
        coordinates = tap('Play'); time.sleep(1.2)
        adb('shell', 'input', 'tap', *coordinates)
        paused = wait_for('Play')
        assert not has('0:00 / 0:03', paused), 'Explicit playback must advance'
        capture('opened-after-save')
        tap('Got it ❤️')
        adb('shell', 'am', 'force-stop', PACKAGE)
        instrument('inspectPersistedPresentationAfterProcessDeath', inspectLaunch='true', expectOpened='true')
        result = {'status': 'PASS', 'physicalDevice': False, 'actualProcessRestart': True, 'cachedWithoutRelay': True, 'autoPresentedOnce': True, 'sealedNoPrivateSemantics': True, 'manualAudio': True, 'nativeSAF': True, 'originalSHA256': plan['photoHash'], 'originalBytes': plan['photoBytes'], 'visualStatus': 'CANDIDATE'}
        (out / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
        print(json.dumps(result))
    finally:
        try:
            adb('wait-for-device')
            adb('shell', 'am', 'force-stop', PACKAGE)
        finally:
            if disconnected:
                adb('reverse', port, port)
                assert any(line.split()[-2:] == [port, port] for line in adb('reverse', '--list').decode().splitlines())


if __name__ == '__main__':
    main()
