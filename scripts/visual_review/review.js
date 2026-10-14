(() => {
  'use strict';
  const data = REVIEW_DATA;
  const byId = new Map(data.screenshots.map(item => [item.id, item]));
  const $ = id => document.getElementById(id);
  const storageKey = 'together-visual-feedback-v1-' + data.manifestSHA256;
  const labels = {pending: '待复核', changes_requested: '提出修改', approved: '人工认可'};
  let records = {}, selected = null, mode = 'side', mix = 50, zoom = 100, fit = true;
  let storageAvailable = true;
  function notice(message) { $('notice').textContent = message; }
  function validRecord(record, item) {
    return record && record.baselineSHA256 === item.baselineSHA256 &&
      record.candidateSHA256 === item.candidateSHA256 &&
      ['unconfirmed', 'yes', 'no'].includes(record.needsFix) &&
      Object.hasOwn(labels, record.finalStatus) && typeof record.feedback === 'string';
  }
  try {
    const saved = JSON.parse(localStorage.getItem(storageKey) || '{}');
    for (const [id, record] of Object.entries(saved)) {
      if (byId.has(id) && validRecord(record, byId.get(id))) records[id] = record;
    }
  } catch (_) {
    storageAvailable = false;
    notice('浏览器不允许本地存储。反馈暂存在本页内存，请关闭前导出 JSON。');
  }
  function recordFor(item) {
    return records[item.id] || {needsFix: 'unconfirmed', feedback: '', finalStatus: 'pending',
      baselineSHA256: item.baselineSHA256, candidateSHA256: item.candidateSHA256};
  }
  function filtered() {
    const query = $('search').value.trim().toLowerCase();
    return data.screenshots.filter(item =>
      ($('status-filter').value === 'all' || item.raw.severity === $('status-filter').value) &&
      ($('category-filter').value === 'all' || item.analysis.group === $('category-filter').value) &&
      [item.id, item.name, item.page, item.feature].join(' ').toLowerCase().includes(query));
  }
  function element(tag, className, text) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined) node.textContent = text;
    return node;
  }
  function tag(text, status) {
    return element('span', 'tag ' + (status === 'PASS' ? 'pass' : status === 'FAIL' ? 'fail' : 'review'), text);
  }
  function refreshNavigation() {
    const list = filtered(), nav = $('screenshot-list');
    nav.replaceChildren();
    const groups = new Map();
    for (const item of list) {
      if (!groups.has(item.page)) {
        const group = element('details'); group.open = true;
        group.append(element('summary', '', item.page));
        nav.append(group); groups.set(item.page, group);
      }
      const button = element('button', item.id === selected ? 'active' : '', item.id + ' · ' + item.feature);
      button.type = 'button'; button.dataset.screenshot = item.id;
      button.setAttribute('aria-current', item.id === selected ? 'true' : 'false');
      button.append(element('small', '', item.name),
        element('span', 'human', item.raw.severity + ' · ' + labels[recordFor(item).finalStatus]));
      button.addEventListener('click', () => select(item.id));
      groups.get(item.page).append(button);
    }
    if (!list.length) nav.append(element('p', 'empty', '没有匹配的截图。'));
    const approved = Object.values(records).filter(record => record.finalStatus === 'approved').length;
    $('human-count').textContent = '人工认可 ' + approved + ' / ' + data.screenshots.length;
    $('raw-counts').textContent = ['PASS', 'REVIEW REQUIRED', 'FAIL'].map(key => key + ' ' + (data.rawCounts[key] || 0)).join(' · ');
    const index = list.findIndex(item => item.id === selected);
    $('position').textContent = index < 0 ? '0 / ' + list.length : (index + 1) + ' / ' + list.length;
    $('previous').disabled = index <= 0; $('next').disabled = index < 0 || index >= list.length - 1;
  }
  function sourceLink(label, url) {
    const link = element('a', '', label); link.href = url; link.target = '_blank'; link.rel = 'noopener';
    return link;
  }
  function regions(item) {
    const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    svg.setAttribute('viewBox', '0 0 ' + item.metrics.baseSize.join(' '));
    svg.setAttribute('aria-hidden', 'true');
    const boxes = item.metrics.strongBBox ? [item.metrics.strongBBox, ...item.metrics.hotspots.map(t => t.box)] : [];
    boxes.forEach((box, index) => {
      const rect = document.createElementNS(svg.namespaceURI, 'rect');
      for (const [key, value] of Object.entries({x: box[0], y: box[1], width: box[2]-box[0], height: box[3]-box[1],
        fill: 'none', stroke: index ? '#db8d20' : '#c33460', 'stroke-width': index ? 1 : 2,
        'stroke-dasharray': index ? '4 4' : '8 4', 'vector-effect': 'non-scaling-stroke'})) rect.setAttribute(key, value);
      svg.append(rect);
    });
    svg.toggleAttribute('hidden', !$('show-regions').checked);
    return svg;
  }
  function image(url, className, alt) {
    const img = element('img', className); img.src = url; img.alt = alt; img.draggable = false;
    img.addEventListener('error', () => notice('原图未能加载：请保留项目目录，使用本地生成的 index.html。'));
    return img;
  }
  function updateMix() {
    $('mix-label').textContent = mix + '%'; $('mix').value = mix;
    document.querySelectorAll('.new-layer').forEach(layer => {
      layer.style.opacity = mode === 'overlay' ? mix / 100 : 1;
      layer.style.clipPath = mode === 'wipe' ? 'inset(0 ' + (100-mix) + '% 0 0)' : 'none';
    });
    document.querySelectorAll('.wipe-line').forEach(line => { line.style.left = mix + '%'; });
  }
  function resizeImages() {
    let firstScale = null;
    document.querySelectorAll('.artboard').forEach(board => {
      const viewport = board.parentElement, width = Number(board.dataset.width), height = Number(board.dataset.height);
      const scale = fit ? Math.min((viewport.clientWidth-24)/width, (viewport.clientHeight-24)/height) : zoom/100;
      board.style.width = Math.max(1, width*scale) + 'px'; board.style.height = Math.max(1, height*scale) + 'px';
      if (firstScale === null) firstScale = scale;
    });
    if (firstScale !== null) {
      $('zoom-label').textContent = (fit ? '适应 · ' : '') + Math.round(firstScale*100) + '%';
      $('zoom').value = Math.max(10, Math.min(400, Math.round(firstScale*100)));
    }
  }
  function renderComparison(item) {
    const comparison = $('comparison'); comparison.replaceChildren(); comparison.classList.toggle('single', mode !== 'side');
    const sizeEqual = item.metrics.sizeEqual;
    if (!sizeEqual && mode !== 'side') { mode = 'side'; notice('截图尺寸不同，请使用并排模式检查窗口适配。'); }
    comparison.classList.toggle('single', mode !== 'side');
    document.querySelectorAll('#modes button').forEach(button => {
      button.setAttribute('aria-pressed', button.dataset.mode === mode ? 'true' : 'false');
      button.disabled = !sizeEqual && button.dataset.mode !== 'side';
    });
    $('mix-control').hidden = mode === 'side';
    $('mix-title').textContent = mode === 'overlay' ? 'Build 5 不透明度' : 'Build 5 覆盖比例（也可在图上拖动）';
    const sides = mode === 'side' ? ['baseline', 'candidate'] : ['combined'];
    for (const side of sides) {
      const panel = element('div', 'image-panel'), label = element('div', 'image-label');
      const title = side === 'baseline' ? 'Build 4 · Approved' : side === 'candidate' ? 'Build 5 · 待人工认可' : 'Build 4 ↓ / Build 5 ↑';
      label.append(element('strong', '', title), sourceLink('原图', side === 'baseline' ? item.baselineURL : item.candidateURL));
      const viewport = element('div', 'viewport'), board = element('div', 'artboard');
      const size = side === 'candidate' ? item.metrics.candidateSize : item.metrics.baseSize;
      board.dataset.width = size[0]; board.dataset.height = size[1];
      board.append(image(side === 'candidate' ? item.candidateURL : item.baselineURL, '', title));
      if (side === 'combined') {
        board.append(image(item.candidateURL, 'new-layer', 'Build 5 当前截图'));
        if (mode === 'wipe') {
          board.append(element('div', 'wipe-line')); board.style.cursor = 'ew-resize'; board.style.touchAction = 'none';
          const drag = event => {
            const rect = board.getBoundingClientRect(); mix = Math.round(Math.max(0, Math.min(100, (event.clientX-rect.left)/rect.width*100))); updateMix();
          };
          board.addEventListener('pointerdown', event => { board.setPointerCapture(event.pointerId); drag(event); });
          board.addEventListener('pointermove', event => { if (board.hasPointerCapture(event.pointerId)) drag(event); });
        }
      }
      if (item.differenceURL && sizeEqual) {
        const heatmap = image(item.differenceURL, 'heatmap', 'max RGB >16 差异像素'); heatmap.hidden = !$('show-mask').checked;
        board.append(heatmap, regions(item));
      }
      viewport.append(board); panel.append(label, viewport); comparison.append(panel);
    }
    let syncing = false;
    comparison.querySelectorAll('.viewport').forEach(viewport => viewport.addEventListener('scroll', () => {
      if (syncing || mode !== 'side' || !sizeEqual) return;
      syncing = true;
      comparison.querySelectorAll('.viewport').forEach(other => { if (other !== viewport) { other.scrollTop = viewport.scrollTop; other.scrollLeft = viewport.scrollLeft; } });
      requestAnimationFrame(() => { syncing = false; });
    }));
    updateMix(); resizeImages();
  }
  function select(id) {
    const item = byId.get(id); if (!item) return; selected = id;
    $('screenshot-id').textContent = item.id;
    $('page-title').textContent = item.page + ' · ' + item.feature;
    $('screenshot-name').textContent = item.name;
    $('result-badges').replaceChildren(tag(item.raw.severity, item.raw.severity),
      element('span', 'tag', '强差异 ' + (item.raw.changedRatio*100).toFixed(4) + '%'));
    $('classification').textContent = item.analysis.group + ' · ' + item.analysis.kind;
    $('assessment').textContent = item.analysis.assessment;
    $('evidence').replaceChildren(...item.analysis.evidence.map(text => element('li', '', text)));
    const provenance = $('provenance'); provenance.replaceChildren();
    for (const [label, path, url, hash, scope] of [
      ['Build 4', item.baselinePath, item.baselineURL, item.baselineSHA256, item.baselineScope],
      ['Build 5', item.candidatePath, item.candidateURL, item.candidateSHA256, item.candidateScope]]) {
      const block = element('p', 'provenance'); block.append(sourceLink(label + ' 原图', url),
        document.createTextNode('\n' + path + '\nSHA-256 ' + hash + '\n' + (scope ? scope.raw + '\nFrame 附件时间：' + (scope.frameRecordedAt || '未记录') + '\nXCTest：' + (scope.testIdentifier || '未记录') : '没有可用 Frame 附件')));
      if (scope) block.append(sourceLink('查看原始 Frame 附件', scope.sourceURL));
      provenance.append(block);
    }
    if (item.diagnostic) {
      const p = element('p', 'provenance', '后续专项运行（仅辅助证据，不替换本次截图）：\n' + item.diagnostic.resultBundle + '\n');
      p.append(sourceLink('查看指针中性位置专项截图', item.diagnostic.url)); provenance.append(p);
    }
    const record = recordFor(item); $('needs-fix').value = record.needsFix; $('feedback').value = record.feedback;
    $('final-status').value = record.finalStatus;
    $('saved-status').textContent = record.updatedAt ? '本机保存：' + new Date(record.updatedAt).toLocaleString() : '尚未填写人工意见。';
    refreshNavigation(); renderComparison(item);
  }
  function saveFeedback() {
    if (!selected) return;
    const item = byId.get(selected);
    records[selected] = {...recordFor(item), needsFix: $('needs-fix').value, feedback: $('feedback').value,
      finalStatus: $('final-status').value, updatedAt: new Date().toISOString()};
    try { localStorage.setItem(storageKey, JSON.stringify(records)); }
    catch (_) { storageAvailable = false; notice('反馈仅暂存内存；请在关闭前导出 JSON。'); }
    $('saved-status').textContent = storageAvailable ? '已保存在本机浏览器。' : '暂存在内存，请导出。';
    refreshNavigation();
  }
  for (const group of Object.keys(data.categoryCounts)) {
    const option = element('option', '', group + ' · ' + data.categoryCounts[group]); option.value = group; $('category-filter').append(option);
  }
  for (const id of ['search', 'status-filter', 'category-filter']) $(id).addEventListener(id === 'search' ? 'input' : 'change', () => {
    const list = filtered();
    if (list.length && !list.some(item => item.id === selected)) select(list[0].id);
    else refreshNavigation();
  });
  for (const [id, offset] of [['previous', -1], ['next', 1]]) $(id).addEventListener('click', () => {
    const list = filtered(), index = list.findIndex(item => item.id === selected), next = list[index+offset]; if (next) select(next.id);
  });
  document.addEventListener('keydown', event => {
    if (['INPUT', 'TEXTAREA', 'SELECT', 'BUTTON'].includes(event.target.tagName)) return;
    if (event.key === 'ArrowLeft') $('previous').click(); if (event.key === 'ArrowRight') $('next').click();
  });
  document.querySelectorAll('#modes button').forEach(button => button.addEventListener('click', () => { mode = button.dataset.mode; renderComparison(byId.get(selected)); }));
  $('zoom').addEventListener('input', () => { fit = false; zoom = Number($('zoom').value); resizeImages(); });
  $('fit').addEventListener('click', () => { fit = true; resizeImages(); });
  $('actual-size').addEventListener('click', () => { fit = false; zoom = 100; resizeImages(); });
  window.addEventListener('resize', resizeImages);
  $('mix').addEventListener('input', () => { mix = Number($('mix').value); updateMix(); });
  $('show-regions').addEventListener('change', () => { document.querySelectorAll('.artboard svg').forEach(svg => { svg.toggleAttribute('hidden', !$('show-regions').checked); }); });
  $('show-mask').addEventListener('change', () => { document.querySelectorAll('.heatmap').forEach(mask => { mask.hidden = !$('show-mask').checked; }); });
  $('feedback').addEventListener('input', saveFeedback);
  for (const id of ['needs-fix', 'final-status']) $(id).addEventListener('change', saveFeedback);
  $('export-feedback').addEventListener('click', () => {
    const payload = {schemaVersion: 1, manifestSHA256: data.manifestSHA256, exportedAt: new Date().toISOString(),
      scope: 'Local human feedback; not baseline mutation or merge authorization',
      screenshots: data.screenshots.map(item => ({id: item.id, name: item.name, ...recordFor(item)}))};
    const url = URL.createObjectURL(new Blob([JSON.stringify(payload, null, 2) + '\n'], {type: 'application/json'}));
    const anchor = element('a'); anchor.href = url; anchor.download = 'together-build5-visual-feedback.json'; anchor.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
    notice('已导出本地反馈。请在聊天中提供反馈或导出文件路径；本页没有上传任何内容。');
  });
  $('import-feedback').addEventListener('click', () => $('feedback-file').click());
  $('feedback-file').addEventListener('change', async () => {
    const file = $('feedback-file').files[0]; if (!file) return;
    try {
      const payload = JSON.parse(await file.text()), imported = {};
      if (payload.schemaVersion !== 1 || payload.manifestSHA256 !== data.manifestSHA256 || !Array.isArray(payload.screenshots)) throw Error('清单版本或哈希不匹配');
      for (const record of payload.screenshots) {
        const item = byId.get(record.id);
        if (!item || record.name !== item.name || !validRecord(record, item) || Object.hasOwn(imported, record.id)) throw Error('截图 ID、哈希或反馈格式不匹配');
        imported[record.id] = record;
      }
      records = {...records, ...imported};
      try { localStorage.setItem(storageKey, JSON.stringify(records)); } catch (_) { storageAvailable = false; }
      select(selected); notice('已导入本地人工意见；未更新批准基线，未上传或合并。');
    } catch (error) { notice('未导入反馈：' + error.message); }
    $('feedback-file').value = '';
  });
  $('manifest-hash').textContent = '冻结清单 SHA-256：' + data.manifestSHA256 + '\n' + data.manifestPath + '\nXCUITest：' + data.ui.uiPassed + ' PASS / ' + data.ui.uiFailed + ' FAIL / ' + data.ui.uiSkipped + ' SKIP';
  select(filtered()[0]?.id || data.screenshots[0].id);
})();
