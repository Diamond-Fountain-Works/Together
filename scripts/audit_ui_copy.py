#!/usr/bin/env python3
"""Static product-copy gate. Never opens databases, media, user files or fixtures."""
from pathlib import Path
import argparse, hashlib, json, re, sys
from project_paths import ROOT, APP as PROJECT, CORE
CATALOG=CORE/'Sources/TogetherCore/Resources/UI.xcstrings'
REVIEW=ROOT/'qa/ui_copy_review.json'
CATEGORIES={'Navigation','Action','Status','Guidance','Empty State','Error','Emotional'}
# Swift lexer: understands nested strings in interpolation and ignores comments.
def literals(source):
    found=[]
    def string(start):
        i=start+1; nested=[]
        while i<len(source):
            if source[i]=='\\':
                if i+1<len(source) and source[i+1]=='(':
                    depth=1;i+=2
                    while i<len(source) and depth:
                        if source[i]=='"':
                            end,children=string(i);nested.extend(children);i=end
                        elif source[i]=='(':depth+=1;i+=1
                        elif source[i]==')':depth-=1;i+=1
                        else:i+=1
                else:i+=2
            elif source[i]=='"':
                token=(start,i+1,source[start+1:i]);return i+1,[(token),*nested]
            else:i+=1
        return i,nested
    i=0
    while i<len(source):
        if source.startswith('//',i):
            end=source.find('\n',i);i=len(source) if end<0 else end
        elif source.startswith('/*',i):
            end=source.find('*/',i+2);i=len(source) if end<0 else end+2
        elif source[i]=='"':i,items=string(i);found.extend(items)
        else:i+=1
    return sorted(found,key=lambda t:t[0])
def visible(path,source,start,raw):
    if not raw.strip() or raw.startswith(('http:','https:','ws:','wss:')):return False
    line=source[source.rfind('\n',0,start)+1:start]
    before=source[max(0,start-180):start]
    if 'Copy.text(' in line or 'Copy.format(' in line:return False
    if re.search(r'\b(?:public )?enum\b.*case',line):return False
    if re.search(r'\.(accessibilityIdentifier|keyboardShortcut|matchedGeometryEffect|tag|id)\([^()]*$',line):return False
    if re.search(r'Image\(systemName:[^)]*$',line):return False
    if re.search(r'\b(Text|Button|Label|Toggle|Picker|Menu|TextField|PageHeading|ContentUnavailableView|DatePicker|Stepper|GroupBox|Section|LabeledContent|ProgressView|metric|statistic|AdvisorStep)\s*\([^\n]*$',line):
        if re.search(r'(systemImage|id|icon|imageName)\s*:\s*$',line):return False
        return True
    if re.search(r'\.(help|accessibilityLabel|accessibilityValue|navigationTitle|alert|confirmationDialog)\s*\([^\n]*$',line):return True
    if re.search(r'(messageText|informativeText|errorMessage|error|saveError)\s*=\s*$',line):return True
    if 'addButton(withTitle:' in line or 'TogetherError.invalid(' in line:return True
    if path.name in ['Projector.swift','WishProjector.swift','GiftProjector.swift'] and re.search(r'conflict\([^\n]*$',line):return True
    if path.name=='LoveGift.swift' and source.index('public var displayName')<start<source.index('public protocol DateProvider'):return True
    if 'errorDescription' in before and path.parent.name not in ['Synchronization','Gifts']:return bool(re.search(r'[\u4e00-\u9fff]',raw))
    # Catch indirect Chinese labels/status helpers/arrays in product view code.
    # User values are variables, not literals; test-only content is excluded by path.
    if 'TogetherApp' in path.parts and re.search(r'[\u4e00-\u9fff]',raw):return True
    return False

