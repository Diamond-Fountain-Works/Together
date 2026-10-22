#!/usr/bin/env python3
from pathlib import Path
import os, json, platform, subprocess, sys
import argparse,re,plistlib
parser=argparse.ArgumentParser();parser.add_argument('--behavior-only',action='store_true');parser.add_argument('--only-test',action='append',default=[]);parser.add_argument('--label',default='');parser.add_argument('--without-building',action='store_true',help='Use an already built QA host, still enforcing bundle/path isolation');args=parser.parse_args()
if any(not re.fullmatch(r'test[A-Za-z0-9_]+',name) for name in args.only_test):parser.error('--only-test requires a XCTest method name')
if args.label and not re.fullmatch(r'[a-z0-9-]+',args.label):parser.error('--label requires a safe lowercase identifier')
ROOT=Path(__file__).resolve().parents[1]
project=ROOT/json.loads((ROOT/'qa/project.json').read_text())['projectDirectory'];results=ROOT/'qa/results';results.mkdir(parents=True,exist_ok=True)
output=ROOT/'qa/visual/candidates';output.mkdir(parents=True,exist_ok=True)
# New run path; never removes or overwrites an approved result bundle/baseline.
import datetime,hashlib
stamp=datetime.datetime.now().strftime('%Y%m%d-%H%M%S');bundle=results/f'ui-{stamp}.xcresult'
output=output/stamp;output.mkdir(parents=True,exist_ok=False)
env=os.environ.copy()
report_name='ui'+('-'+args.label if args.label else '')
derived=Path(os.environ.get('TOGETHER_UI_DERIVED_DATA',str(ROOT/'qa/results/tool-caches'/('UIQA-'+project.name+'-DerivedData'))))
derived.mkdir(parents=True,exist_ok=True)
subprocess.run([sys.executable,'script/generate_project.py'],cwd=project,check=True,env=env)
# Build first, verify the actual bundle, and only then allow XCTest to launch.
# A stale scheme/configuration must never fall back to the production bundle ID.
base=['xcodebuild','-project','Together.xcodeproj','-scheme','Together','-configuration','UITesting','-destination',f'platform=macOS,arch={platform.machine()}','-derivedDataPath',str(derived),'ARCHS='+platform.machine(),'ONLY_ACTIVE_ARCH=YES','SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG TOGETHER_UI_TEST_HOST','SWIFT_OPTIMIZATION_LEVEL=-Onone']
log_path=results/(report_name+'-test.log')
with log_path.open('w') as log:
    build=subprocess.CompletedProcess([],0) if args.without_building else subprocess.run(base+['build-for-testing'],cwd=project,env=env,stdout=log,stderr=subprocess.STDOUT)
isolation_error=None
runfile=None
if build.returncode==0:
    try:
        candidates=list((derived/'Build/Products').glob('Together_*.xctestrun'))
        runfile=max(candidates,key=lambda path:path.stat().st_mtime)
        run_configuration=plistlib.loads(runfile.read_bytes())
        config=run_configuration['TogetherUITests']
        host=Path(config['UITargetAppPath'].replace('__TESTROOT__',str(runfile.parent)))
        runner=Path(config['TestHostPath'].replace('__TESTROOT__',str(runfile.parent)))
        for bundle_path,expected in [(host,'com.together.app.qa'),(runner,'com.together.app.qa.UITests.xctrunner')]:
            assert bundle_path.resolve().is_relative_to(derived.resolve()), 'Bundle escaped private derived data'
            info=plistlib.loads((bundle_path/'Contents/Info.plist').read_bytes())
            assert info['CFBundleIdentifier']==expected, 'QA bundle identifier mismatch'
        config.setdefault('EnvironmentVariables',{})['TOGETHER_UI_VERIFIED_APP_PATH']=str(host)
        # xcodebuild does not promise to propagate arbitrary parent variables
        # into the sandboxed test host. Declare the one loopback origin needed
        # by device fixtures explicitly in the generated test configuration.
        if origin := env.get('TOGETHER_UI_RELAY_URL'):
            from urllib.parse import urlsplit
            address=urlsplit(origin)
            assert address.scheme=='http' and address.hostname=='127.0.0.1' and address.port, 'UI fixtures require an explicit loopback Worker'
            assert address.path in ('','/') and not address.username and not address.password and not address.query and not address.fragment, 'Invalid QA origin'
            config.setdefault('EnvironmentVariables',{})['TOGETHER_UI_RELAY_URL']=origin
        runfile.write_bytes(plistlib.dumps(run_configuration))
    except (AssertionError,KeyError,ValueError,OSError) as error:
        isolation_error=str(error)
