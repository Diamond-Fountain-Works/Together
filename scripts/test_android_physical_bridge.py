#!/usr/bin/env python3
"""Actual Samsung over USB reverse <-> isolated native Swift QA process, never public Wi-Fi.

Only signed public enrollment files, synthetic fixture bytes and diagnostic summaries are copied.
Private keys remain on the device that generated them. No macOS App is launched.
"""
from pathlib import Path
import argparse
import concurrent.futures
import json
import math
import os
import random
import secrets
import struct
import subprocess
import tempfile
import time
import wave
import zlib
from run_android_physical_qa import PhysicalRun, ROOT, PACKAGE


def sample_media(directory):
    rng=random.Random(7)
    def chunk(kind,data):
        return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data)&0xffffffff)
    pixels=b''.join(b'\0'+bytes(rng.randrange(256) for _ in range(256*3)) for _ in range(256))
    (directory/'synthetic.png').write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',256,256,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(pixels))+chunk(b'IEND',b''))
    with wave.open(str(directory/'synthetic.wav'),'wb') as w:
        w.setnchannels(1);w.setsampwidth(2);w.setframerate(16000)
        w.writeframes(b''.join(struct.pack('<h',int(math.sin(i/20)*1500)) for i in range(48000)))


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--serial',required=True);parser.add_argument('--expect-model',required=True)
    parser.add_argument('--relay',required=True);parser.add_argument('--label',default='native-physical-'+time.strftime('%Y%m%d-%H%M%S'));parser.add_argument('--authorize-physical-test-app',action='store_true',required=True)
    args=parser.parse_args()
    run=PhysicalRun(args.serial,args.expect_model,args.relay,ROOT/'qa/results/android-phase-c'/args.label)
    run.preflight()
    root=Path(tempfile.mkdtemp(prefix='together-c-physical-')).resolve();root.chmod(0o700)
    (root/'launch.json').write_text(json.dumps({'base':args.relay}))
    sample_media(root)
    phone_dir='files/physical-bridge/'+run.run_id
    run.adb('shell','run-as',PACKAGE,'mkdir','-p',phone_dir)
    def push(name):
        assert name in ['offer.json','completion.json','native-created.json','native-offline-written','native-checkpoint.json','native-revoked','synthetic.png','synthetic.wav']
        run.adb('shell','-T','run-as',PACKAGE,'sh','-c',"'cat > "+phone_dir+'/'+name+"'",input=(root/name).read_bytes())
    def pull(name):
        assert name in ['request.json','phone-created.json','phone-offline.json','phone-reconnected.json','phone-restarted.json','phone-revoked.json','phone-diagnostic.json']
        r=run.adb('exec-out','run-as',PACKAGE,'cat',phone_dir+'/'+name,check=False)
        if r.returncode==0 and r.stdout.lstrip().startswith(b'{'):
            try: json.loads(r.stdout)
            except json.JSONDecodeError: return False  # File is being atomically published.
            (root/name).write_bytes(r.stdout);return True
        return False
    env=os.environ.copy();env.update(TOGETHER_RUN_PHYSICAL_ANDROID_BRIDGE='1',TOGETHER_PHYSICAL_BRIDGE_DIR=str(root))
    log=(run.out/'native-swift.log').open('wb')
    native=subprocess.Popen(['/usr/bin/swift','test','--package-path',str(ROOT/'packages/together-core-swift'),'--filter','AndroidPhysicalBridgeTests'],cwd=ROOT,env=env,stdout=log,stderr=subprocess.STDOUT)
    before=run.adb('reverse','--list').stdout.decode();same=[l for l in before.splitlines() if l.split()[-2:-1]==[run.port]]
    assert not same or all(l.split()[-2:]==[run.port,run.port] for l in same)
    added=not same
    if added:run.adb('reverse',run.port,run.port)
    copied=set(); result={'status':'FAIL','transport':'physical USB adb reverse; not public Wi-Fi','nativeHost':'isolated Swift Testing process; not graphical Mac app','root':str(root)}
    executor=concurrent.futures.ThreadPoolExecutor(max_workers=1)
    try:
        deadline=time.monotonic()+180
        while not (root/'offer.json').exists():
            assert native.poll() is None,'Native QA host exited before offer; see native-swift.log'
            assert time.monotonic()<deadline,'Native QA host initialization timed out'
            time.sleep(.2)
        for name in ['offer.json','native-created.json','synthetic.png','synthetic.wav']:push(name);copied.add(name)
        future=executor.submit(run.instrument,'com.together.android.PhysicalBridgeTest#enrolledPhysicalPhoneExchangesBusinessAndPersistsForRestart','phone-initial',{'physicalBridgeId':run.run_id},300)
        def pump(future):
            while not future.done():
                for name in ['request.json','phone-created.json','phone-offline.json','phone-reconnected.json','phone-restarted.json','phone-revoked.json']:
                    if name not in copied and pull(name):copied.add(name)
                for name in ['completion.json','native-offline-written','native-checkpoint.json','native-revoked']:
                    if name not in copied and (root/name).exists():push(name);copied.add(name)
                assert native.poll() is None or (root/'native-result.json').exists(),'Native QA host failed; see retained diagnostics'
                time.sleep(.1)
            return future.result()
        initial=pump(future);assert initial['status']=='PASS',initial
        for name in ['phone-reconnected.json','phone-diagnostic.json']:pull(name)
        deadline=time.monotonic()+30
        while not (root/'native-checkpoint.json').exists():
            assert native.poll() is None;assert time.monotonic()<deadline;time.sleep(.1)
        push('native-checkpoint.json')
        # am instrument launches a new target process after this explicit force-stop. No clear/uninstall.
        run.adb('shell','am','force-stop',PACKAGE)
        future=executor.submit(run.instrument,'com.together.android.PhysicalBridgeTest#identityAckAndMediaSurviveActualForceStopThenRevocationRejectsAccess','phone-restart-revoke',{'physicalBridgeId':run.run_id},240)
        restarted=pump(future);assert restarted['status']=='PASS',restarted
        pull('phone-revoked.json')
        deadline=time.monotonic()+30
        while not (root/'native-result.json').exists():
            assert native.poll() is None;assert time.monotonic()<deadline;time.sleep(.1)
        assert native.wait(timeout=30)==0
        result.update(status='PASS',native=json.loads((root/'native-result.json').read_text()),phone=json.loads((root/'phone-revoked.json').read_text()))
    finally:
        if native.poll() is None:native.terminate();native.wait(timeout=15)
        log.close()
        executor.shutdown(wait=True)
        try: pull('phone-diagnostic.json')
        except (RuntimeError,subprocess.SubprocessError): pass
        for name in ['native-result.json','native-diagnostic.json','native-timing.json','native-checkpoint.json','phone-created.json','phone-reconnected.json','phone-restarted.json','phone-revoked.json','phone-diagnostic.json']:
            if (root/name).exists():(run.out/name).write_bytes((root/name).read_bytes())
        result['copiedStages']=sorted(copied)
        (run.out/'result.json').write_text(json.dumps(result,indent=2))
        if added:run.adb('reverse','--remove',run.port,check=False)
        print(json.dumps(result),flush=True)


if __name__=='__main__':main()
