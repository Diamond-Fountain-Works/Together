#!/usr/bin/env python3
"""Audit only static Android UI sources. Never opens Room, user text or media."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET
ROOT = Path(__file__).resolve().parents[1]
CATEGORIES = {'Navigation','Action','Status','Guidance','Empty State','Error','Emotional'}

def audit(root=ROOT):
    index_path = root/'qa/android_copy_review.json'
    index = json.loads(index_path.read_text()) if index_path.exists() else {}
    issues=[]; texts={}; sets={}
    def issue(path,key,kind,severity,suggestion):
        issues.append(dict(path=str(path.relative_to(root)),key=key,type=kind,severity=severity,suggestion=suggestion))
    for path in sorted((root/'apps/android/app/src/main/res').glob('values*/strings.xml')):
        seen=set(); locale=path.parent.name; sets[locale]=seen
        for node in ET.parse(path).getroot():
            key=node.attrib['name']; value=''.join(node.itertext()).replace("\\'", "'"); identity=f'{locale}/{key}'
            if key in seen: issue(path,key,'duplicate_key','Error','Use a unique resource key.')
            seen.add(key); texts[identity]=value
            entry=index.get(identity,{})
            if entry.get('category') not in CATEGORIES or entry.get('sha256') != hashlib.sha256(value.encode()).hexdigest() or entry.get('state') != 'reviewed' or not entry.get('reason'):
                issue(path,key,'unreviewed_copy','Error','Review the exact text, category and context; update its SHA-256.')
            if re.search(r'(?i)lorem ipsum|sample data|placeholder|虚构数据示例|演示数据',value):
                issue(path,key,'placeholder','Error','Remove product placeholder content.')
            category=entry.get('category'); chinese=len(re.findall(r'[\u4e00-\u9fff]',value))
            if (category=='Action' and chinese>8) or (category=='Navigation' and chinese>14) or (category=='Guidance' and chinese>30):
                issue(path,key,'copy_budget','Warning','Review for concision; do not truncate user content or remove necessary security guidance.')
            if len(re.findall(r'[❤♡♥🎉✨💖]',value))>2: issue(path,key,'emoji_density','Warning','Review decorative symbols.')
            if re.search(r'(?i)welcome back|let.s make memories|给彼此留点空间',value): issue(path,key,'decorative_prose','Warning','Remove prose without an actionable purpose.')
    for locale,keys in sets.items():
        for key in sets.get('values',set()) ^ keys:
            issue(root/'apps/android/app/src/main/res'/locale/'strings.xml',key,'locale_coverage','Error','Keep base and translated resource keys aligned.')
    for identity in index.keys()-texts.keys(): issue(index_path,identity,'stale_review','Error','Remove or correct unused review metadata.')
    for path in (root/'apps/android/app/src/main').rglob('*.kt'):
        for line in path.read_text().splitlines():
            if re.search(r'\bText\s*\(\s*"[^"\n]+"|contentDescription\s*=\s*"[^"\n]+"',line):
                issue(path,'literal','visible_literal','Error','Use an audited Android string resource.')
    errors=sum(x['severity']=='Error' for x in issues)
    return dict(status='FAIL' if errors else 'WARN' if issues else 'PASS',entries=len(texts),errors=errors,warnings=len(issues)-errors,issues=issues,scope='Static Android resources and visible Kotlin literals only; user data is excluded.')

def main():
    p=argparse.ArgumentParser();p.add_argument('--json');a=p.parse_args();report=audit()
    if a.json:
        path=ROOT/a.json;path.parent.mkdir(parents=True,exist_ok=True);path.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print(f"Android Copy QA: {report['status']} ({report['entries']} entries; {report['errors']} errors; {report['warnings']} warnings)")
    for x in report['issues']: print(x['severity'],x['path'],x['key'],x['type'])
    return 1 if report['errors'] else 0
if __name__=='__main__': sys.exit(main())