def scan():
    issues=[]
    def issue(path,key,kind,severity,suggestion):issues.append({'file':str(path.relative_to(ROOT)) if path.is_absolute() else str(path),'id':key,'type':kind,'severity':severity,'suggestion':suggestion})
    if not CATALOG.exists() or not REVIEW.exists():
        issue(CATALOG,'catalog','missing_catalog','Error','Create String Catalog and review metadata.');return issues
    entries=json.loads(CATALOG.read_text())['strings'];entry_paths={key:CATALOG for key in entries}
    platform_catalog=PROJECT/'Sources/TogetherApp/Resources/InfoPlist.xcstrings'
    if platform_catalog.exists():
        for key,entry in json.loads(platform_catalog.read_text())['strings'].items():
            if key in entries:issue(platform_catalog,key,'duplicate_catalog_key','Error','Give each catalog one owning key.')
            entries[key]=entry;entry_paths[key]=platform_catalog
    reviews=json.loads(REVIEW.read_text())['entries'];seen={}
    for key,entry in entries.items():
        entry_path=entry_paths[key]
        text=entry.get('localizations',{}).get('zh-Hans',{}).get('stringUnit',{}).get('value','')
        meta=reviews.get(key,{})
        if meta.get('textSHA256') != hashlib.sha256(text.encode()).hexdigest():issue(REVIEW,key,'changed_since_review','Error','Review this exact catalog value and record its textSHA256; an old key is not approval for changed text.')
        if meta.get('category') not in CATEGORIES:issue(REVIEW,key,'missing_category','Error','Assign one UI copy category.')
        if meta.get('review') not in ['approved','legacy_review','review_required']:issue(REVIEW,key,'unreviewed_copy','Error','Review the new key before acceptance.')
        if meta.get('review') in ['legacy_review','review_required']:issue(REVIEW,key,'human_review','Warning',meta.get('reason','Review copy and context.'))
        if re.search(r'(?i)lorem\s+ipsum|sample\s+data|placeholder|虚构数据示例|演示数据说明',text):issue(entry_path,key,'placeholder_content','Error','Remove fixture/placeholder text from product resources.')
        chinese=len(re.findall(r'[\u4e00-\u9fff]',text))
        budget={'Action':8,'Navigation':14,'Guidance':30,'Empty State':30}.get(meta.get('category'))
        if budget and chinese>budget and not meta.get('budgetException'):issue(entry_path,key,'copy_budget','Warning',f'Review {chinese} Chinese characters against budget {budget}; do not truncate automatically.')
        if re.search(r'[\U0001F300-\U0001FAFF❤♡♥]{3,}',text):issue(entry_path,key,'emoji_density','Warning','Reduce consecutive emoji or document approved emotional feedback.')
        if re.search(r'留一点空间给彼此|精心打造|美好的一天|开启.*美好.*旅程',text) and meta.get('category')!='Emotional':issue(entry_path,key,'decorative_copy','Error','Replace decorative prose with factual UI status/action.')
        if text in seen:issue(entry_path,key,'duplicate_copy','Warning',f'Reuse {seen[text]} unless contexts require independent translation.')
        seen[text]=key
    sourceRoot=PROJECT/'Sources'
    for path in [*sourceRoot.rglob('*.swift'), *(CORE/'Sources').rglob('*.swift')]:
        if 'UITesting' in path.parts or path.name in ['Copy.swift','UIFixture.swift']:continue
        source=path.read_text()
        for match in re.finditer(r'Copy\.(?:text|format)\(\s*"([^"]+)"',source):
            key=match.group(1)
            # A dynamic enum/code suffix is not itself a visible catalog entry.
            # Concrete branches are covered by catalog/enum tests; do not demand
            # a fictitious translation for e.g. "finance.status.".
            if key.endswith('.') and re.match(r'\s*\+',source[match.end():]):continue
            if key not in entries:issue(path,key,'unknown_catalog_key','Error','Register the key in UI.xcstrings and review metadata.')
        for start,end,raw in literals(source):
            line=source[source.rfind('\n',0,start)+1:start]
            if re.search(r'Copy\.(?:text|format)\([^)]*$',line):
                if re.match(r'^(copy|nav|role|gift|status|setup|finance)\.',raw) and raw not in entries and not (raw.endswith('.') and re.match(r'\s*\+',source[end:])):issue(path,raw,'unknown_catalog_key','Error','Register every conditional catalog key, not only the first branch.')
            if visible(path,source,start,raw):
                if raw in ['', ' ']:continue
                issue(path,f'line:{source.count(chr(10),0,start)+1}', 'visible_literal','Error','Move this static text/template to the catalog; leave user data untouched.')
    notes=PROJECT/'Sources/TogetherApp/Resources/ReleaseNotes.json'
    if notes.exists():
        for entry in json.loads(notes.read_text()):
            for n,highlight in enumerate(entry.get('highlights',[])):
                for field in ['title','details']:
                    if field in highlight:issue(notes,f'{entry.get("version")}.{n}.{field}','uncatalogued_release_copy','Error','Use titleKey/detailsKey and reviewed catalog copy.')
    return issues

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--json');args=parser.parse_args()
    issues=scan();errors=sum(i['severity']=='Error' for i in issues);warnings=len(issues)-errors
    report={'status':'FAIL' if errors else 'WARN' if warnings else 'PASS','errors':errors,'warnings':warnings,'issues':issues}
    if args.json:
        p=ROOT/args.json;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print(f'Copy QA: {report["status"]} ({errors} errors, {warnings} warnings)')
    for i in issues[:30]:print(f'{i["severity"]}: {i["file"]}:{i["id"]} [{i["type"]}] {i["suggestion"]}')
    return 1 if errors else 0
if __name__=='__main__':sys.exit(main())
