#!/usr/bin/env python3
"""Together-only Samsung UI: cached sealed gift, real restart, explicit audio and native SAF.

Uses generated QA media only. Does not operate on the user's gallery, unlock the phone, grant
permissions, uninstall, clear data, or change radio/keyboard settings. Screenshots stay local.
"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import secrets
import struct
import time
import xml.etree.ElementTree as ET
from run_android_physical_qa import PhysicalRun, ROOT, PACKAGE


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--serial',required=True);p.add_argument('--expect-model',required=True);p.add_argument('--relay',required=True)
    p.add_argument('--authorize-physical-test-app',action='store_true',required=True)
    p.add_argument('--label',default='physical-lifecycle-'+time.strftime('%Y%m%d-%H%M%S'))
    args=p.parse_args()
    run=PhysicalRun(args.serial,args.expect_model,args.relay,ROOT/'qa/results/android-phase-c'/args.label);run.preflight()
    candidates=ROOT/'qa/visual/candidates/android-phase-c'/args.label;candidates.mkdir(parents=True,exist_ok=True)
    tokens=secrets.token_hex(32).upper();sequence=0;result={'status':'FAIL','visualStatus':'CANDIDATE'}
    allowed={PACKAGE,PACKAGE+'.test','com.android.documentsui','com.google.android.documentsui','com.samsung.android.honeyboard'}
    copies={}
    for directory in ['values','values-zh-rCN']:
        for element in ET.parse(ROOT/'apps/android/app/src/main/res'/directory/'strings.xml').getroot():
            if element.tag=='string':copies.setdefault(element.get('name'),set()).add(''.join(element.itertext()))
    def labels(key):return copies.get(key,{key})
    def tree():
        nonlocal sequence
        raw=run.adb('exec-out','uiautomator','dump','/dev/tty',timeout=25).stdout.decode(errors='replace')
        if '<?xml' not in raw:raise RuntimeError('UI tree unavailable; phone may need manual unlock')
        root=ET.fromstring(raw[raw.index('<?xml'):raw.index('</hierarchy>')+12])
        foreground={n.get('package') for n in root.iter('node') if n.get('package')}
        assert foreground & allowed,'Unexpected foreground/lock screen. Manual action required; no automated unlock.'
        sequence+=1
        # External file pickers may list user filenames. Keep only UI bounds/control identifiers;
        # never save that text/tree or take a screenshot of unrelated files.
        if foreground <= {PACKAGE,PACKAGE+'.test','com.samsung.android.honeyboard'}:
            (run.out/f'ui-{sequence:03d}.xml').write_text(raw)
        return root
    def matches(n,value):
        values=labels(value)
        return n.get('text') in values or n.get('content-desc') in values or n.get('resource-id')==value
    def find(value,root):return [n for n in root.iter('node') if matches(n,value) and n.get('package') in allowed and n.get('enabled')=='true' and re.findall(r'\d+',n.get('bounds',''))[-2:]!=['0','0']]
    def wait(value,timeout=20):
        deadline=time.monotonic()+timeout
        while time.monotonic()<deadline:
            root=tree()
            if find(value,root):return root
            time.sleep(.2)
        raise AssertionError('Missing QA UI control: '+value)
    def tap(value):
        root=wait(value);nodes=find(value,root);assert len(nodes)==1,(value,len(nodes))
        bounds=list(map(int,re.findall(r'\d+',nodes[0].get('bounds'))));x1,y1,x2,y2=bounds
        assert x2>x1 and y2>y1
        run.adb('shell','input','tap',str((x1+x2)//2),str((y1+y2)//2))
    def swipe_to(value):
        for _ in range(6):
            root=tree()
            if find(value,root):return
            scroll=[n for n in root.iter('node') if n.get('scrollable')=='true' and n.get('package')==PACKAGE]
            assert scroll,'No Together scroll container for '+value
            x1,y1,x2,y2=map(int,re.findall(r'\d+',scroll[-1].get('bounds')))
            run.adb('shell','input','swipe',str((x1+x2)//2),str(int(y1+(y2-y1)*.8)),str((x1+x2)//2),str(int(y1+(y2-y1)*.25)),'300')
        raise AssertionError('QA control remains outside scroll viewport: '+value)
    def capture(name):
        root=tree();assert any(n.get('package')==PACKAGE for n in root.iter('node'))
        (candidates/(name+'.png')).write_bytes(run.adb('exec-out','screencap','-p').stdout)
    def instrument(method,label,extra):
        r=run.instrument('com.together.android.GiftLaunchRuntimeTest#'+method,label,extra,120)
        assert r['status']=='PASS',r
    def read_plan():return json.loads(run.adb('exec-out','run-as',PACKAGE,'cat','files/phase-b-launch.json').stdout)
    def launch(plan):
        namespace=plan['namespace'];assert re.fullmatch('[A-Z0-9-]{1,45}',namespace)
        permit=json.dumps({'namespace':namespace,'token':tokens,'expiresAt':int(time.time()*1000)+900_000}).encode()
        run.adb('shell','-T','run-as',PACKAGE,'sh','-c',"'cat > no_backup/physical-qa-permit.json'",input=permit)
        run.adb('shell','am','force-stop',PACKAGE)
        started=time.monotonic()
        output=run.adb('shell','am','start','-W','-n',PACKAGE+'/com.together.android.qa.BusinessQaActivity','--es','qaNamespace',namespace,'--es','qaClock',plan['clock'],'--es','qaPhysicalToken',tokens).stdout.decode()
        (run.out/f'launch-{sequence:03d}.txt').write_text(output)
        return round((time.monotonic()-started)*1000,2)
    before=run.adb('reverse','--list').stdout.decode();same=[l for l in before.splitlines() if l.split()[-2:-1]==[run.port]]
    assert not same,'This standalone driver owns a dedicated, initially unused reverse port'
    run.adb('reverse',run.port,run.port)
    try:
        instrument('prepareCachedGiftForActualProcessRestart','prepare',{'prepareLaunch':'true'})
        plan=read_plan();(run.out/'plan.json').write_text(json.dumps(plan,indent=2))
        assert re.fullmatch('[A-Za-z0-9.-]+',plan['photoFilename'])
        run.adb('shell','am','force-stop',PACKAGE);run.adb('reverse','--remove',run.port)
        launch(plan);sealed=wait('action_open_gift')
        assert 'Synthetic private gift sentinel' not in ET.tostring(sealed).decode()
        assert not find('action_play',sealed) and not find('action_save_photo',sealed)
        capture('cached-offline-sealed')
        launch(plan);second=wait('Together')
        assert not find('action_open_gift',second)
        run.adb('shell','am','force-stop',PACKAGE)
        instrument('inspectPersistedPresentationAfterProcessDeath','inspect-sealed',{'inspectLaunch':'true'})
        launch(plan)
        tap('app.actions');tap('action_gift_history');tap('action_view_gift');tap('action_open_gift')
        swipe_to('action_save_photo');opened=wait('action_save_photo');assert find('action_play',opened),'Voice must not autoplay'
        capture('opened-before-save')
        tap('action_save_photo');wait('android:id/button1')
        # A uniquely generated fixture filename cannot replace a user's existing photograph.
        tap('android:id/button1')
        wait('action_save_photo')
        exported=run.adb('exec-out','cat','/sdcard/Download/'+plan['photoFilename']).stdout
        assert len(exported)==plan['photoBytes'] and hashlib.sha256(exported).hexdigest()==plan['photoHash'],'Original export must preserve every byte'
        assert exported[:8]==b'\x89PNG\r\n\x1a\n'
        width,height=struct.unpack('>II',exported[16:24])
        assert find('action_play',tree()),'Save must not start voice playback'
        tap('action_play');deadline=time.monotonic()+15;completed=False
        while time.monotonic()<deadline:
            root=tree()
            if find('action_play',root) and find('0:03 / 0:03',root):completed=True;break
            time.sleep(.2)
        assert completed,'Explicit voice playback did not complete'
        capture('opened-original-and-audio')
        tap('action_gift_received')
        tap('action_close')
        tap('app.actions');tap('action_send_gift');tap('action_add_photo')
        # Select only this run's freshly exported, uniquely named synthetic picture. Never select
        # a gallery item or unrelated document. Missing item stops QA instead of choosing another.
        tap(plan['photoFilename'])
        wait('action_remove_photo');capture('native-photo-picker-imported')
        tap('action_cancel')
        run.adb('shell','am','force-stop',PACKAGE)
        instrument('inspectNativePhotoDraftAfterPicker','inspect-photo-draft',{'inspectPhotoDraft':'true','expectedPhotoHash':plan['photoHash']})
        # Leave/return to this Activity and then terminate/restart its process.
        launch(plan)
        run.adb('shell','input','keyevent','KEYCODE_HOME');launch(plan)
        assert not find('action_open_gift',wait('Together'))
        run.adb('shell','am','force-stop',PACKAGE)
        instrument('inspectPersistedPresentationAfterProcessDeath','inspect-opened',{'inspectLaunch':'true','expectOpened':'true'})
        result.update(status='PASS',physicalDevice=True,actualProcessRestart=True,cachedWithoutRelay=True,autoPresentedOnce=True,sealedPrivacy=True,manualAudio=True,nativeSAF=True,nativePhotoSelection=True,originalBytes=len(exported),originalSHA256=plan['photoHash'],originalPNGDimensions=[width,height],exportPath='/sdcard/Download/'+plan['photoFilename'])
    finally:
        run.adb('shell','am','force-stop',PACKAGE,check=False)
        run.adb('shell','run-as',PACKAGE,'rm','-f','no_backup/physical-qa-permit.json',check=False)
        run.adb('reverse','--remove',run.port,check=False)
        (run.out/'result.json').write_text(json.dumps(result,indent=2));print(json.dumps(result),flush=True)


if __name__=='__main__':main()
