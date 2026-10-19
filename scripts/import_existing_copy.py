#!/usr/bin/env python3
"""One-time mechanical inventory. Review required for legacy/over-budget prose.
Not called by QA: this script never approves future additions automatically.
"""
from pathlib import Path
import hashlib,json,re,sys
sys.path.insert(0,str(Path(__file__).parent))
from audit_ui_copy import ROOT,literals,visible,CATALOG,REVIEW
from project_paths import APP, CORE
if CATALOG.exists() or REVIEW.exists():
 raise SystemExit("Initial inventory already exists. Review individual catalog changes; never re-import/auto-approve it.")
entries={};review={};values={}
def add(value,category,context,key=None):
 if value in values:return values[value]
 key=key or 'copy.'+category.lower().replace(' ','_')+'.'+hashlib.sha256(value.encode()).hexdigest()[:12]
 values[value]=key
 entries[key]={'comment':f'{category}; {context}', 'localizations':{'zh-Hans':{'stringUnit':{'state':'translated','value':value}}}}
 legacy=category=='Guidance' and len(re.findall(r'[\u4e00-\u9fff]',value))>30
 review[key]={'category':category,'context':context,'review':'review_required' if legacy else 'approved','reason':'Existing product inventory; long guidance requires human copy review.' if legacy else 'Existing product/action copy or explicitly requested scope; no invented user data.'}
 return key

def classify(path,source,start,raw):
 line=source[source.rfind('\n',0,start)+1:start]
 if 'TogetherError.invalid' in line or path.parent.name in ['Synchronization','Media'] or 'conflict(' in line:return 'Error'
 if path.name in ['LoveGift.swift','GiftRevealView.swift','GiftEditorView.swift'] and ('❤️' in raw or '♡' in raw or '爱意' in raw or '情话' in raw):return 'Emotional'
 if re.search(r'\b(Button|addButton)\(',line) or 'addButton(withTitle:' in line:return 'Action'
 if re.search(r'\b(TextField|Picker|Toggle)\(',line):return 'Guidance'
 if 'PageHeading' in line or raw in ['Home','Tasks','Wishes','Upcoming','Completed','Connection','Settings','Shared Tasks','Your Profile','Welcome','Together Advisor',"What's New",'Love Gift History','New Task','Edit Task']:return 'Navigation'
 if 'ContentUnavailableView' in line or '没有' in raw:return 'Empty State'
 if len(raw)<30:return 'Status'
 return 'Guidance'

def interpolate(raw):
 parts=[];args=[];i=0
 while i<len(raw):
  if raw.startswith('\\(',i):
   depth=1;j=i+2;start=j
   while j<len(raw) and depth:
    if raw[j]=='"':
     j+=1
     while j<len(raw) and raw[j]!='"':j+=2 if raw[j]=='\\' else 1
     j+=1
    elif raw[j]=='(':depth+=1;j+=1
    elif raw[j]==')':depth-=1;j+=1
    else:j+=1
   expr=raw[start:j-1];args.append('String(describing: '+expr+')');parts.append('%@');i=j
  else:
   parts.append('%%' if raw[i]=='%' else raw[i]);i+=1
 return ''.join(parts).replace('\\n','\n').replace('\\"','"'),args

for path in [*APP.joinpath('Sources').rglob('*.swift'), *CORE.joinpath('Sources').rglob('*.swift')]:
 if path.name in ['Copy.swift','LoveGift.swift']:continue
 source=path.read_text();chosen=[]
 for start,end,raw in literals(source):
  if visible(path,source,start,raw):
   if any(a<=start and end<=b for a,b,_ in chosen):continue
   chosen.append((start,end,raw))
 for start,end,raw in reversed(chosen):
  value,args=interpolate(raw);category=classify(path,source,start,raw)
  key=add(value,category,str(path.relative_to(ROOT)))
  replacement=f'Copy.format("{key}", '+', '.join(args)+')' if args else f'Copy.text("{key}")'
  source=source[:start]+replacement+source[end:]
 path.write_text(source)
