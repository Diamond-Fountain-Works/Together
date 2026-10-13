#!/usr/bin/env python3
"""Own-view fixture rendering fallback when macOS XCTest automation is unavailable.

Does not use accessibility, capture the desktop or access the production store.
Never substitutes these images for a passed UI behavior test or approved baseline.
"""
from pathlib import Path
import argparse,hashlib,json,os,platform,shutil,subprocess,tempfile,time
p=argparse.ArgumentParser();p.add_argument('--app',required=True);a=p.parse_args()
root=Path(__file__).resolve().parents[1];app=Path(a.app).resolve();binary=app/'Contents/MacOS/Together'
if not binary.exists():p.error('Build the Debug fixture app first')
out=root/'qa/visual/candidates/finance-content';out.mkdir(parents=True,exist_ok=True)
results=[]
cases=[(page,populated,dark,False) for page in ['reserves','expenses','bills','finance-settings'] for populated in [False,True] for dark in [False,True]]
cases += [('expenses',True,dark,True) for dark in [False,True]]
for page,populated,dark,compact in cases:
    name=f'{page}-'+('populated' if populated else 'empty')+'-'+('dark' if dark else 'light')+('-compact-reduced' if compact else '-disconnected')
    with tempfile.TemporaryDirectory(prefix='together-ui-') as folder:
        env=os.environ.copy();env.update(TOGETHER_UI_ROOT=folder,TOGETHER_UI_PAGE=page,TOGETHER_UI_STATE='populated' if populated else 'empty',TOGETHER_UI_MODE='dark' if dark else 'light',TOGETHER_UI_REDUCE_MOTION='1',TOGETHER_UI_COMPACT='1' if compact else '0',TOGETHER_UI_CAPTURE='1',TOGETHER_UI_CASE=name)
        with (root/'qa/results/finance-content-capture.log').open('a') as log:
            process=subprocess.Popen([str(binary),'--ui-testing','-AppleLanguages','(zh-Hans)','-AppleLocale','zh_CN'],env=env,stdout=log,stderr=subprocess.STDOUT)
            try:
                source=Path(folder)/(name+'.png');meta=Path(folder)/'capture.json';deadline=time.monotonic()+25
                while not (source.exists() and meta.exists()) and process.poll() is None and time.monotonic()<deadline:time.sleep(.1)
                if not source.exists() or not meta.exists():results.append({'case':name,'status':'FAIL','reason':'fixture capture did not complete'});continue
                target=out/source.name;shutil.copy2(source,target)
                results.append({'case':name,'status':'CAPTURED','path':str(target.relative_to(root)),'sha256':hashlib.sha256(target.read_bytes()).hexdigest(),'metadata':json.loads(meta.read_text())})
            finally:
                if process.poll() is None:
                    process.terminate()
                    try:process.wait(timeout=5)
                    except subprocess.TimeoutExpired:process.kill();process.wait()
print('Fixture content captures:',sum(v['status']=='CAPTURED' for v in results),'/',len(cases))
report={'status':'FAIL' if any(v['status']=='FAIL' for v in results) else 'REVIEW REQUIRED','source':'AppKit own-view rendering fallback; UI behavior tests are separate','approvedBaselinesReplaced':False,'cases':results}
(root/'qa/results/finance-content-capture.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
raise SystemExit(1 if report['status']=='FAIL' else 0)
