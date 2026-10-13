#!/usr/bin/env python3
"""Check actual bundle metadata instead of assuming Xcode emitted custom keys."""
from pathlib import Path
import json, os, plistlib, subprocess, sys

root = Path(__file__).resolve().parent.parent
if len(sys.argv) != 2:
    raise SystemExit('usage: verify_bundle.py /path/to/Together.app')
bundle = Path(sys.argv[1])
info = plistlib.loads((bundle / 'Contents/Info.plist').read_bytes())
config = root / 'Configuration/RelayService.json'
expected_origin = os.environ.get('TOGETHER_RELAY_URL', json.loads(config.read_text()).get('origin', '') if config.exists() else '')
expected = {'CFBundleIdentifier': 'com.together.app', 'CFBundleShortVersionString': '0.0.1', 'CFBundleVersion': '1'}
if expected_origin:
    expected['TogetherRelayURL'] = expected_origin
for key, value in expected.items():
    if info.get(key) != value:
        raise SystemExit(f'Bundle verification FAIL: {key} does not match configuration')
if not info.get('NSMicrophoneUsageDescription'):
    raise SystemExit('Bundle verification FAIL: missing microphone purpose')
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(bundle)], check=True)
print('Bundle verification PASS: version, identity, relay origin, microphone purpose and signature')
