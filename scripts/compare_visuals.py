#!/usr/bin/env python3
"""Compare approved immutable screenshots; never replaces a baseline."""
from pathlib import Path
import argparse,json,hashlib,sys
from PIL import Image,ImageChops
ROOT=Path(__file__).resolve().parents[1];BASE=ROOT/'qa/visual/approved';CANDIDATES=ROOT/'qa/visual/candidates'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def expected_cases(config):
 matrix=config['candidateMatrix'];cases=[]
 for page in matrix['ordinaryPages']:
  for state in matrix['states']:
   for mode in matrix['modes']:cases.append(f"{page}-{state}-{mode}-{matrix['network']}.png")
 for mode in matrix['modes']:
  for motion in matrix['motion']:
   for state in matrix['reveal']:cases.append(f'reveal-{mode}-{motion}-{state}.png')
 cases.extend(matrix.get('additionalCases',[]))
 return cases
def compare(base,candidate):
 a=Image.open(base).convert('RGB');b=Image.open(candidate).convert('RGB')
 if a.size!=b.size:return {'severity':'FAIL','reason':'dimensions changed','baseSize':a.size,'candidateSize':b.size}
 delta=ImageChops.difference(a,b);pixels=list(delta.get_flattened_data());changed=sum(max(rgb)>16 for rgb in pixels);ratio=changed/len(pixels);box=delta.getbbox()
 return {'severity':'PASS' if changed==0 else 'FAIL' if ratio>0.02 else 'REVIEW REQUIRED','changedRatio':ratio,'bbox':box}
def main():
 p=argparse.ArgumentParser();p.add_argument('--self-test',action='store_true');a=p.parse_args()
 manifest=BASE/'manifest.json';approved=json.loads(manifest.read_text()).get('images',{}) if manifest.exists() else {};results=[]
 config=json.loads((ROOT/'qa/project.json').read_text());required=expected_cases(config)
 capture=ROOT/'qa/results/ui.json';run=json.loads(capture.read_text()) if capture.exists() else {}
 current=set(run.get('screenshots',[]));missing=sorted(set(required)-current)
 for key in missing:results.append({'case':key,'severity':'FAIL','reason':'missing from current XCTest capture run; old candidates cannot supply evidence'})
 for key in sorted(current & set(required)):
  candidate=CANDIDATES/key
  if not candidate.exists():results.append({'case':key,'severity':'FAIL','reason':'current capture file missing'});continue
  key=candidate.name;entry=approved.get(key)
  if not entry:results.append({'case':key,'severity':'REVIEW REQUIRED','reason':'no human-approved baseline','candidateSHA256':sha(candidate)});continue
  base=BASE/key
  if not base.exists() or sha(base)!=entry['sha256']:results.append({'case':key,'severity':'FAIL','reason':'approved baseline modified or missing'});continue
  results.append({'case':key,**compare(base,candidate)})
 status='NOT RUN' if not results else 'FAIL' if any(r['severity']=='FAIL' for r in results) else 'REVIEW REQUIRED' if any(r['severity']!='PASS' for r in results) else 'PASS'
 report={'status':status,'resultBundle':run.get('resultBundle'),'comparisons':results,'requiredCaptureCount':len(required),'capturedCount':len(current & set(required)),'missingPages':config['unimplementedPages'],'approvalPolicy':'Only a user-approved reviewed image hash may enter approved/.'}
 out=ROOT/'qa/results/visual.json';out.parent.mkdir(parents=True,exist_ok=True);out.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print('Visual QA:',status,len(results),'captures')
 return 1 if status in ['FAIL','NOT RUN'] else 2 if status=='REVIEW REQUIRED' else 0
if __name__=='__main__':sys.exit(main())
