#!/usr/bin/env python3
"""Publication gate: paths/content in tracked work plus all refs/reflog blobs.

Never opens Application Support, Keychain, ignored runtime files or credentials.
Reports locations and rule names only; never prints a matched secret value.
This is a repository data/credential check, not a cryptographic security audit.
"""
from pathlib import Path
import argparse, hashlib, json, re, subprocess, sys

ROOT = Path(__file__).resolve().parents[1]
RULES = {
    'private_key_pem': re.compile(rb'-----BEGIN (?:RSA |EC |OPENSSH |DSA |ENCRYPTED )?PRIVATE KEY-----'),
    'github_token': re.compile(rb'\bgh[pousr]_[A-Za-z0-9_]{20,}\b|\bgithub_pat_[A-Za-z0-9_]{30,}\b'),
    'aws_access_key': re.compile(rb'\b(?:AKIA|ASIA)[A-Z0-9]{16}\b'),
    'literal_credential': re.compile(rb'''(?i)(?:password|api[_-]?key|cloudflare[_-]?api[_-]?token|auth[_-]?secret|pairing[_-]?secret|relay[_-]?secret)\s*[=:]\s*["']([^"'\r\n]{8,})["']'''),
}
FORBIDDEN = re.compile(r'(?i)(?:^|/)(?:\.env(?:\.[^/]+)?|\.dev\.vars(?:\.[^/]+)?|[^/]+\.(?:sqlite|sqlite3|db|store)(?:-wal|-shm)?|[^/]+\.(?:key|p12|pfx|jks|keystore|mobileprovision)|[^/]+\.(?:m4a|mp3|wav|aiff|mp4|mov|heic|jpe?g))$')
RUNTIME = re.compile(r'(?:^|/)(?:node_modules|DerivedData|\.derivedData|\.build|\.wrangler|\.git|\.qa-runtime|\.QA-runtime|dist)(?:/|$)|^qa/(?:results|reports/local)/')

def git(*args):
    return subprocess.run(['git', '-C', str(ROOT), *args], check=True, capture_output=True).stdout

def findings(path, data, scope):
    result = []
    def add(rule, line=None):
        result.append({'scope':scope, 'path':path, 'rule':rule, 'severity':'Error', 'line':line})
    template = path.endswith(('.env.example', '.env.template', '.dev.vars.example'))
    if FORBIDDEN.search(path) and not template: add('private_data_or_credential_file')
    if RUNTIME.search(path): add('tracked_runtime_artifact')
    if data.startswith(b'SQLite format 3\x00'): add('sqlite_content')
    for rule, pattern in RULES.items():
        for match in pattern.finditer(data):
            if rule == 'literal_credential' and (match.group(1) in [b'REPLACE_ME', b'YOUR_TOKEN_HERE'] or b'${' in match.group(1)):
                continue
            add(rule, data[:match.start()].count(b'\n') + 1)
    if path.lower().endswith('.png'):
        icon = '/Resources/Assets.xcassets/AppIcon.appiconset/' in path or '/Resources/IconSource/' in path
        synthetic_capture = path.startswith(('qa/visual/approved/', 'qa/visual/reviews/'))
        if not (icon or synthetic_capture): add('image_requires_provenance_review')
    return result

def scan(history=True):
    issues = []; paths = git('ls-files', '-z').decode().split('\x00'); paths = [p for p in paths if p]
    for path in paths:
        file = ROOT / path
        if file.is_symlink():
            issues.append({'scope':'worktree','path':path,'rule':'tracked_symlink_review','severity':'Error'})
        elif file.is_file(): issues.extend(findings(path, file.read_bytes(), 'worktree'))
    blobs = 0; commits = []
    if history:
        commits = sorted(set(git('rev-list','--all','--reflog').decode().splitlines()))
        # rev-list names a shared blob only once. Inspect every historical tree
        # path too, so a renamed .env/database cannot hide behind a safe alias.
        seen_paths = set()
        for commit in commits:
            for row in git('ls-tree','-r','-z',commit).decode().split('\x00'):
                if '\t' not in row: continue
                _, path = row.split('\t',1)
                if path not in seen_paths:
                    seen_paths.add(path)
                    issues.extend(findings(path,b'', 'historical_path'))
        objects = git('rev-list','--objects','--all','--reflog').decode().splitlines()
        for row in objects:
            oid, _, path = row.partition(' ')
            if git('cat-file','-t',oid).strip() != b'blob': continue
            blobs += 1
            for issue in findings(path, git('cat-file','blob',oid), 'history'):
                issue['blobId'] = oid; issues.append(issue)
    # Ensure screenshot publication refers to the exact approved synthetic set.
    manifest = ROOT/'qa/visual/approved/manifest.json'
    if manifest.exists():
        for name, entry in json.loads(manifest.read_text()).get('images',{}).items():
            image = manifest.parent/name
            if not image.exists() or hashlib.sha256(image.read_bytes()).hexdigest() != entry['sha256']:
                issues.append({'scope':'worktree','path':str(image.relative_to(ROOT)),'rule':'visual_provenance_hash','severity':'Error'})
    unique = list({json.dumps(x,sort_keys=True):x for x in issues}.values())
    return {'status':'FAIL' if unique else 'PASS','trackedFileCount':len(paths),'historyBlobCount':blobs,'recoverableCommitCount':len(commits),'recoverableCommits':commits,'errors':len(unique),'issues':unique,'scope':'Tracked source plus every ref/reflog-reachable blob; excluded runtime/real user data stays local.','limitations':['Not an independent application security review','Media approval uses deterministic-fixture capture provenance; not OCR of arbitrary user photos','No claim to detect every possible unlabeled secret'],'ignoredRuntimeUploaded':False}

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--json');parser.add_argument('--no-history',action='store_true');args=parser.parse_args()
    report=scan(not args.no_history)
    if args.json:
        path=ROOT/args.json;path.parent.mkdir(parents=True,exist_ok=True);path.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print('Repository Safety:',report['status'],'files:',report['trackedFileCount'],'historical blobs:',report['historyBlobCount'],'issues:',report['errors'])
    for item in report['issues'][:25]:print(item['scope'],item['path'],item['rule'],item.get('line',''))
    return 1 if report['errors'] else 0
if __name__=='__main__':sys.exit(main())
