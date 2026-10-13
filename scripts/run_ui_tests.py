#!/usr/bin/env python3
from pathlib import Path
import os, json, platform, subprocess, sys
import argparse,re
parser=argparse.ArgumentParser();parser.add_argument('--behavior-only',action='store_true');parser.add_argument('--only-test',action='append',default=[]);args=parser.parse_args()
if any(not re.fullmatch(r'test[A-Za-z0-9_]+',name) for name in args.only_test):parser.error('--only-test requires a XCTest method name')
ROOT=Path(__file__).resolve().parents[1]
project=ROOT/json.loads((ROOT/'qa/project.json').read_text())['projectDirectory'];results=ROOT/'qa/results';results.mkdir(parents=True,exist_ok=True)
output=ROOT/'qa/visual/candidates';output.mkdir(parents=True,exist_ok=True)
# New run path; never removes or overwrites an approved result bundle/baseline.
import datetime
stamp=datetime.datetime.now().strftime('%Y%m%d-%H%M%S');bundle=results/f'ui-{stamp}.xcresult'
env=os.environ.copy()
derived=Path.home()/'.cache/Together/UIQA-DerivedData'
derived.mkdir(parents=True,exist_ok=True)
subprocess.run([sys.executable,'script/generate_project.py'],cwd=project,check=True,env=env)
command=['xcodebuild','-project','Together.xcodeproj','-scheme','Together','-configuration','Debug','-destination',f'platform=macOS,arch={platform.machine()}','-derivedDataPath',str(derived),'-resultBundlePath',str(bundle),'-test-timeouts-enabled','YES','-default-test-execution-time-allowance','300','-maximum-test-execution-time-allowance','300','test']
selected=args.only_test or (['testNavigationAndNoPersistentGiftUI','testTaskActionAndClosableSheet','testPlansFiltersSharedEditorAndHomeRouting','testWishLedgerDetailUsesExistingActions','testCompactLayoutAndReduceMotion','testMenuGiftEditorAndEmptySubmission','testSealedGiftPrivacyAndOneAutomaticModal'] if args.behavior_only else [])
if selected:
 for name in selected:
  command.append('-only-testing:TogetherUITests/TogetherUITests/'+name)
with (results/'ui-test.log').open('w') as log:run=subprocess.run(command,cwd=project,env=env,stdout=log,stderr=subprocess.STDOUT)
summary={'status':'PASS' if run.returncode==0 else 'FAIL','resultBundle':str(bundle),'exitCode':run.returncode,'screenshots':[],'skippedPages':['Our Story: not implemented']}
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
        except (TypeError,KeyError,json.JSONDecodeError):pass
summary['screenshots']=sorted(set(summary['screenshots']))
(results/'ui.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n')
print('UI Tests:',summary['status'],'result:',bundle)
sys.exit(run.returncode)
