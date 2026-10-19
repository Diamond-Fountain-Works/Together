#!/usr/bin/env python3
"""Create two fail-closed QA bundles, never install them in Applications.

Build the UITesting host first. The two copies have distinct QA bundle IDs,
owner-only databases/keys and loopback relay origins. They are test artifacts,
not two production installations. No production data/defaults are read.
"""
from pathlib import Path
import argparse,json,os,plistlib,shutil,subprocess,tempfile,time
ROOT=Path(__file__).resolve().parents[1]
def require(value,message):
    if not value:raise RuntimeError(message)
def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--qa-app',type=Path,required=True);a=p.parse_args()
    source=a.qa_app.resolve();info=plistlib.loads((source/'Contents/Info.plist').read_bytes())
    require(info['CFBundleIdentifier']=='com.together.app.qa','Verified QA host required')
    require(source.is_relative_to(ROOT.parent/'qa/results') or source.is_relative_to(ROOT/'qa/results'),'QA artifact root required')
    output=ROOT/'qa/results'/('qa-twins-'+time.strftime('%Y%m%d-%H%M%S'));output.mkdir(parents=True,mode=0o700)
    temporary=Path(tempfile.mkdtemp(prefix='together-ui-twins-'));temporary.chmod(0o700)
    rows=[]
    for label,port,latency,rate in [('a',8891,80,131072),('b',8892,450,65536)]:
        bundle=output/f'Together QA {label.upper()}.app';subprocess.run(['ditto',str(source),str(bundle)],check=True)
        path=bundle/'Contents/Info.plist';values=plistlib.loads(path.read_bytes())
        values.update(CFBundleIdentifier='com.together.app.qa.'+label,CFBundleDisplayName='Together QA '+label.upper(),CFBundleName='Together QA '+label.upper())
        path.write_bytes(plistlib.dumps(values))
        subprocess.run(['codesign','--force','--sign','-','--entitlements',str(ROOT/'apps/apple/macOS/Sources/TogetherApp/Resources/Together.entitlements'),str(bundle)],check=True,capture_output=True)
        subprocess.run(['codesign','--verify','--deep','--strict',str(bundle)],check=True,capture_output=True)
        data=temporary/(temporary.name+'-'+label);data.mkdir(mode=0o700)
        control=output/('network-'+label+'.json');control.write_text(json.dumps({'latencyMs':latency,'bytesPerSecond':rate,'offline':False})+'\n')
        rows.append({'label':label,'bundle':str(bundle),'bundleID':values['CFBundleIdentifier'],'root':str(data),'origin':f'http://127.0.0.1:{port}','control':str(control)})
    manifest=output/'twins.json';manifest.write_text(json.dumps(rows,indent=2)+'\n');print(manifest)
if __name__=='__main__':main()
