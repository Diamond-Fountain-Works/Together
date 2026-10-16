#!/usr/bin/env python3
"""One reproducible entry; records separate gates, never calls missing evidence PASS."""
from pathlib import Path
import subprocess,json,os,re,sys,time,urllib.request,tempfile,socket,signal
from project_paths import ROOT, APP as project, CORE, RELAY
out=ROOT/'qa/results';out.mkdir(parents=True,exist_ok=True);report={};owned_server=None;owned_state=None;server_log=None

def run(name,command,cwd=ROOT,env=None):
    with (out/(name+'.log')).open('w') as log:r=subprocess.run(command,cwd=cwd,env=env,stdout=log,stderr=subprocess.STDOUT)
    report[name]={'status':'PASS' if r.returncode==0 else 'FAIL','exitCode':r.returncode,'log':str((out/(name+'.log')).relative_to(ROOT))}
    return r.returncode
try:
    run('quality-tools',[sys.executable,'scripts/test_quality_tools.py'])
    run('visual-review-tools',[sys.executable,'scripts/test_visual_review.py'])
    run('repository-safety-tools',[sys.executable,'scripts/test_repository_safety.py'])
    run('repository-safety',[sys.executable,'scripts/audit_repository_safety.py','--json','qa/results/repository-safety.json'])
    run('protocol-conformance',[sys.executable,'-m','unittest','discover','-s','tests/conformance','-v'])
    run('copy',[sys.executable,'scripts/audit_ui_copy.py','--json','qa/results/copy.json'])
    if (out/'copy.json').exists():report['copy']=json.loads((out/'copy.json').read_text())
    run('server-check',['npm','run','check'],RELAY);run('server-tests',['npm','test'],RELAY)
    # A fresh test Worker avoids mutating a user's running local service or
    # inheriting rate-limit/route records from another QA invocation. Production
    # limits remain enabled; this is data isolation, not a bypass.
    with socket.socket() as probe:
        probe.bind(('127.0.0.1',0)); relay_port=probe.getsockname()[1]
    relay_origin=f'http://127.0.0.1:{relay_port}'
    def available():
        try:
            with urllib.request.urlopen(relay_origin+'/health',timeout=1) as r:return json.loads(r.read()).get('delivery')=='realtime-only'
        except Exception:return False
    owned_state=tempfile.TemporaryDirectory(prefix='together-qa-relay-')
    server_log=(out/'relay-dev.log').open('w');owned_server=subprocess.Popen(['./node_modules/.bin/wrangler','dev','--local','--ip','127.0.0.1','--port',str(relay_port),'--persist-to',owned_state.name],cwd=RELAY,stdout=server_log,stderr=subprocess.STDOUT,start_new_session=True)
    until=time.monotonic()+30
    while not available() and time.monotonic()<until and owned_server.poll() is None:time.sleep(.25)
    env=os.environ.copy()
    if available():env['TOGETHER_RUN_RELAY_TESTS']='1';env['TOGETHER_RELAY_TEST_URL']=relay_origin
    run('business',[sys.executable,'scripts/run_finance_migration_test.py','--all-tests'],ROOT,env)
    text=(out/'business.log').read_text()
    # Swift Testing's summary count includes disabled/skipped tests. Report the
    # actual outcomes separately rather than treating the headline as passes.
    report['business']['passedCount']=len(re.findall(r'^✔ Test (?!run with)[^\n]+ passed after',text,re.M))
    report['business']['skippedCount']=len(re.findall(r'^➜ Test [^\n]+ skipped\.',text,re.M))
    report['business']['failedCount']=len(re.findall(r'^✘ Test (?!run with)[^\n]+ failed',text,re.M))
    report['business']['discoveredCount']=int(re.search(r'Test run with (\d+) tests',text).group(1)) if re.search(r'Test run with (\d+) tests',text) else None
    report['dataMigration']={'status':'PASS' if 'actualLegacyStoreKeepsIdentityDataAndFinancialRestart() passed' in text else 'NOT RUN','sourceVersion':'0.0.1','targetVersion':json.loads((project/'Configuration/ReleaseVersion.json').read_text())['marketingVersion'],'isolation':'private temporary store created with original source'}
    report['relayIntegration']={'status':'PASS' if available() and 'invitationMutualConfirmEncryptedLogMediaReconnectAndPersistentMigration() passed' in text else 'NOT RUN' if not available() else 'FAIL','endpoint':relay_origin,'isolatedWorkerState':True}
    report['multiDeviceIntegration']={'status':'PASS' if available() and 'fourNativeClientsMigrateCatchUpMediaAndRevokeOverRealLocalWorker() passed' in text else 'NOT RUN' if not available() else 'FAIL','endpoint':relay_origin,'physicalDevices':False,'clients':4}
    report['crashRecovery']={'status':'PASS' if 'killedWriterRestoresFactsStagingIdentityPairingAndReceipts() passed' in text else 'NOT RUN','isolation':'synthetic child process and temporary database'}
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
    if owned_server:
        try:os.killpg(owned_server.pid,signal.SIGTERM)
        except ProcessLookupError:pass
        try:owned_server.wait(timeout=5)
        except subprocess.TimeoutExpired:
            try:os.killpg(owned_server.pid,signal.SIGKILL)
            except ProcessLookupError:pass
            owned_server.wait()
    if server_log:server_log.close()
    if owned_state:owned_state.cleanup()
    report['security']={'status':'REVIEW REQUIRED','document':'docs/security/SECURITY_REVIEW.md','productionDeployment':'not inferred by QA','realCrossWiFi':'NOT RUN'}
    (out/'summary.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
for k,v in report.items():print(k+': '+v.get('status','NOT RUN'))
failed=any(v.get('status')=='FAIL' for v in report.values());review=any(v.get('status') in ['WARN','REVIEW REQUIRED','NOT RUN'] for v in report.values())
sys.exit(1 if failed else 2 if review else 0)
