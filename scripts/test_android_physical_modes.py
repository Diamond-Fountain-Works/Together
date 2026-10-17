#!/usr/bin/env python3
"""Explicit Samsung-only visual/interaction matrix; restore every changed display setting.

Only Together synthetic test namespaces run. No radio, keyboard, permissions, lock-screen or
user-data settings are changed. All screenshots are unapproved, local-only candidates.
"""
import argparse
import json
import signal
from pathlib import Path
from run_android_physical_qa import PhysicalRun, ROOT, PACKAGE, require


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--serial', required=True)
    p.add_argument('--expect-model', required=True)
    p.add_argument('--relay', required=True)
    p.add_argument('--authorize-physical-test-app', action='store_true', required=True)
    p.add_argument('--label', default='samsung-mode-matrix')
    args = p.parse_args()
    require(args.label.replace('-', '').isalnum(), 'Simple local artifact label required')
    run = PhysicalRun(args.serial, args.expect_model, args.relay,
                      ROOT/'qa/results/android-phase-c'/args.label)
    run.preflight()
    def shell(*values):
        return run.adb('shell', *values).stdout.decode().strip()
    settings = [('system', 'font_scale'), ('system', 'accelerometer_rotation'),
                ('system', 'user_rotation'), ('global', 'window_animation_scale'),
                ('global', 'transition_animation_scale'), ('global', 'animator_duration_scale')]
    before = {f'{ns}.{key}': shell('settings', 'get', ns, key) for ns, key in settings}
    before['night'] = shell('cmd', 'uimode', 'night')
    require(before['night'] in ('Night mode: no', 'Night mode: yes', 'Night mode: auto',
                                'Night mode: custom'), 'Unknown night mode; refuse to change it')
    require(before['night'] != 'Night mode: custom', 'Custom night schedule needs manual QA instead')
    (run.out/'settings-before.json').write_text(json.dumps(before, indent=2))
    def put(ns, key, value):
        if value == 'null': shell('settings', 'delete', ns, key)
        else: shell('settings', 'put', ns, key, value)
    results = []
    restored = False
    def interrupted(_signum, _frame):
        raise KeyboardInterrupt('Interrupted; restoring phone display settings')
    signal.signal(signal.SIGTERM, interrupted)
    methods = {
        'task': 'taskEditorFlexibleLaterEditCompleteReopenAndTombstone',
        'finance': 'actualFinanceCRUDCurrencyBillsAndReviewUseOneLedger',
        'wishes': 'wishesBeneficiaryConfirmsAndHistoryDoesNotRequireFinancialApproval',
        'gift': 'sealedGiftHasNoPrivateSemanticsUntilOpenAndContentReceiptIsIndependent',
    }
    try:
        for mode, selected in [('dark', ['task', 'finance', 'wishes', 'gift']),
                               ('large-font-reduced-motion', ['task', 'finance', 'gift']),
                               ('landscape', ['task', 'finance'])]:
            shell('am', 'force-stop', PACKAGE)
            # First restore the recorded values so changes do not leak from one matrix row.
            for ns, key in settings: put(ns, key, before[f'{ns}.{key}'])
            shell('cmd', 'uimode', 'night', before['night'].split()[-1])
            if mode == 'dark': shell('cmd', 'uimode', 'night', 'yes')
            if mode == 'large-font-reduced-motion':
                put('system', 'font_scale', '1.3')
                for key in ('window_animation_scale', 'transition_animation_scale', 'animator_duration_scale'):
                    put('global', key, '0')
            if mode == 'landscape':
                put('system', 'accelerometer_rotation', '0')
                put('system', 'user_rotation', '1')
            classes = ','.join('com.together.android.BusinessUiTest#'+methods[k] for k in selected)
            result = run.instrument(classes, mode, {'capturePrefix': 'samsung-'+mode}, timeout=450)
            results.append(result)
            # Preserve failures and stop; never manufacture a passing matrix by omitting a row.
            require(result['status'] == 'PASS', 'Physical mode failed: '+mode)
    finally:
        shell('am', 'force-stop', PACKAGE)
        errors = []
        for ns, key in settings:
            try: put(ns, key, before[f'{ns}.{key}'])
            except Exception as error: errors.append(f'{ns}.{key}: {error}')
        try: shell('cmd', 'uimode', 'night', before['night'].split()[-1])
        except Exception as error: errors.append('night: '+str(error))
        after = {f'{ns}.{key}': shell('settings', 'get', ns, key) for ns, key in settings}
        after['night'] = shell('cmd', 'uimode', 'night')
        restored = not errors and after == before
        (run.out/'settings-after.json').write_text(json.dumps(after, indent=2))
        summary = dict(status='PASS' if len(results)==3 and all(r['status']=='PASS' for r in results)
                       and restored else 'FAIL', results=results, settingsRestored=restored,
                       restorationErrors=errors, visualStatus='CANDIDATE')
        (run.out/'result.json').write_text(json.dumps(summary, indent=2))
        print(json.dumps(summary), flush=True)
    require(restored, 'Display settings restore failed; see local report and restore recorded values manually')


if __name__ == '__main__':
    main()
