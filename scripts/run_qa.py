#!/usr/bin/env python3
"""One reproducible entry; records separate gates, never calls missing evidence PASS."""
from pathlib import Path
import subprocess,json,os,re,sys,time,urllib.request
ROOT=Path(__file__).resolve().parents[1];project=ROOT/json.loads((ROOT/'qa/project.json').read_text())['projectDirectory'];out=ROOT/'qa/results';out.mkdir(parents=True,exist_ok=True);report={};owned_server=None

def run(name,command,cwd=ROOT,env=None):
    with (out/(name+'.log')).open('w') as log:r=subprocess.run(command,cwd=cwd,env=env,stdout=log,stderr=subprocess.STDOUT)
    report[name]={'status':'PASS' if r.returncode==0 else 'FAIL','exitCode':r.returncode,'log':str((out/(name+'.log')).relative_to(ROOT))}
    return r.returncode
try:
    run('quality-tools',[sys.executable,'scripts/test_quality_tools.py'])
    run('copy',[sys.executable,'scripts/audit_ui_copy.py','--json','qa/results/copy.json'])
    if (out/'copy.json').exists():report['copy']=json.loads((out/'copy.json').read_text())
    run('server-check',['npm','run','check'],ROOT/'server');run('server-tests',['npm','test'],ROOT/'server')
    def available():
        try:
            with urllib.request.urlopen('http://127.0.0.1:8787/health',timeout=1) as r:return json.loads(r.read()).get('delivery')=='realtime-only'
        except Exception:return False
    if not available():
        log=(out/'relay-dev.log').open('w');owned_server=subprocess.Popen(['./node_modules/.bin/wrangler','dev','--local','--ip','127.0.0.1','--port','8787'],cwd=ROOT/'server',stdout=log,stderr=subprocess.STDOUT)
        until=time.monotonic()+30
        while not available() and time.monotonic()<until and owned_server.poll() is None:time.sleep(.25)
    env=os.environ.copy()
    if available():env['TOGETHER_RUN_RELAY_TESTS']='1'
    run('business',['swift','test'],project,env)
    text=(out/'business.log').read_text()
    report['business']['passedCount']=int(re.search(r'Test run with (\d+) tests.*passed',text).group(1)) if re.search(r'Test run with (\d+) tests.*passed',text) else None
    report['relayIntegration']={'status':'PASS' if available() and 'invitationMutualConfirmEncryptedLogMediaReconnectAndPersistentMigration() passed' in text else 'NOT RUN' if not available() else 'FAIL'}
    run('build',['./script/build_and_run.sh','--build-only'],project)
    if '--skip-ui' in sys.argv:
        report['ui']={'status':'NOT RUN','reason':'Explicit --skip-ui; previous runs cannot substitute for current verification.'}
        report['visual']={'status':'NOT RUN','reason':'Current XCTest capture was not run.'}
    else:
        run('ui',[sys.executable,'scripts/run_ui_tests.py'])
        if (out/'ui.json').exists():report['ui']=json.loads((out/'ui.json').read_text())
        run('visual',[sys.executable,'scripts/compare_visuals.py'])
        if (out/'visual.json').exists():report['visual']=json.loads((out/'visual.json').read_text())
finally:
    if owned_server:owned_server.terminate()
    report['security']={'status':'REVIEW REQUIRED','document':'SECURITY_REVIEW.md','productionDeployment':'not inferred by QA','realCrossWiFi':'NOT RUN'}
    (out/'summary.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
for k,v in report.items():print(k+': '+v.get('status','NOT RUN'))
failed=any(v.get('status')=='FAIL' for v in report.values());review=any(v.get('status') in ['WARN','REVIEW REQUIRED','NOT RUN'] for v in report.values())
sys.exit(1 if failed else 2 if review else 0)
