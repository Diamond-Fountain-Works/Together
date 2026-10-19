#!/usr/bin/env python3
"""Physical Samsung partner UI <-> native Swift, authorized staging only.

USB controls tests and transfers synthetic fixture/control files. All actual
pairing, signed logs, ACK and media travel via public HTTPS/WSS. No adb reverse.
Does not open a production Mac app, workspace, identity or preferences.
"""
from pathlib import Path
import argparse, concurrent.futures, hashlib, json, os, secrets, subprocess, tempfile, time
from test_android_physical_bridge import sample_media
ROOT = Path(__file__).resolve().parents[1]
PACKAGE = 'com.together.android.debug'
ORIGIN = 'https://together-pairing-staging.together-connection-service.workers.dev'

def require(condition, message):
    if not condition:
        raise RuntimeError(message)

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--serial', required=True)
    p.add_argument('--authorize-physical-test-app', action='store_true', required=True)
    p.add_argument('--direction', choices=['android-invites', 'mac-invites', 'both'], default='both')
    a = p.parse_args()
    adb = [str(Path.home() / 'Library/Android/sdk/platform-tools/adb'), '-s', a.serial]

    def run(*args, **kw):
        return subprocess.run(adb + list(args), capture_output=True, check=True, **kw)
    require(run('get-state').stdout.strip() == b'device', 'Authorized online device required')
    require(not run('reverse', '--list').stdout.strip(), 'USB reverse must be absent for real-network acceptance')
    model = run('shell', 'getprop', 'ro.product.model').stdout.decode().strip()
    require(model == 'SM-S9210', 'Explicitly authorized Samsung model required')
    require(b'enabled' not in run('shell', 'cmd', 'wifi', 'status').stdout.splitlines()[0].lower(), 'Samsung Wi-Fi must be off')
    output = ROOT / 'qa/results/partner-cross-network' / time.strftime('%Y%m%d-%H%M%S')
    output.mkdir(parents=True, mode=448)
    (output / 'android-network.txt').write_bytes(run('shell', 'dumpsys', 'connectivity').stdout)
    (output / 'android-wifi.txt').write_bytes(run('shell', 'cmd', 'wifi', 'status').stdout)
    run('install', '-r', str(ROOT / 'apps/android/app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk'))
    results = []
    for android_invites in [True, False] if a.direction == 'both' else [a.direction == 'android-invites']:
        label = 'android-invites' if android_invites else 'mac-invites'
        case = output / label
        case.mkdir(mode=448)
        ident = secrets.token_hex(16).upper()
        private = 'files/partner-bridge/' + ident
        root = Path(tempfile.mkdtemp(prefix='together-partner-')).resolve()
        root.chmod(448)
        (root / 'launch.json').write_text(json.dumps({'base': ORIGIN, 'androidInvites': android_invites}))
        sample_media(root)
        run('shell', 'run-as', PACKAGE, 'mkdir', '-p', private)

        def push(name):
            require('/' not in name and name in {'launch.json', 'synthetic.png', 'synthetic.wav', 'mac-invitation.json', 'approved', 'mac-created.json', 'mac-offline-written', 'mac-checkpoint.json'}, 'Acceptance guard failed')
            run('shell', '-T', 'run-as', PACKAGE, 'sh', '-c', "'cat > " + private + '/' + name + "'", input=(root / name).read_bytes())

        def pull(name):
            require('/' not in name, 'Acceptance guard failed')
            response = subprocess.run(adb + ['exec-out', 'run-as', PACKAGE, 'cat', private + '/' + name], capture_output=True)
            if response.returncode:
                return False
            try:
                json.loads(response.stdout)
            except (json.JSONDecodeError, UnicodeDecodeError):
                return False
            (root / name).write_bytes(response.stdout)
            return True
        for name in ('launch.json', 'synthetic.png', 'synthetic.wav'):
            push(name)
        env = os.environ.copy()
        env['TOGETHER_PARTNER_BRIDGE_DIR'] = str(root)
        native_log = (case / 'native-swift.log').open('w')
        native = subprocess.Popen(['swift', 'test', '--skip-build', '--package-path', str(ROOT / 'packages/together-core-swift'), '--filter', 'PartnerPhysicalBridgeTests'], cwd=ROOT, env=env, stdout=native_log, stderr=subprocess.STDOUT)
        copied = set()
        approved = False
        result = {'direction': label, 'status': 'FAIL', 'adbReverse': False, 'nativeMacHost': 'isolated native Swift test process; not the Mac GUI'}

        def instrument(method, logname):
            cmd = adb + ['shell', 'am', 'instrument', '-w', '-r', '-e', 'class', 'com.together.android.PartnerPhysicalTest#' + method, '-e', 'physicalQa', 'explicit-test-app-only', '-e', 'expectedModel', model, '-e', 'qaRunId', ident, '-e', 'relayURL', ORIGIN, '-e', 'publicStagingQa', 'explicit-staging-only', '-e', 'partnerBridgeId', ident, PACKAGE + '.test/com.together.android.IsolatedAndroidTestRunner']
            started = time.monotonic()
            response = subprocess.run(cmd, capture_output=True, timeout=360)
            (case / logname).write_bytes(response.stdout + response.stderr)
            text = response.stdout.decode(errors='replace')
            require(response.returncode == 0 and 'OK (' in text and ('FAILURES!!!' not in text), 'Instrumentation failed; see ' + str(case / logname))
            return {'status': 'PASS', 'elapsedSeconds': round(time.monotonic() - started, 2)}
        executor = concurrent.futures.ThreadPoolExecutor(max_workers=1)

        def pump(future):
            nonlocal approved
            deadline = time.monotonic() + 360
            while not future.done():
                require(time.monotonic() < deadline, 'Driver deadline exceeded')
                for name in ('phone-invitation.json', 'phone-verification.json', 'phone-created.json', 'phone-offline.json', 'phone-reconnected.json', 'phone-restarted.json'):
                    if name not in copied and pull(name):
                        copied.add(name)
                if not approved and (root / 'mac-verification.json').exists() and (root / 'phone-verification.json').exists():
                    mac = json.loads((root / 'mac-verification.json').read_text())
                    phone = json.loads((root / 'phone-verification.json').read_text())
                    require(mac['code'] == phone['code'] and len(mac['code']) == 6, 'Signed transcript verification codes differ')
                    (root / 'approved').write_bytes(b'')
                    push('approved')
                    approved = True
                for name in ('mac-invitation.json', 'mac-created.json', 'mac-offline-written', 'mac-checkpoint.json'):
                    if name not in copied and (root / name).exists():
                        push(name)
                        copied.add(name)
                require(native.poll() is None or (root / 'mac-result.json').exists(), 'Native Swift host exited; see ' + str(case / 'native-swift.log'))
                time.sleep(0.1)
            return future.result()
        try:
            first = executor.submit(instrument, 'partnerInvitationUiHistoryLiveSyncMediaAndReconnect', 'phone-initial.log')
            result['initial'] = pump(first)
            require(pull('phone-reconnected.json'), 'Acceptance guard failed')
            deadline = time.monotonic() + 30
            while not (root / 'mac-checkpoint.json').exists():
                require(time.monotonic() < deadline, 'Acceptance guard failed')
                time.sleep(0.1)
            push('mac-checkpoint.json')
            run('shell', 'am', 'force-stop', PACKAGE)
            second = executor.submit(instrument, 'pairedPartnerIdentityAndHistorySurviveActualProcessRestart', 'phone-restart.log')
            result['restart'] = pump(second)
            pull('phone-restarted.json')
            deadline = time.monotonic() + 30
            while not (root / 'mac-result.json').exists():
                require(native.poll() is None, 'Acceptance guard failed')
                require(time.monotonic() < deadline, 'Acceptance guard failed')
                time.sleep(0.1)
            require(native.wait(timeout=30) == 0, 'Acceptance guard failed')
            result.update(status='PASS', native=json.loads((root / 'mac-result.json').read_text()), verificationCodesEqual=approved)
        except Exception as error:
            result['error'] = str(error)
        finally:
            if native.poll() is None:
                native.terminate()
                native.wait(timeout=15)
            native_log.close()
            executor.shutdown(wait=True)
            for name in ('phone-diagnostic.json', 'phone-restarted.json'):
                pull(name)
            for name in ('mac-diagnostic.json', 'mac-result.json', 'mac-checkpoint.json', 'phone-diagnostic.json', 'phone-reconnected.json', 'phone-restarted.json'):
                if (root / name).exists():
                    (case / name).write_bytes((root / name).read_bytes())
            (case / 'logcat.txt').write_bytes(run('logcat', '-d', '-v', 'threadtime', '-s', 'TogetherPartnerQa', 'TogetherPhysicalQa', 'AndroidRuntime').stdout)
            for name in ('verification-candidate', 'connected-candidate', 'restarted-candidate'):
                screenshot = subprocess.run(adb + ['pull', '/data/local/tmp/together-partner-' + ident + '-' + name + '.png', str(case / (name + '.png'))], capture_output=True)
            (case / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
            results.append(result)
            require(not run('reverse', '--list').stdout.strip(), 'Acceptance guard failed')
            print(label, result['status'], result.get('error', ''), flush=True)
        if result['status'] != 'PASS':
            break
    summary = {'status': 'PASS' if len(results) == (2 if a.direction == 'both' else 1) and all((r['status'] == 'PASS' for r in results)) else 'FAIL', 'network': 'Mac Wi-Fi / physical Samsung independent network / public WSS; no USB networking', 'results': results}
    (output / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    print(output, flush=True)
    raise SystemExit(0 if summary['status'] == 'PASS' else 1)
if __name__ == '__main__':
    main()
