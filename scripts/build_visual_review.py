#!/usr/bin/env python3
"""Generate an offline, local-only visual review. Never approves or merges."""
from pathlib import Path
from datetime import datetime, timezone
from PIL import Image, ImageChops, ImageStat
import argparse, collections, hashlib, json, re
from compare_visuals import compare, expected_cases, capture_file
from project_paths import ROOT

ASSETS = Path(__file__).with_name('visual_review')
PAGE_NAMES = {
    'home': ('Home', '概览'), 'tasks': ('Plans', 'Pending'),
    'upcoming': ('Plans', 'Upcoming'), 'completed': ('Plans', 'Completed'),
    'wishes': ('Wishes', '愿望账本'), 'gifts': ('Love Gifts', '发送编辑器'),
    'reveal': ('Love Gifts', 'Gift Reveal'), 'settings': ('Settings', '个人设置'),
    'reserves': ('Our Finances', 'United Reserves'),
    'expenses': ('Our Finances', 'Expenses'), 'bills': ('Our Finances', 'Recurring Bills'),
    'bill-editor': ('Our Finances', '账单编辑器'),
    'currency-picker': ('Our Finances', 'Currency Picker'),
    'finance-settings': ('Our Finances', 'Financial Cycle Settings'),
}

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def local_path(path, parent=ROOT):
    resolved = (parent / path).resolve()
    if not resolved.is_relative_to(ROOT.resolve()):
        raise ValueError('Review inputs must stay inside the repository')
    return resolved

def scope_metadata(bundle):
    """Read only exported synthetic XCTest attachment metadata, not a live AX tree."""
    stamp = Path(bundle).stem.removeprefix('ui-')
    folder = ROOT / 'qa/results' / ('attachments-' + stamp)
    manifest = folder / 'manifest.json'
    result = {}
    if not manifest.exists():
        return result
    for group in json.loads(manifest.read_text()):
        for item in group.get('attachments', []):
            name = item.get('suggestedHumanReadableName') or item.get('name', '')
            filename = item.get('exportedFileName') or item.get('filename', '')
            case = name.split('-capture-scope')[0] + '.png'
            if '-capture-scope' not in name or not filename.endswith('.txt'):
                continue
            source = local_path(filename, folder)
            if source.parent != folder.resolve() or not source.exists():
                continue
            text = source.read_text()
            match = re.search(r'scope: (\w+); frame: \(([^)]+)\); fixture window: \(([^)]+)\)', text)
            if match:
                result[case] = {
                    'scope': match[1], 'frame': [float(x) for x in match[2].split(',')],
                    'window': [float(x) for x in match[3].split(',')],
                    'raw': text, 'sourcePath': str(source), 'sourceURL': source.as_uri(),
                    'testIdentifier': group.get('testIdentifier'),
                    'frameRecordedAt': datetime.fromtimestamp(item['timestamp'], timezone.utc).isoformat()
                        if isinstance(item.get('timestamp'), (int, float)) else None,
                }
    return result