command=['xcodebuild','test-without-building','-xctestrun',str(runfile),'-destination',f'platform=macOS,arch={platform.machine()}','-resultBundlePath',str(bundle),'-test-timeouts-enabled','YES','-default-test-execution-time-allowance','300','-maximum-test-execution-time-allowance','300']
selected=args.only_test or (['testNavigationAndNoPersistentGiftUI','testTaskActionAndClosableSheet','testPlansFiltersSharedEditorAndHomeRouting','testWishLedgerDetailUsesExistingActions','testCompactLayoutAndReduceMotion','testMenuGiftEditorAndEmptySubmission','testSealedGiftPrivacyAndOneAutomaticModal'] if args.behavior_only else [])
if selected:
 for name in selected:
  command.append('-only-testing:TogetherUITests/TogetherUITests/'+name)
if build.returncode==0 and isolation_error is None:
    with log_path.open('a') as log:
        log.write('QA host and runner bundle identifiers verified before launch.\n');log.flush()
        run=subprocess.run(command,cwd=project,env=env,stdout=log,stderr=subprocess.STDOUT)
else:
    run=build
    if isolation_error:
        run.returncode=65
        with log_path.open('a') as log:log.write('QA isolation preflight refused launch: '+isolation_error+'\n')
summary={'status':'PASS' if run.returncode==0 else 'FAIL','resultBundle':str(bundle),'exitCode':run.returncode,'screenshots':[],'screenshotSHA256':{},'captureDirectory':str(output.relative_to(ROOT)),'skippedPages':['Our Story: not implemented'],'qaHostVerified':build.returncode==0 and isolation_error is None}
summary['buildForTesting']='NOT RUN (explicit verified existing QA artifact)' if args.without_building else 'PASS' if build.returncode==0 else 'FAIL'
log_text=(results/(report_name+'-test.log')).read_text()
if run.returncode!=0 and 'Timed out while enabling automation mode' in log_text and 'Test Case ' not in log_text:
    summary['status']='NOT RUN'
    summary['reason']='macOS XCTest automation mode could not initialize; no UI assertions executed.'
if bundle.exists():
 raw=subprocess.run(['xcrun','xcresulttool','get','test-results','summary','--path',str(bundle),'--format','json'],capture_output=True,text=True)
 if raw.returncode==0:
  try:summary['xcresult']=json.loads(raw.stdout)
  except json.JSONDecodeError:pass
# Export native XCTest attachments outside the sandboxed test runner. The runner
# must not write screenshots into Documents or request new directory access.
if bundle.exists():
    attachments=results/("attachments-"+stamp)
    exported=subprocess.run(['xcrun','xcresulttool','export','attachments','--path',str(bundle),'--output-path',str(attachments)],capture_output=True,text=True)
    manifest=attachments/'manifest.json'
    if exported.returncode==0 and manifest.exists():
        try:
            groups=json.loads(manifest.read_text())
            for group in groups:
                for item in group.get('attachments',[]):
                    name=item.get('suggestedHumanReadableName') or item.get('name','')
                    filename=item.get('exportedFileName') or item.get('filename','')
                    if name and filename and (attachments/filename).exists() and filename.endswith('.png'):
                        import shutil
                        safe=name.removesuffix('.png').split('_0_')[0]
                        if all(c.isalnum() or c in '-_' for c in safe):
                            shutil.copy2(attachments/filename,output/(safe+'.png'))
                            summary['screenshots'].append(safe+'.png')
                            summary['screenshotSHA256'][safe+'.png']=hashlib.sha256((output/(safe+'.png')).read_bytes()).hexdigest()
        except (TypeError,KeyError,json.JSONDecodeError):pass
summary['screenshots']=sorted(set(summary['screenshots']))
(results/(report_name+'.json')).write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n')
print('UI Tests:',summary['status'],'result:',bundle)
sys.exit(run.returncode)
