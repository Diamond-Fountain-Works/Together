#!/usr/bin/env python3
"""Read-only source fingerprint + owner-only copy; all SwiftData writes stay in it.

Never opens live SQLite via SwiftData, reads Keychain, replaces an app, or exports
private text/keys. Requires a quiescent source; concurrent changes abort the test.
"""
from pathlib import Path
import argparse, hashlib, json, os, shutil, subprocess, tempfile, time

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--app', help='Optional Debug .app for two isolated real process launches')
args = parser.parse_args()
source = Path.home() / 'Library/Application Support/Together'
results = root / 'qa/results'
results.mkdir(parents=True, exist_ok=True)

def fingerprint():
    paths = list(source.glob('Together.store*')) + list((source/'Identity').glob('device-*.key'))
    hashes = {}
    for path in paths:
        if not path.is_file(): continue
        digest = hashlib.sha256()
        # file_digest is only available in Python 3.11+. Keep the documented
        # QA entry usable on older Python and never read a whole store at once.
        with path.open('rb') as file:
            for block in iter(lambda: file.read(1024 * 1024), b''):
                digest.update(block)
        hashes[str(path.relative_to(source))] = digest.hexdigest()
    return hashes

def run(command, cwd, env=None):
    with (results/'existing-store-upgrade.log').open('a') as log:
        subprocess.run(command, cwd=cwd, env=env, stdout=log, stderr=subprocess.STDOUT, check=True)

before = None
report = {'status':'NOT RUN', 'isolation':'owner-only temporary copy', 'productionSourceUnchanged':False, 'appProcessLaunches':0}
try:
    before = fingerprint()
    if not (source/'Together.store').exists():
        raise RuntimeError('Existing store is absent')
    with tempfile.TemporaryDirectory(prefix='together-ui-existing-') as directory:
        copied = Path(directory)
        copied.chmod(0o700)
        for name in ('Together.store', 'Together.store-wal', 'Together.store-shm'):
            if (source/name).exists():
                target = copied/name.replace('Together.store','legacy.store')
                shutil.copyfile(source/name, target); target.chmod(0o600)
        for name in ('Identity', 'Media'):
            if (source/name).exists(): shutil.copytree(source/name, copied/name)
        if fingerprint() != before: raise RuntimeError('Source changed during copy; repeat after closing the production app')
        cache = Path.home()/'.cache/Together/LegacyMigration-SPM'
        run(['swift','run','--scratch-path',str(cache),'LegacyFixture','--audit-copy',str(copied)],root/'qa/migration/legacy_fixture')
        if args.app:
            binary = Path(args.app).resolve()/'Contents/MacOS/Together'
            for launch in range(2):
                env = os.environ.copy()
                env.update(TOGETHER_UI_ROOT=str(copied), TOGETHER_UI_PAGE='home', TOGETHER_UI_STATE='empty', TOGETHER_UI_MODE='light', TOGETHER_UI_REDUCE_MOTION='1', TOGETHER_UI_CAPTURE='1', TOGETHER_UI_CASE=f'upgrade-reopen-{launch}')
                ready = copied/'capture.json'
                ready.unlink(missing_ok=True)
                with (results/'existing-store-app.log').open('a') as log:
                    process = subprocess.Popen([str(binary),'--ui-testing','-AppleLanguages','(zh-Hans)','-AppleLocale','zh_CN'],env=env,stdout=log,stderr=subprocess.STDOUT)
                    try:
                        deadline = time.monotonic()+20
                        while not ready.exists() and process.poll() is None and time.monotonic()<deadline:time.sleep(.1)
                        if not ready.exists(): raise RuntimeError('Isolated upgraded app did not finish showing its content')
                        report['appProcessLaunches'] += 1
                    finally:
                        if process.poll() is None:
                            process.terminate()
                            try:process.wait(timeout=5)
                            except subprocess.TimeoutExpired:process.kill();process.wait()
        env = os.environ.copy();env['TOGETHER_EXISTING_COPY_FIXTURE']=str(copied)
        run(['swift','test','--filter','ExistingStoreUpgradeTests'],root/'0.2.1',env)
        expected = json.loads((copied/'existing-expected.json').read_text())
        report.update(status='PASS', preservedOperations=len(expected['operationHashes']), preservedEntityHashes=len(expected['entities']), preservedLocalRecords=len(expected['localRecords']), peerPreserved=expected.get('peer') is not None, relayBindingPreserved=expected.get('binding') is not None, repeatedStoreOpens=3, sourceIdentityFileCount=len(list((source/'Identity').glob('device-*.key'))))
except Exception as error:
    report.update(status='FAIL', reason=str(error))
finally:
    try:
        report['productionSourceUnchanged'] = before is not None and fingerprint() == before
    except OSError as error:
        report.update(status='FAIL', reason='Final source fingerprint failed: '+str(error))
    if before is not None and not report['productionSourceUnchanged'] and not report.get('reason', '').startswith('Final source fingerprint failed:'):
        report.update(status='FAIL', reason='Source fingerprint changed during the rehearsal; investigate concurrent app activity')
    (results/'existing-store-upgrade.json').write_text(json.dumps(report,indent=2)+'\n')
print('Existing store copy upgrade:',report['status'],'source unchanged:',report['productionSourceUnchanged'],'isolated app launches:',report['appProcessLaunches'])
raise SystemExit(0 if report['status']=='PASS' else 1)
