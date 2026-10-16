#!/usr/bin/env python3
"""Assert explicit headless gates; never promote skipped desktop QA to PASS."""
import json
from project_paths import ROOT
report=json.loads((ROOT/'qa/results/summary.json').read_text())
required=['quality-tools','visual-review-tools','repository-safety-tools','repository-safety','protocol-conformance',
          'server-check','server-tests','business','dataMigration','relayIntegration','multiDeviceIntegration','crashRecovery','build']
failed=[name for name in required if report.get(name,{}).get('status')!='PASS']
if report.get('copy',{}).get('status') not in ('PASS','WARN'): failed.append('copy')
for name in ('ui','visual'):
    if report.get(name,{}).get('status')!='NOT RUN': failed.append(name+' headless reporting')
for name,value in report.items():print(name+': '+value.get('status','MISSING'))
if failed:raise SystemExit('Missing/failed CI gates: '+', '.join(failed))
print('Headless CI gates passed. Desktop UI/visual and independent security review remain separate.')