def measure(base, candidate, heatmap):
    with Image.open(base) as image:
        a = image.convert('RGB')
    with Image.open(candidate) as image:
        b = image.convert('RGB')
    if a.size != b.size:
        return {'baseSize': list(a.size), 'candidateSize': list(b.size), 'sizeEqual': False}
    channels = ImageChops.difference(a, b).split()
    maximum = ImageChops.lighter(ImageChops.lighter(channels[0], channels[1]), channels[2])
    # Same existing >16 rule. Region metrics are evidence, never an exemption.
    mask = maximum.point(lambda value: 255 if value > 16 else 0)
    total = round(ImageStat.Stat(mask).sum[0] / 255)
    inset = min(64, a.width // 4, a.height // 4)
    center = round(ImageStat.Stat(mask.crop((inset, inset, a.width-inset, a.height-inset))).sum[0] / 255)
    tiles = []
    for y in range(0, a.height, 128):
        for x in range(0, a.width, 128):
            box = (x, y, min(x+128, a.width), min(y+128, a.height))
            count = round(ImageStat.Stat(mask.crop(box)).sum[0] / 255)
            if count:
                tiles.append({'box': list(box), 'pixels': count})
    # Diagnostic mask only; the screenshot pixels and comparison are untouched.
    overlay = Image.new('RGBA', a.size, (199, 65, 78, 0))
    overlay.putalpha(mask.point(lambda value: 210 if value else 0))
    overlay.save(heatmap)
    return {'baseSize': list(a.size), 'candidateSize': list(b.size), 'sizeEqual': True,
            'strongPixels': total, 'centerStrongPixels': center, 'edgeInsetPixels': inset,
            'edgeShare': (total-center)/total if total else 0,
            'strongBBox': list(mask.getbbox()) if total else None,
            'hotspots': sorted(tiles, key=lambda v: v['pixels'], reverse=True)[:8]}

def classify(name, comparison, metrics, old_scope, new_scope):
    evidence = []
    frame_equal = bool(old_scope and new_scope and old_scope['frame'] == new_scope['frame']
                       and old_scope['window'] == new_scope['window'])
    evidence.append('图像尺寸一致' if metrics['sizeEqual'] else '图像尺寸改变，需要检查窗口适配')
    if old_scope and new_scope:
        evidence.append('原生元素和主窗口 Frame 均一致' if frame_equal else '原生元素或主窗口 Frame 有变化')
    else:
        evidence.append('缺少完整 Frame 附件，不能以像素位置代替 AX 证据')
    unresolved = '尚未确认需要 SwiftUI 修复；请人工检查后填写意见。'
    if comparison['severity'] == 'PASS':
        return {'group': '阈值内一致', 'kind': '自动比较通过', 'assessment': '仍未获得 Build 5 人工批准。',
                'evidence': evidence, 'confidence': '仅自动比较结果'}
    if not metrics['sizeEqual']:
        kind, group = '窗口尺寸或捕获范围变化', '布局与窗口适配'
    elif name.startswith('reveal-') and '-normal-opened' in name:
        kind, group = '动画终帧 / 鼠标 Hover 状态', '动画与 Hover'
        evidence += ['普通动效展开后，文字、头像、照片区域存在内部差异。',
                     '完整运行早于指针中性位置修正；另有后续专项运行可对照，不替换本图。',
                     '查看原始图片按钮使用原生 Hover；按钮出现不等于页面新增功能。']
    elif metrics.get('strongPixels') and metrics.get('centerStrongPixels') == 0 and frame_equal:
        group = 'Popover 材质与背景' if name.startswith('currency-picker') else '窗口外缘与背景'
        kind = 'Popover 外缘 / 原生材质背景' if name.startswith('currency-picker') else '桌面背景 / 窗口边框与圆角'
        evidence += [f"强差异 {metrics['strongPixels']} px 全部位于 {metrics['edgeInsetPixels']} px 外缘带。",
                     '中心区域 max RGB >16 的差异为 0；未因此豁免比较或批准。']
        if name.startswith('currency-picker'):
            evidence.append('Popover 超出父窗口边缘，截图会包含后方窗口；位置相同不能消除材质透色。')
    else:
        kind, group = '未充分归因，检查控件 / 文本 / 布局', '人工布局复核'
        evidence.append('现有证据不足以断言文本无截断、控件无遮挡或对比度合格。')
    return {'group': group, 'kind': kind, 'assessment': unresolved, 'evidence': evidence,
            'confidence': '证据支持的候选原因，未经人工认可'}

def build(manifest_path, out, diagnostic_path=None):
    manifest_path = local_path(manifest_path)
    frozen = json.loads(manifest_path.read_text())
    out = local_path(out)
    if not out.is_relative_to((ROOT/'qa/results').resolve()):
        raise ValueError('Generated review must stay in ignored qa/results')
    baseline_root = ROOT/'qa/visual/approved'
    baseline = json.loads((baseline_root/'manifest.json').read_text())['images']
    required = expected_cases(json.loads((ROOT/'qa/project.json').read_text()))
    entries = {item['case']: item for item in frozen['images']}
    if set(entries) != set(required) or len(entries) != len(frozen['images']):
        raise ValueError('Frozen matrix is incomplete or duplicated')
    out.mkdir(parents=True, exist_ok=True)
    masks = out/'differences'; masks.mkdir(exist_ok=True)
    new_scopes = scope_metadata(frozen['sourceResultBundle'])
    old_scopes = {}
    for bundle in {entry['sourceResultBundle'] for entry in baseline.values()}:
        old_scopes.update(scope_metadata(bundle))
    diagnostic = json.loads(local_path(diagnostic_path).read_text()) if diagnostic_path else {}
    items = []
    for index, name in enumerate(required, 1):
        if not re.fullmatch(r'[a-z0-9-]+\.png', name):
            raise ValueError('Unexpected screenshot name')
        current = local_path('images/'+name, manifest_path.parent)
        reference = local_path(name, baseline_root)
        if sha(current) != entries[name]['sha256'] or sha(reference) != baseline[name]['sha256']:
            raise ValueError('Frozen/approved screenshot hash changed: '+name)
        measured = measure(reference, current, masks/name)
        raw = compare(reference, current)
        if raw != entries[name]['comparison']:
            # tuple/list representation differs after JSON decoding only.
            if json.loads(json.dumps(raw)) != entries[name]['comparison']:
                raise ValueError('Frozen comparison disagrees with current bytes: '+name)
        prefix = next(p for p in sorted(PAGE_NAMES, key=len, reverse=True) if name.startswith(p+'-'))
        page, feature = PAGE_NAMES[prefix]
        item = {'id': f'S{index:03}', 'name': name, 'page': page, 'feature': feature,
                'baselinePath': str(reference), 'baselineURL': reference.as_uri(),
                'candidatePath': str(current), 'candidateURL': current.as_uri(),
                'baselineSHA256': baseline[name]['sha256'], 'candidateSHA256': sha(current),
                'differenceURL': (masks/name).as_uri() if measured['sizeEqual'] else None,
                'raw': raw, 'metrics': measured, 'baselineScope': old_scopes.get(name),
                'candidateScope': new_scopes.get(name),
                'analysis': classify(name, raw, measured, old_scopes.get(name), new_scopes.get(name))}
        if name in diagnostic.get('screenshots', []) and diagnostic.get('status') == 'PASS':
            path = capture_file(name, diagnostic)
            item['diagnostic'] = {'path': str(path), 'url': path.as_uri(), 'sha256': sha(path),
                                  'resultBundle': str(diagnostic['resultBundle'])}
        items.append(item)
    data = {'schemaVersion': 1, 'manifestSHA256': sha(manifest_path),
            'manifestPath': str(manifest_path), 'sourceResultBundle': frozen['sourceResultBundle'],
            'ui': {key: frozen[key] for key in ('uiPassed', 'uiFailed', 'uiSkipped')},
            'rawCounts': dict(collections.Counter(item['raw']['severity'] for item in items)),
            'categoryCounts': dict(collections.Counter(item['analysis']['group'] for item in items)),
            'screenshots': items, 'humanApprovalCount': 0,
            'baselineMutated': False, 'remoteWrites': False}
    serialized = json.dumps(data, ensure_ascii=False, indent=2)
    (out/'analysis.json').write_text(serialized+'\n')
    # Script/data stay inline so file:// works without fetch, a server or CDN.
    safe = serialized.replace('<', '\\u003c').replace('\u2028', '\\u2028').replace('\u2029', '\\u2029')
    html = (ASSETS/'index.html').read_text().replace('/* REVIEW_CSS */', (ASSETS/'review.css').read_text())
    html = html.replace('/* REVIEW_DATA */', 'const REVIEW_DATA = '+safe+';')
    html = html.replace('/* REVIEW_JS */', (ASSETS/'review.js').read_text())
    (out/'index.html').write_text(html)
    return data

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest', default='qa/results/build5-visual-review-20261014-214009/manifest.json')
    parser.add_argument('--output', default='qa/results/build5-visual-review-20261014-214009/browser')
    parser.add_argument('--diagnostic', default='qa/results/ui-surfaces-final.json')
    args = parser.parse_args()
    data = build(args.manifest, args.output, args.diagnostic)
    print('Local review:', local_path(args.output)/'index.html')
    print('Raw comparison:', data['rawCounts'], 'human approved: 0')
    print('Cause groups:', data['categoryCounts'])

if __name__ == '__main__':
    main()
