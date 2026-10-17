#!/usr/bin/env python3
"""Actual Phase A APK -> Phase B replacement, dedicated synthetic emulator only.
Does not read host user stores or install anything on a Mac/physical handset.
"""
import argparse,hashlib,json,os,re,shutil,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--serial',required=True);p.add_argument('--phase-a-apk',required=True,type=Path);p.add_argument('--phase-a-sha256',required=True);p.add_argument('--relay',required=True);p.add_argument('--allow-qa-downgrade',action='store_true');a=p.parse_args()
adb=shutil.which('adb')
if not adb:sys.exit('Put the existing SDK platform-tools on PATH.')
def run(*args):return subprocess.check_output([adb,'-s',a.serial,*args],stderr=subprocess.STDOUT,text=True,timeout=120)
if not re.fullmatch(r'emulator-\d+',a.serial) or run('shell','getprop','ro.kernel.qemu').strip()!='1':sys.exit('Dedicated emulator required; physical-device operation refused.')
if not re.fullmatch(r'http://127\.0\.0\.1:\d+',a.relay):sys.exit('Explicit loopback-only test Relay required.')
if hashlib.sha256(a.phase_a_apk.read_bytes()).hexdigest()!=a.phase_a_sha256:sys.exit('Phase A APK hash mismatch; no install performed.')
new=ROOT/'apps/android/app/build/outputs/apk/debug/app-debug.apk';tests=ROOT/'apps/android/app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk'
if not(new.is_file() and tests.is_file()):sys.exit('Build both Debug APK and test APK first.')
sdk=Path(adb).resolve().parent.parent
build_tools=sorted((sdk/'build-tools').glob('*/apksigner'))
if not build_tools:sys.exit('Existing Android build-tools are required.')
tools=build_tools[-1].parent
for apk,version in ((a.phase_a_apk,'0.2.1-phaseA'),(new,'0.2.1-phaseB')):
 badging=subprocess.check_output([str(tools/'aapt2'),'dump','badging',str(apk)],text=True)
 if "package: name='com.together.android.debug'" not in badging or "versionName='"+version+"'" not in badging:sys.exit('Unexpected APK identity/version; no install performed.')
def certificate(apk):
 output=subprocess.check_output([str(tools/'apksigner'),'verify','--print-certs',str(apk)],text=True)
 return re.findall(r'certificate SHA-256 digest: ([0-9a-f]+)',output)
if not certificate(new) or certificate(new)!=certificate(a.phase_a_apk):sys.exit('APK signing identities differ; data-preserving replacement refused.')
package='com.together.android.debug';runner=package+'.test/com.together.android.IsolatedAndroidTestRunner'
probe=subprocess.run([adb,'-s',a.serial,'shell','pm','path',package],capture_output=True,text=True,timeout=20)
if probe.returncode not in (0,1):probe.check_returncode()
installed=probe.stdout.strip()
if installed and not a.allow_qa_downgrade:sys.exit('Existing QA installation found; explicit --allow-qa-downgrade is required. No data will be deleted.')
out=ROOT/'qa/results/android-phase-b/apk-upgrade';out.mkdir(parents=True,exist_ok=True)
for apk in (a.phase_a_apk,tests):print(run('install','-r',*(['-d'] if a.allow_qa_downgrade and apk==a.phase_a_apk else []),str(apk)).strip())
port=a.relay.rsplit(':',1)[1];run('reverse','tcp:'+port,'tcp:'+port)
def phase(seed):
 text=run('shell','am','instrument','-w','-r','-e','class','com.together.android.PhaseAUpgradeTest','-e','upgradeSeed','true' if seed else 'false','-e','relayURL',a.relay,runner)
 (out/('seed.log' if seed else 'verify.log')).write_text(text)
 if 'OK (1 test)' not in text or 'FAILURES' in text or 'INSTRUMENTATION_FAILED' in text:sys.exit('Upgrade phase failed; logs retained at '+str(out))
 print('SEED PASS' if seed else 'VERIFY PASS')
phase(True)
print(run('install','-r',str(new)).strip());print(run('install','-r',str(tests)).strip());phase(False)
for name in ('before','after'):
 raw=run('exec-out','run-as',package,'cat','files/synthetic-upgrade/'+name+'.json')
 (out/(name+'.json')).write_text(raw)
result=json.loads((out/'after.json').read_text());assert result['status']=='PASS'
result.update({'baselineSHA256':a.phase_a_sha256,'targetSHA256':hashlib.sha256(new.read_bytes()).hexdigest(),'physicalDevice':False,'appDataDeleted':False,'macInstall':False})
(out/'result.json').write_text(json.dumps(result,indent=2)+'\n');print('Actual APK replacement: PASS; all facts, key and binding retained.')
