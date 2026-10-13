#!/usr/bin/env python3
"""Register one reviewed static entry. Default requires human review."""
import argparse,hashlib,json
from audit_ui_copy import CATALOG,REVIEW,CATEGORIES
p=argparse.ArgumentParser();p.add_argument('key');p.add_argument('text');p.add_argument('--category',required=True,choices=sorted(CATEGORIES));p.add_argument('--context',required=True);p.add_argument('--approved-reason');a=p.parse_args()
c=json.loads(CATALOG.read_text());r=json.loads(REVIEW.read_text())
if a.key in c['strings']:raise SystemExit('Key exists; edit its reviewed entry explicitly.')
c['strings'][a.key]={'comment':a.category+'; '+a.context,'localizations':{'zh-Hans':{'stringUnit':{'state':'translated','value':a.text}}}}
r['entries'][a.key]={'category':a.category,'context':a.context,'review':'approved' if a.approved_reason else 'review_required','reason':a.approved_reason or 'Human review needed before acceptance.','textSHA256':hashlib.sha256(a.text.encode()).hexdigest()}
CATALOG.write_text(json.dumps(c,ensure_ascii=False,indent=2)+'\n');REVIEW.write_text(json.dumps(r,ensure_ascii=False,indent=2)+'\n')