# Role copy is parameterized explicitly to avoid modifying canonical parser values.
path=CORE/'Sources/TogetherCore/Gifts/LoveGift.swift';source=path.read_text()
a=source.index('    public var displayName:');b=source.index('public protocol DateProvider')
role_values={'role.boyfriend':'Boyfriend / 男朋友','role.girlfriend':'Girlfriend / 女朋友','role.unknown':'未设置','role.affection.boyfriend':'小男友','role.affection.girlfriend':'小女友','role.affection.unknown':'TA','role.pronoun.boyfriend':'他','role.pronoun.girlfriend':'她',
 'gift.prompt.unknown':'今天有什么想对 TA 说的话吗？❤️','gift.prompt.known':'今天有什么想和%@说的情话吗？❤️','gift.title.unknown.text':'这是 TA 专门送给你的一份爱意 ♡','gift.title.unknown.attachment':'这是 TA 专门送给你的一份小礼物 ♡','gift.title.known.text':'这是%@专门送给你的情话 ♡','gift.title.known.attachment':'这是%@专门送给你的小礼物 ♡','gift.intro.unknown':'TA 悄悄为你准备了一份爱意 ❤️','gift.intro.known':'%@充满爱地给你送来了一份小礼物 ❤️','gift.avatar.unknown':'让 TA 一眼心动的照片 ♡','gift.avatar.known':'让%@一眼心动的照片 ♡','gift.ending.unknown':'收到这份爱意了吗？快去找 TA 聊聊天吧 ❤️','gift.ending.known':'收到这份爱意了吗？快去找%@聊聊天吧 ❤️'}
for k,v in role_values.items():add(v,'Emotional' if k.startswith('gift.') else 'Status','User-approved relationship copy',k)
# alias TA has one canonical key
TA=values['TA']
source=source[:a]+'''    public var displayName: String { switch self { case .boyfriend: Copy.text("role.boyfriend"); case .girlfriend: Copy.text("role.girlfriend"); case .unknown: Copy.text("role.unknown") } }
    public var affectionateName: String { switch self { case .boyfriend: Copy.text("role.affection.boyfriend"); case .girlfriend: Copy.text("role.affection.girlfriend"); case .unknown: Copy.text("'''+TA+'''") } }
    public var pronoun: String { switch self { case .boyfriend: Copy.text("role.pronoun.boyfriend"); case .girlfriend: Copy.text("role.pronoun.girlfriend"); case .unknown: Copy.text("'''+TA+'''") } }
}
public enum LoveCopy {
    public static func prompt(partner: RelationshipLabel) -> String { partner == .unknown ? Copy.text("gift.prompt.unknown") : Copy.format("gift.prompt.known", partner.affectionateName) }
    public static func title(sender: RelationshipLabel, hasText: Bool) -> String {
        if sender == .unknown { return Copy.text(hasText ? "gift.title.unknown.text" : "gift.title.unknown.attachment") }
        return Copy.format(hasText ? "gift.title.known.text" : "gift.title.known.attachment", sender.affectionateName)
    }
    public static func introduction(sender: RelationshipLabel) -> String { sender == .unknown ? Copy.text("gift.intro.unknown") : Copy.format("gift.intro.known", sender.affectionateName) }
    public static func avatarPrompt(partner: RelationshipLabel) -> String { partner == .unknown ? Copy.text("gift.avatar.unknown") : Copy.format("gift.avatar.known", partner.affectionateName) }
    public static func ending(sender: RelationshipLabel) -> String { sender == .unknown ? Copy.text("gift.ending.unknown") : Copy.format("gift.ending.known", sender.pronoun) }
}
'''+source[b:]
# Non-UI persistence keys and relationship parser values remain unchanged.
path.write_text(source)
# Release notes use catalog references.
notes=APP/'Sources/TogetherApp/Resources/ReleaseNotes.json';releases=json.loads(notes.read_text())
for release in releases:
 for item in release['highlights']:
  if item['title']=='Two Macs, One Space':item['details']='邀请码配对、双方身份确认及原生中继连接。正式服务部署和跨 Wi-Fi 验收状态见项目测试报告。'
  item['titleKey']=add(item.pop('title'),'Navigation','Release notes')
  item['detailsKey']=add(item.pop('details'),'Guidance','Release notes')
notes.write_text(json.dumps(releases,ensure_ascii=False,indent=2)+'\n')
CATALOG.write_text(json.dumps({'sourceLanguage':'zh-Hans','version':'1.0','strings':entries},ensure_ascii=False,indent=2)+'\n')
REVIEW.write_text(json.dumps({'version':1,'entries':review},ensure_ascii=False,indent=2)+'\n')
print(f'Inventoried {len(entries)} catalog entries; long guidance remains review_required.')
