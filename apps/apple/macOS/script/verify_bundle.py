#!/usr/bin/env python3
"""Check actual bundle metadata instead of assuming Xcode emitted custom keys."""
from pathlib import Path
import json, os, plistlib, subprocess, sys

root = Path(__file__).resolve().parent.parent
if len(sys.argv) not in [2,3] or (len(sys.argv)==3 and sys.argv[2]!='--release'):
    raise SystemExit('usage: verify_bundle.py /path/to/Together.app [--release]')
bundle = Path(sys.argv[1])
info = plistlib.loads((bundle / 'Contents/Info.plist').read_bytes())
config = root / 'Configuration/RelayService.json'
expected_origin = os.environ.get('TOGETHER_RELAY_URL', json.loads(config.read_text()).get('origin', '') if config.exists() else '')
release = json.loads((root / 'Configuration/ReleaseVersion.json').read_text())
expected = {'CFBundleIdentifier': 'com.together.app', 'CFBundleShortVersionString': release['marketingVersion'], 'CFBundleVersion': release['buildNumber']}
native = info.get('TogetherTransport') == 'native'
if native:
    if info.get('TogetherRelayURL'): raise SystemExit('Bundle verification FAIL: native launch includes an obsolete default Relay origin')
    expected['LSMinimumSystemVersion'] = '14.5'
    if subprocess.check_output(['lipo','-archs',str(bundle/'Contents/MacOS/Together')],text=True).split() != ['arm64']:
        raise SystemExit('Bundle verification FAIL: native distribution requires the verified Apple Silicon slice')
elif expected_origin:
    expected['TogetherRelayURL'] = expected_origin
for key, value in expected.items():
    if info.get(key) != value:
        raise SystemExit(f'Bundle verification FAIL: {key} does not match configuration')
if not info.get('NSMicrophoneUsageDescription'):
    raise SystemExit('Bundle verification FAIL: missing microphone purpose')
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(bundle)], check=True)
signed = subprocess.run(['codesign','-d','--entitlements',':-',str(bundle)],capture_output=True,check=True)
entitlements = plistlib.loads(signed.stdout)
for key in ['com.apple.security.network.client','com.apple.security.network.server','com.apple.security.device.audio-input','com.apple.security.files.user-selected.read-write']:
    if entitlements.get(key) is not True:raise SystemExit('Bundle verification FAIL: required entitlement missing: '+key)
if ('Release' in bundle.parts or '--release' in sys.argv) and entitlements.get('com.apple.security.get-task-allow'):
    raise SystemExit('Bundle verification FAIL: Release allows debugger access')

if native and '--release' in sys.argv:
    symbols=subprocess.check_output(['nm','-gj',str(bundle/'Contents/MacOS/Together')],text=True,stderr=subprocess.DEVNULL)
    if any(name in symbols for name in ['UIFixture','NativeAcceptance','TOGETHER_UI_TEST_HOST']):
        raise SystemExit('Bundle verification FAIL: QA startup/fixtures linked into the Release executable')
    for name in ['Iroh-LICENSE-MIT.txt','Iroh-LICENSE-APACHE.txt']:
        if not (bundle/'Contents/Resources'/name).is_file(): raise SystemExit('Bundle verification FAIL: missing native transport license: '+name)
    print('Native Release boundary PASS: normal startup, Apple Silicon, macOS 14.5+, no QA fixture symbols, license notices')

print('Bundle verification PASS: version, identity, transport configuration, microphone purpose, entitlements and signature')
