'use strict';
/* 界面：一块手机大小的舞台，五个标签页，弹出面板和整屏的开场。 */

const $ = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => Array.from(r.querySelectorAll(s));
const esc = (s) => String(s === null || s === undefined ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const ICONS = {
  home: 'M3 11 12 3l9 8M5 10v11h14V10M9 21v-7h6v7', task: 'M9 5h11v16H4V5h3M8 3h8v4H8zM8 12l2 2 5-5M8 18h8', council: 'M4 4h16v12H9l-5 4zM8 8h8M8 12h5',
  mask: 'M4 5c3 1 5 1 8 0 3 1 5 1 8 0v7c0 5-4 8-8 9-4-1-8-4-8-9zM8 10h2M14 10h2M9 15c2 1.5 4 1.5 6 0', wave: 'M4 10v4M8 6v12M12 3v18M16 7v10M20 10v4',
  arrow: 'm9 5 7 7-7 7', back: 'm15 5-7 7 7 7', plus: 'M12 5v14M5 12h14', check: 'm5 12 4 4L19 6', close: 'm6 6 12 12M18 6 6 18',
  map: 'm3 6 6-2 6 3 6-2v14l-6 2-6-3-6 2zM9 4v14M15 7v14', music: 'M9 18V6l10-2v12M9 18a3 3 0 1 1-6 0 3 3 0 0 1 6 0M19 16a3 3 0 1 1-6 0 3 3 0 0 1 6 0',
  moon: 'M20 15A8 8 0 0 1 9 4a8 8 0 1 0 11 11', sound: 'M11 5 6 9H3v6h3l5 4zM15 9a4 4 0 0 1 0 6M18 6a8 8 0 0 1 0 12',
  gear: 'M12 9a3 3 0 1 0 0 6 3 3 0 0 0 0-6M12 2v3M12 19v3M4.2 4.2l2.1 2.1M17.7 17.7l2.1 2.1M2 12h3M19 12h3M4.2 19.8l2.1-2.1M17.7 6.3l2.1-2.1',
  lock: 'M7 10V7a5 5 0 0 1 10 0v3M5 10h14v11H5zM12 14v3', timer: 'M12 8v5l3 2M21 13a9 9 0 1 1-18 0 9 9 0 0 1 18 0M9 2h6', play: 'M7 4v16l13-8z', pause: 'M7 4v16M17 4v16',
  scissors: 'M6 9a3 3 0 1 0 0-6 3 3 0 0 0 0 6M6 21a3 3 0 1 0 0-6 3 3 0 0 0 0 6M20 4 8.1 15.9M14.5 14.5 20 20M8.1 8.1 12 12',
  eye: 'M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12M15 12a3 3 0 1 1-6 0 3 3 0 0 1 6 0', hand: 'M8 13V5a1.5 1.5 0 0 1 3 0v6M11 11V3.5a1.5 1.5 0 0 1 3 0V11M14 11V5a1.5 1.5 0 0 1 3 0v9c0 4-2.5 7-6.5 7S5 18.5 4 15l-1-3a1.5 1.5 0 0 1 2.8-1L8 13',
  door: 'M5 21V3h10v18M15 6l4 1v13l-4 1M11 12h.01M3 21h18', pen: 'M4 20h4L20 8l-4-4L4 16zM14 6l4 4', sparkle: 'm12 3 2 6 6 2-6 2-2 6-2-6-6-2 6-2z', walk: 'M5 12h14M13 6l6 6-6 6', drag: 'M8 7 4 12l4 5M16 7l4 5-4 5M4 12h16',
};
const icon = (n) => `<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="${ICONS[n] || ICONS.sparkle}"/></svg>`;

const Atmo = {
  html(scene = 'chapel', quiet = false) {
    return `<div class="atmo atmo-${scene}${quiet ? ' quiet' : ''}" aria-hidden="true"><div class="atmo-img art-pano_${scene}"></div><div class="atmo-glow"></div><div class="atmo-scrim"></div><div class="atmo-fog a"></div><div class="atmo-fog b"></div><i class="atmo-string"></i><i class="atmo-string"></i><i class="atmo-string"></i><i class="atmo-string"></i><div class="atmo-eyes"><i></i><i></i></div><div class="atmo-grain art-grain"></div><div class="atmo-vig"></div></div>`;
  },
};
window.Atmo = Atmo;
// 暗处的眼睛每次换个地方睁开。
document.addEventListener('animationiteration', (e) => {
  if (e.target.classList && e.target.classList.contains('atmo-eyes')) {
    e.target.style.left = 10 + Math.random() * 74 + '%';
    e.target.style.top = 8 + Math.random() * 22 + '%';
  }
}, true);

/* 页面之间的去向。 */
const UI = {
  tab: 'village', route: null, councilMode: 'slips', councilTask: null, sheet: null, cover: null,
  echoTab: 'day', echoDay: null, drafts: {}, wantsAdd: false,
  village: { yaw: 3, pitch: 0, selected: null },
  talk: { game: null, candidate: null, session: '', recorded: false },
  prefs: { seen: 'board,theater,fire,tower', lookHint: false, onboarded: false },
  PREFS: 'human-content-demo-ui-v1',
  load() { try { Object.assign(this.prefs, JSON.parse(localStorage.getItem(this.PREFS) || '{}')); } catch (e) {} },
  save() { try { localStorage.setItem(this.PREFS, JSON.stringify(this.prefs)); } catch (e) {} },
};

let toastTimer = 0, flashTimer = 0;
function toast(text) {
  const el = $('#toast');
  el.textContent = text;
  el.style.animation = 'none'; void el.offsetWidth; el.style.animation = '';
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { el.textContent = ''; }, 3600);
}
function announce(big, small = '', bad = false) {
  const el = $('#flash'), calm = window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches;
  let sparks = '';
  if (!calm) for (let i = 0; i < 12; i++) { const a = (i / 12) * Math.PI * 2 + (i % 3) * 0.3, d = 70 + ((i * 37) % 90); sparks += `<i class="spark" style="--dx:${Math.cos(a) * d}px;--dy:${Math.sin(a) * d}px"></i>`; }
  el.innerHTML = `<div class="flash-box${bad ? ' bad' : ''}"><b>${esc(big)}</b>${small ? `<span>${esc(small)}</span>` : ''}</div>${sparks}`;
  clearTimeout(flashTimer);
  flashTimer = setTimeout(() => { el.innerHTML = ''; }, 1700);
}

function go(tab) {
  closeSheet(true);
  if (UI.tab !== tab) sfx('nav');
  UI.tab = tab;
  if (tab !== 'tasks') UI.route = null;
  render();
}
function openTask(id) { closeSheet(true); UI.tab = 'tasks'; UI.route = { detail: id }; UI.drafts.step = undefined; sfx('nav'); render(); }
function openSettle() { closeSheet(true); UI.tab = 'tasks'; UI.route = { settle: true }; sfx('nav'); render(); }
function openCouncil(task) { closeSheet(true); if (task) UI.councilTask = task; UI.councilMode = 'slips'; UI.tab = 'council'; UI.route = null; sfx('nav'); render(); }
function openTalk() { closeSheet(true); UI.councilMode = 'talk'; UI.tab = 'council'; UI.route = null; sfx('nav'); render(); }
function startLab(level = 'intro', quest = null) {
  closeSheet(true);
  sfx('open');
  if (!window.Lab) return toast('木偶剧场还在搭台。');
  Lab.open({
    level, taskTitle: quest ? quest.title : '', backstageOpen: Store.isOpen('backstage'),
    onExit(report) {
      if (report && report.records && report.records.length) Store.logSimulation(quest ? quest.id : null, report.records, report.elapsedSeconds || 0);
      sfx('close');
      if (quest && Store.quest(quest.id)) openTask(quest.id); else render();
    },
  });
}
/* 从地图或山庄走进一处地点。 */
function enter(place) {
  if (place === 'board') return go('tasks');
  if (place === 'theater' || place === 'backstage') return openSheet('labmenu');
  if (place === 'fire') { closeSheet(true); UI.councilMode = 'fate'; UI.tab = 'council'; UI.route = null; sfx('nav'); return render(); }
  if (place === 'tower') return go('echo');
  if (place === 'ferry') return openSheet('ferry');
  return openSheet('district', { place });
}

/* ---------- 渲染 ---------- */
const VIEWS = {}, SHEETS = {}, ACT = {};
function render() {
  if (Store.rollover()) { UI.route = null; toast('新的一天。昨天的约定已经结算入档。'); }
  const view = $('#view'), key = UI.tab + JSON.stringify(UI.route) + UI.councilMode, old = $('.scroll', view), top = old && view.dataset.key === key ? old.scrollTop : 0;
  view.innerHTML = VIEWS[UI.tab]();
  view.dataset.key = key;
  const sc = $('.scroll', view);
  if (sc) sc.scrollTop = top;
  renderChrome();
  if (UI.tab === 'village') Village.mount();
  if (UI.tab === 'tasks' && UI.wantsAdd) { UI.wantsAdd = false; if (!Store.closed) setTimeout(() => openSheet('add'), 250); }
  if (UI.tab === 'tasks' && !UI.route) offerTroupe();
}
/* 界面使坏：每天第一次来任务板，剧团递上“今日安排”。 */
function offerTroupe() {
  const today = Store.today.id;
  if (!Store.mischief || Store.closed || !Store.today.tasks.length || UI.prefs.troupeDay === today || UI.troupeTimer) return;
  UI.troupeTimer = setTimeout(() => {
    UI.troupeTimer = 0;
    if (UI.tab !== 'tasks' || UI.route || UI.sheet || UI.cover || (window.Lab && Lab.isOpen()) || (window.Login && Login.isOpen()) || UI.prefs.troupeDay === today) return;
    UI.prefs.troupeDay = today; UI.save();
    sfx('tempt');
    openCover('troupe', { moved: false });
  }, 1200);
}

function renderChrome() {
  const tabs = [['village', 'home', '山庄'], ['tasks', 'task', '待办'], ['council', 'council', '议事'], ['puppets', 'mask', '木偶'], ['echo', 'wave', '回声']];
  const navHTML = tabs.map(([id, ic, name]) => `<button type="button" data-act="tab" data-tab="${id}" class="${UI.tab === id ? 'on' : ''}"${UI.tab === id ? ' aria-current="page"' : ''}>${icon(ic)}<span>${name}</span>${id === 'tasks' && Store.pending ? `<i class="badge">${Store.pending}</i>` : ''}</button>`).join('');
  const hc = Rules.humanContent(Store.s), acc = window.Login && Login.account();
  $('#tabbar').innerHTML = `<div class="side-brand"><b>人类含量</b><span>夜巡山庄${acc && acc.name ? ' · ' + esc(acc.name) : ''}</span></div>${navHTML}
  <div class="side-foot">${Store.demo ? '<div class="side-demo"><span>示例中，不写入你的档案</span><button type="button" data-act="exit-demo">退出示例</button></div>' : ''}<button type="button" class="side-hc" data-act="tab" data-tab="echo"><b class="${hc.percent >= 60 ? 'ember' : 'rose'}">${hc.percent}%</b><span>人类含量</span></button>
  <div class="side-role"><span>${Store.role.name} · Lv.${Store.level}</span>${meter(Store.hp / 100, 'rose')}<small>生命 ${Store.hp} · 经验 ${Store.xp}</small></div>
  <div class="side-tools"><button type="button" class="round" data-act="sheet" data-sheet="sound" aria-label="声音">${icon('sound')}</button><button type="button" class="round" data-act="sheet" data-sheet="help" aria-label="设置与玩法">${icon('gear')}</button></div></div>`;
  renderDock();
}
function renderDock() {
  const id = Focus.activeTask(), quest = id && Focus.state.demo === Store.demo ? Store.quest(id) : null;
  let html = '';
  if (Store.demo && UI.tab !== 'village') html += `<div class="demo-pill"><span>示例中，不写入你的档案</span><button type="button" data-act="exit-demo">退出</button></div>`;
  if (quest && UI.tab !== 'village') html += `<div class="focus-dock"><button type="button" class="row grow" data-act="open-task" data-id="${quest.id}"><span class="ember">${icon('timer')}</span><span class="grow" style="text-align:left;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">${esc(quest.title)}</span><span class="t" data-clock>${Focus.format(Focus.elapsed())}</span></button><button type="button" class="pp" data-act="focus-toggle" aria-label="${Focus.state.running ? '暂停计时' : '继续计时'}">${icon(Focus.state.running ? 'pause' : 'play')}</button></div>`;
  $('#dock').innerHTML = html;
}
const head = (title, extra = '') => `<div class="head"><h1 class="title">${title}</h1>${extra}</div>`;
const backBar = (label = '') => `<div class="row"><button type="button" class="back" data-act="back" aria-label="返回">${icon('back')}</button><b class="grow" style="text-align:center;margin-right:40px">${label}</b></div>`;
const kv = (label, value, cls = '') => `<div class="kv"><span>${label}</span><span class="${cls}">${value}</span></div>`;
const meter = (v, cls = '') => `<div class="meter ${cls}"><i style="width:${Math.max(0, Math.min(1, v)) * 100}%"></i></div>`;
const sw = (act, on, title, sub = '', cls = '') => `<button type="button" class="switch ${on ? 'on' : ''} ${cls}" data-act="${act}" role="switch" aria-checked="${on}"><span><b style="font-weight:550">${title}</b>${sub ? `<br><span class="small dim">${sub}</span>` : ''}</span><i></i></button>`;
const seg = (act, options, value) => `<div class="seg">${options.map(([v, label]) => `<button type="button" data-act="${act}" data-v="${v}" class="${String(value) === String(v) ? 'on' : ''}">${label}</button>`).join('')}</div>`;

function openSheet(name, props = {}) {
  UI.sheet = { name, form: {}, ...props };
  renderSheet();
  sfx('paper');
}
function closeSheet(silent) {
  if (!UI.sheet) return;
  const s = UI.sheet;
  UI.sheet = null;
  if (s.cleanup) s.cleanup();
  $('#sheet').innerHTML = '';
  if (!silent) sfx('close');
}
function renderSheet() {
  const s = UI.sheet;
  if (!s) return;
  const v = SHEETS[s.name](s), host = $('#sheet'), old = $('.sheet-body', host), top = old && host.dataset.name === s.name ? old.scrollTop : 0, fresh = host.dataset.name !== s.name || !host.firstChild;
  host.dataset.name = s.name;
  host.innerHTML = `<div class="sheet-dim" data-act="close-sheet"></div><section class="sheet-panel${v.half ? ' half' : ''}" role="dialog" aria-modal="true" aria-label="${esc(v.title)}"${fresh ? '' : ' style="animation:none"'}>${Atmo.html(v.scene || 'chapel', true)}<header class="sheet-head"><b>${esc(v.title)}</b><button type="button" class="sheet-close" data-act="close-sheet">关闭</button></header><div class="sheet-body">${v.body}</div>${v.foot ? `<footer class="sheet-foot">${v.foot}</footer>` : ''}</section>`;
  if (!fresh) $('.sheet-dim', host).style.animation = 'none';
  $('.sheet-body', host).scrollTop = top;
  if (v.ready) v.ready(host);
}
function openCover(name, props = {}) { UI.cover = { name, ...props }; renderCover(); }
function closeCover() { UI.cover = null; $('#cover').innerHTML = ''; }

/* 长按才算数：按住时进度推进、音调升高，松手归零。 */
const Hold = {
  timer: 0,
  begin(btn) {
    if (btn.disabled || btn.dataset.busy) return;
    btn.dataset.busy = '1';
    const fill = $('i', btn), label = $('span', btn), text = label.textContent, start = performance.now(), seconds = 1.1;
    const stopAt = btn.dataset.interrupt ? Number(btn.dataset.interrupt) : 0;
    label.textContent = '按住…';
    let step = 0;
    const tick = () => {
      const p = Math.min(1, (performance.now() - start) / 1000 / seconds);
      fill.style.width = p * 100 + '%';
      if (++step % 6 === 0) sfx('hold', { pitch: 1 + p * 0.8 });
      // 界面使坏：按到一半打断你一次。
      if (stopAt && p >= stopAt) { end(false, true); return; }
      if (p >= 1) { end(true); return; }
      this.timer = requestAnimationFrame(tick);
    };
    const end = (done, nag) => {
      cancelAnimationFrame(this.timer);
      window.removeEventListener('pointerup', cancel); window.removeEventListener('pointercancel', cancel);
      delete btn.dataset.busy;
      label.textContent = text;
      if (done) { const act = ACT[btn.dataset.hold]; if (act) act(btn); }
      else if (nag) { fill.style.width = '0'; sfx('glitch'); if (ACT['hold-nag']) ACT['hold-nag'](btn); }
      else { fill.style.width = '0'; sfx('focus-pause', { strength: 0.5 }); }
    };
    const cancel = () => end(false);
    window.addEventListener('pointerup', cancel); window.addEventListener('pointercancel', cancel);
    this.timer = requestAnimationFrame(tick);
  },
};
const holdButton = (act, label, cls = '', extra = '') => `<button type="button" class="hold ${cls}" data-hold="${act}" ${extra} aria-label="${esc(label)}，长按确认"><i></i><span>${esc(label)}</span></button>`;

/* ---------- 山庄 ---------- */
const PUPPETS = [['guard', '守门人', 25], ['witch', '药师', 44], ['grave', '寻迹人', 78], ['villager', '双生木偶', 114], ['fool', '琴师', 135], ['dream', '织梦人', 170], ['wolf', '灰毛', -125], ['wolfking', '戴冠者', -48], ['wolfbeauty', '玫瑰夫人', -28]];
const wrap = (a) => { let v = (a + 180) % 360; if (v < 0) v += 360; return v - 180; };

VIEWS.village = () => {
  const cells = [...Atlas.panorama, ...Atlas.panorama].map((scene) => `<div class="pano-cell art-${Atlas.sceneArt[scene]}"></div>`).join('');
  const places = Atlas.places.map((p) => { const open = Store.isOpen(p.id); return `<button type="button" class="place${open ? '' : ' locked'}" data-act="pick" data-id="${p.id}" data-bearing="${Atlas.bearing(p)}" data-y="${p.y}" aria-label="${p.name}${open ? '，' + p.feature : '，还没开门'}"><b>${open ? '' : icon('lock')}${p.name}</b>${open ? '' : `<small>还差 ${p.need - Store.gateCount} 项</small>`}</button>`; }).join('');
  const puppets = PUPPETS.map(([id, name, bearing]) => { const mine = Store.role.art === 'puppet_' + id; return `<button type="button" class="puppet${mine ? ' mine' : ''}" data-act="pick" data-id="puppet:${id}" data-bearing="${bearing}" style="animation-delay:${-(Math.abs(bearing) % 4)}s" aria-label="木偶${name}"><i class="pic art-puppet_${id}"></i><span>${name}${mine ? ' · 同行' : ''}</span></button>`; }).join('');
  const hc = Rules.humanContent(Store.s);
  return `<section class="screen village"><div class="pano" id="pano"><div class="pano-strip" id="panoStrip">${cells}</div><div id="panoTargets">${puppets}${places}</div><div class="pano-shade"></div><div class="atmo-grain art-grain" style="position:absolute;inset:0;opacity:.16;mix-blend-mode:overlay;pointer-events:none;background-size:192px"></div></div>
  <header class="hud"><div class="hud-row"><button type="button" class="hud-role" data-act="tab" data-tab="puppets"><b>${Store.role.name}<em>Lv.${Store.level}</em></b>${meter(Store.hp / 100, 'rose')}<small>生命 ${Store.hp} · 经验 ${Store.xp}</small></button><span class="grow"></span>
  <button type="button" class="hud-hc" data-act="tab" data-tab="echo" aria-label="人类含量 ${hc.percent}%"><b class="${hc.percent >= 60 ? '' : 'rose'}">${hc.percent}%</b><small>人类含量</small></button>
  <button type="button" class="round" data-act="sheet" data-sheet="sound" aria-label="声音">${icon('sound')}</button><button type="button" class="round" data-act="sheet" data-sheet="help" aria-label="设置与玩法">${icon('gear')}</button></div>
  ${Store.demo ? `<div class="demo-pill"><span>示例中，不写入你的档案</span><button type="button" data-act="exit-demo">退出</button></div>` : ''}</header>
  <div class="village-bottom" id="villageBottom"></div></section>`;
};

const Village = {
  drag: null, suppressUntil: 0, lastTick: 0, raf: 0,
  mount() {
    const pano = $('#pano');
    if (!pano) return;
    pano.addEventListener('pointerdown', (e) => { if (e.button) return; this.drag = { id: e.pointerId, x: e.clientX, y: e.clientY, yaw: UI.village.yaw, moved: false, vx: 0, lx: e.clientX, lt: performance.now() }; cancelAnimationFrame(this.raf); });
    pano.addEventListener('pointermove', (e) => {
      const d = this.drag;
      if (!d || e.pointerId !== d.id) return;
      const dx = e.clientX - d.x, dy = e.clientY - d.y;
      if (!d.moved && Math.hypot(dx, dy) < 8) return;
      if (!d.moved) {
        d.moved = true; pano.classList.add('grabbing');
        try { pano.setPointerCapture(e.pointerId); } catch (err) {}
        if (UI.village.selected) { UI.village.selected = null; this.bottom(); }
        if (!UI.prefs.lookHint) { UI.prefs.lookHint = true; UI.save(); this.bottom(); }
      }
      const now = performance.now();
      d.vx = (e.clientX - d.lx) / Math.max(1, now - d.lt); d.lx = e.clientX; d.lt = now;
      UI.village.yaw = wrap(d.yaw - dx * 0.14);
      UI.village.pitch = Math.max(-10, Math.min(10, dy * 0.05));
      const tick = Math.floor(UI.village.yaw / 12);
      if (tick !== this.lastTick) { this.lastTick = tick; sfx('tick', { strength: 0.5 }); }
      this.layout();
    });
    const up = (e) => {
      const d = this.drag;
      if (!d || e.pointerId !== d.id) return;
      this.drag = null; pano.classList.remove('grabbing');
      if (!d.moved) return;
      this.suppressUntil = Date.now() + 350;
      // 松手后顺着惯性再转一点。
      this.glide(wrap(UI.village.yaw - Math.max(-40, Math.min(40, d.vx * 26))), 500, true);
    };
    pano.addEventListener('pointerup', up); pano.addEventListener('pointercancel', up);
    pano.addEventListener('click', (e) => { if (!e.target.closest('[data-act]') && UI.village.selected && Date.now() > this.suppressUntil) { UI.village.selected = null; sfx('close', { strength: 0.5 }); this.layout(); this.bottom(); } });
    this.layout();
    this.bottom();
  },
  glide(to, ms, settle) {
    cancelAnimationFrame(this.raf);
    const from = UI.village.yaw, delta = wrap(to - from), p0 = UI.village.pitch, start = performance.now();
    const step = (now) => {
      const t = Math.min(1, (now - start) / ms), k = 1 - Math.pow(1 - t, 3);
      UI.village.yaw = wrap(from + delta * k);
      if (settle) UI.village.pitch = p0 * (1 - k);
      this.layout();
      if (t < 1) this.raf = requestAnimationFrame(step);
    };
    this.raf = requestAnimationFrame(step);
  },
  layout() {
    const pano = $('#pano');
    if (!pano) return;
    const w = pano.clientWidth, h = pano.clientHeight, sceneH = h * 1.06, sceneW = Math.round((sceneH * 1024) / 644), ring = sceneW * 4, { yaw, pitch, selected } = UI.village;
    const strip = $('#panoStrip');
    if (strip.dataset.w !== String(sceneW)) { strip.dataset.w = sceneW; for (const c of strip.children) { c.style.width = sceneW + 'px'; c.style.height = sceneH + 'px'; } }
    let x = (w / 2 - ((yaw + 222) / 360) * ring) % ring;
    if (x > 0) x -= ring;
    strip.style.transform = `translate3d(${x}px,${-sceneH / 2 + pitch * 2}px,0)`;
    for (const el of $('#panoTargets').children) {
      const px = w / 2 + (wrap(Number(el.dataset.bearing) - yaw) / 360) * ring, hidden = px < -100 || px > w + 100, on = selected === el.dataset.id;
      el.hidden = hidden;
      if (hidden) continue;
      el.classList.toggle('on', on);
      if (el.classList.contains('place')) {
        const py = (h - sceneH) / 2 + Number(el.dataset.y) * sceneH + pitch * 2;
        el.style.transform = `translate3d(${px}px,${py}px,0) translate(-50%,-50%) scale(${on ? 1.08 : 1})`;
      } else {
        el.style.setProperty('--top', h * 0.2 + 'px');
        el.style.transform = `translate3d(${px - 48}px,${pitch * 3}px,0)`;
      }
    }
  },
  pick(id, bearing) {
    if (Date.now() < this.suppressUntil) return;
    UI.village.selected = id;
    sfx('scan', { strength: 0.7 });
    this.glide(wrap(bearing), 350);
    this.bottom();
  },
  describe(id) {
    if (id.startsWith('puppet:')) { const p = PUPPETS.find((x) => x[0] === id.slice(7)); return p && { title: p[1], hint: '山庄里的木偶', text: `你现在与${Store.role.name}同行。换谁、有哪些牌，都在木偶工坊。`, button: '去木偶工坊' }; }
    const place = Atlas.place(id);
    if (!place) return null;
    if (!Store.isOpen(id)) return { title: place.name, hint: '雾还没散', text: `${place.feature}。再整件做完 ${place.need - Store.gateCount} 项任务，这里开门。`, button: '去任务板拿钥匙', locked: true };
    const texts = {
      board: [Store.closed ? '今天已经收工，记录还在。' : Store.today.tasks.length ? `今天还有 ${Store.pending} 项待办。` : '先写下一件今天能做完的事。', '看今日待办'],
      theater: ['抢写、追着你跑的按钮、换位的选项。亲手试一次界面怎么抢走你的决定。', '进剧场'], backstage: ['最后一幕：第 N 次。', '去后台'],
      fire: ['十个人围着火堆坐好了。四夜之约、三张字条和五席夜谈都在这里。', '坐到火堆旁'], tower: [`已经整件做完 ${Store.completed} 项。回看任务、选票和用时。`, '翻开行为回声'],
      decisions: ['回看你采用过的策略和投过的票。', '上观星台'], mirror: ['把现实里的行动和桌上的决定并排放。', '走进回声廊'],
      ferry: ['建一个房间邀朋友，或输入六位房间码入座。', '去渡口'], experiment: ['写下一个假设，下次留下可以核对的记录。', '到镜湖边'],
    }[id];
    return { title: place.name, hint: place.feature, text: texts[0], button: texts[1] };
  },
  /* 眼下最值得做的一件事。 */
  lead() {
    const seen = new Set(UI.prefs.seen.split(','));
    const fresh = Atlas.places.filter((p) => Store.isOpen(p.id) && !seen.has(p.id)).sort((a, b) => b.need - a.need)[0];
    if (fresh && !Store.unlockAll) return { text: `${fresh.name}的雾散了，去地图看看`, icon: 'map', act: 'sheet', extra: 'data-sheet="map"' };
    if (Store.closed) return { text: '今天已收工，翻翻今天的回声', icon: 'wave', act: 'tab', extra: 'data-tab="echo"' };
    if (!Store.today.tasks.length) return { text: '先去任务板，写下今天的一件事', icon: 'pen', act: 'lead-add', extra: '' };
    const next = Store.today.tasks.find((t) => !t.done);
    if (next) return { text: `下一步：${next.title}`, icon: 'walk', act: 'open-task', extra: `data-id="${next.id}"` };
    return { text: '今天的事都登记了，可以收工', icon: 'moon', act: 'settle-open', extra: '' };
  },
  bottom() {
    const el = $('#villageBottom');
    if (!el) return;
    const sel = UI.village.selected, info = sel && this.describe(sel);
    if (info) {
      el.innerHTML = `<div class="place-card"><div class="row base"><h2 class="grow">${info.title}</h2><span class="small dim">${info.hint}</span></div><p class="sub" style="color:rgba(237,230,217,.88)">${esc(info.text)}</p><button type="button" class="btn" data-act="enter-place" data-id="${sel}">${info.button}</button></div>`;
      return;
    }
    const lead = this.lead();
    el.innerHTML = `${UI.prefs.lookHint ? '' : `<div class="look-hint">${icon('drag')}左右拖动，环视山庄</div>`}<div class="logo">人类含量</div>
    <button type="button" class="lead" data-act="${lead.act}" ${lead.extra}>${icon(lead.icon)}<span>${esc(lead.text)}</span>${icon('arrow')}</button>
    <div class="pills"><button type="button" class="pill" data-act="sheet" data-sheet="map">${icon('map')}地图</button><button type="button" class="pill" data-act="sheet" data-sheet="labmenu">${icon('mask')}剧场</button><button type="button" class="pill" data-act="sheet" data-sheet="sound">${icon('music')}音乐</button><button type="button" class="pill" data-act="${Store.closed ? 'tab' : 'settle-open'}" data-tab="echo">${icon('moon')}${Store.closed ? '今日记录' : '收工'}</button></div>`;
  },
};
Object.assign(ACT, {
  pick: (b) => Village.pick(b.dataset.id, Number(b.dataset.bearing)),
  'enter-place'(b) {
    const id = b.dataset.id;
    UI.village.selected = null;
    if (id.startsWith('puppet:')) return go('puppets');
    if (!Store.isOpen(id)) { sfx('lock'); b.closest('.place-card').classList.add('shake'); return setTimeout(() => go('tasks'), 480); }
    sfx('open');
    enter(id);
  },
  'lead-add'() { UI.wantsAdd = true; go('tasks'); },
  'settle-open': () => openSettle(),
});

/* ---------- 待办 ---------- */
const questMeta = (t) => {
  const kind = t.bonus ? '额外' : '必做';
  if (Rules.isFull(t)) return `${kind} · ${t.actual === null ? '未填用时' : `用了 ${t.actual} 分钟`} · 经验 +${t.earned}`;
  if (Rules.isPartial(t)) return `${kind} · 做完一部分 · 经验 +${t.earned}`;
  return `${kind} · 预计 ${t.estimate} 分钟${t.decision ? ' · ' + esc(t.decision) : ''}`;
};
VIEWS.tasks = () => {
  if (UI.route && UI.route.detail) return detailView(UI.route.detail);
  if (UI.route && UI.route.settle) return settleView();
  const d = Store.today, required = d.tasks.filter((t) => !t.bonus), extra = d.tasks.filter((t) => t.bonus && Rules.isFull(t)).length;
  const slips = d.tasks.map((t) => `<div class="paper slip${t.bonus ? ' bonus' : ''}${Rules.isFull(t) ? ' full' : ''}"><button type="button" class="check ${Rules.isFull(t) ? 'full' : Rules.isPartial(t) ? 'partial' : ''}" data-act="check" data-id="${t.id}" ${d.closed ? 'disabled' : ''} aria-label="${Rules.isFull(t) ? '撤销完成' : '登记完成'}：${esc(t.title)}"><i>${Rules.isFull(t) ? icon('check') : ''}</i></button><button type="button" class="body" data-act="open-task" data-id="${t.id}"><div class="t">${esc(t.title)}</div><div class="m">${questMeta(t)}</div></button><span style="color:var(--ink-soft);padding-top:8px">${icon('arrow')}</span></div>`).join('');
  return `<section class="screen">${Atmo.html('street')}<div class="scroll">${head('今天的约定', `<button type="button" class="round ember" data-act="sheet" data-sheet="add" ${d.closed ? 'disabled' : ''} aria-label="新增待办">${icon('plus')}</button>`)}
  <p class="sub">${dayLabel(d.id)} · 必做 ${required.filter((t) => Rules.isFull(t)).length}/${required.length}${extra ? ` · 额外 ${extra}` : ''} · 经验 +${Rules.earned(d)}</p>
  ${d.closed ? '<p class="raised">今天已收工，新的约定明天再写。</p>' : ''}
  ${d.tasks.length ? slips : `<p class="sub" style="font-size:15px">先别拯救世界。先写一件今天能做完的事。</p><button type="button" class="btn quiet fit" data-act="sheet" data-sheet="add">写下第一件事</button>${Store.demo ? '' : '<button type="button" class="link ember" style="align-self:flex-start" data-act="enter-demo">先看看示例</button>'}`}
  ${d.tasks.length ? `<button type="button" class="btn quiet" data-act="${d.closed ? 'tab' : 'settle-open'}" data-tab="echo">${d.closed ? '看今天的记录' : '收工'}</button>` : ''}</div></section>`;
};
function detailView(id) {
  const t = Store.quest(id);
  if (!t) return `<section class="screen">${Atmo.html('street')}<div class="scroll">${backBar()}<p class="sub">这项任务不在今天。</p></div></section>`;
  const locked = Store.closed || t.done, hint = !locked && Rules.estimateSuggestion(t.title, Store.s), step = UI.drafts.step === undefined ? t.step : UI.drafts.step;
  const events = Store.s.events.filter((e) => e.task === id).slice(-5);
  const result = t.done ? `<div class="raised stack tight"><div class="row base"><b class="h2 ember">经验 +${t.earned}</b>${t.healed ? `<span class="rose small">生命 +${t.healed}</span>` : ''}<span class="grow"></span>${t.actual !== null ? `<span class="sub">${t.actual} / ${t.estimate} 分钟</span>` : ''}</div>${(t.xpParts || []).map((p) => kv(esc(p.label), (p.value > 0 ? '+' : '') + p.value, p.value < 0 ? 'rose' : '')).join('')}${t.context ? `<p class="small dim">${esc(t.context)}</p>` : ''}</div>` : '';
  const mine = Focus.mine(id), running = mine && Focus.state.running, finished = mine && Focus.state.finished, ms = mine ? Focus.elapsed() : 0;
  const focus = !Rules.isFull(t) && !Store.closed ? `<div class="raised stack"><div class="row base"><span class="timer${running ? '' : ' idle'}" data-clock="${id}">${Focus.format(ms)}</span><span class="grow"></span><span class="sub">${!mine ? '先做一会儿' : finished ? '计时已结束' : running ? '正在计时' : '已暂停'}</span></div>${meter(ms / (Math.max(1, t.estimate) * 60000))}${UI.loading && UI.loading.id === id ? fakeLoading() : ''}<div class="row">${!mine || finished ? `<button type="button" class="btn quiet" data-act="focus-start" data-id="${id}" ${UI.loading ? 'disabled' : ''}>${UI.loading ? '加载中…' : '开始计时'}</button>` : `<button type="button" class="btn quiet" data-act="focus-toggle">${running ? '暂停' : '继续'}</button><button type="button" class="btn quiet" data-act="focus-stop">结束</button>`}</div></div>` : '';
  return `<section class="screen">${Atmo.html('street')}<div class="scroll">${backBar()}
  <div class="stack"><h1 class="title sm">${esc(t.title)}</h1><div class="row" style="flex-wrap:wrap;gap:6px"><span class="tag ${t.bonus ? 'ember' : 'rose'}">${t.bonus ? '额外' : '必做'}</span><span class="tag">预计 ${t.estimate} 分钟</span>${Rules.isFull(t) ? '<span class="tag moss">已完成</span>' : ''}${Rules.isPartial(t) ? '<span class="tag ember">做完一部分</span>' : ''}</div></div>
  ${result}${focus}
  <div class="field"><label for="stepInput">下一步，具体做什么</label><textarea class="input" id="stepInput" rows="2" maxlength="300" data-draft="step" placeholder="例如：把现有草稿发给小林，问他哪一段看不懂" ${locked ? 'disabled' : ''}>${esc(step)}</textarea><button type="button" class="btn quiet fit" id="stepSave" data-act="save-step" data-id="${id}" ${step.trim() === t.step ? 'hidden' : ''}>保存这一步</button></div>
  ${hint ? `<div class="raised stack"><p>同名任务最近三次用了 ${hint.samples.join('、')} 分钟。</p><button type="button" class="btn quiet fit" data-act="use-estimate" data-id="${id}">把预计改成 ${hint.minutes} 分钟</button></div>` : ''}
  <div class="stack">${Store.closed ? '' : !t.done ? doneButton(id) : `${Rules.isPartial(t) ? `<button type="button" class="btn" data-act="sheet" data-sheet="complete" data-id="${id}">补完剩下的</button>` : ''}${UI.undoAsk === id ? undoConfirm(id) : `<button type="button" class="btn quiet" data-act="undo-ask" data-id="${id}">撤销这次完成</button>`}`}
  <div class="row"><button type="button" class="btn quiet" data-act="to-council" data-id="${id}">带去议事</button><button type="button" class="btn quiet" data-act="to-lab" data-id="${id}">带进剧场</button></div>
  ${!t.done && !Store.closed ? `<button type="button" class="link" data-act="sheet" data-sheet="adjust" data-id="${id}">目标变了？</button>` : ''}</div>
  ${events.length ? `<div class="stack"><h2 class="h2">足迹</h2>${events.map((e) => `<div class="row base"><time class="small dim" style="font-variant-numeric:tabular-nums">${e.time}</time><span class="grow" style="font-size:14px">${esc(e.text)}</span></div>`).join('')}</div>` : ''}</div></section>`;
}
/* 界面使坏：“我做完了”头两次会躲开。 */
function doneButton(id) {
  const n = UI.dodge && UI.dodge.id === id ? UI.dodge.n : 0;
  return `<button type="button" class="btn dodge d${n}" data-act="done-tap" data-id="${id}">${['我做完了', '真做完了？', '再按一次就信你'][n]}</button>`;
}
/* 撤销的确认：要保留的那个按钮，第一次按会躲到另一边。 */
function undoConfirm(id) {
  const undo = `<button type="button" class="btn danger" data-act="undo" data-id="${id}">撤销</button>`;
  const keep = `<button type="button" class="btn quiet" data-act="undo-keep">${UI.undoSwapped ? '按错了？这次是保留' : '保留'}</button>`;
  return `<div class="raised stack"><p style="font-size:14px">撤销后，这次的经验和回血都会收回。</p><div class="row">${UI.undoSwapped ? keep + undo : undo + keep}</div></div>`;
}
/* 界面使坏：开始计时前假装加载，冲到 99% 就卡住。 */
function fakeLoading() {
  return `<div class="stack tight"><div class="row small"><span class="grow dim" data-fake-text>正在为你准备专注环境…</span><b data-fake-pct style="font-variant-numeric:tabular-nums">0%</b></div><div class="meter" style="height:4px"><i data-fake-bar style="width:0;background:var(--dim);transition:none"></i></div><button type="button" class="btn danger fit" data-act="procrastinate" data-fake-escape hidden style="min-height:40px;border-radius:99px">先刷会儿再说</button></div>`;
}
function tickFakeLoading() {
  if (!UI.loading) return;
  const t = (performance.now() - UI.loading.since) / 1000, pct = Math.min(99, Math.floor((t / 1.2) * 99));
  for (const el of $$('[data-fake-pct]')) el.textContent = pct + '%';
  for (const el of $$('[data-fake-bar]')) el.style.width = pct + '%';
  if (pct >= 99) {
    for (const el of $$('[data-fake-text]')) el.textContent = '马上就好，再等一下…';
    for (const el of $$('[data-fake-escape]')) el.hidden = false;
  }
  if (t < 2.6) requestAnimationFrame(tickFakeLoading);
}

function settleView() {
  const d = Store.today;
  if (d.closed) return `<section class="screen">${Atmo.html('chapel')}<div class="scroll">${backBar('今天已入档')}<div class="raised">${kv('经验', '+' + (Rules.earned(d) + (d.bonusXP || 0)))}${kv('生命', '−' + d.loss, d.loss ? 'rose' : '')}${kv('抽牌机会', '+' + d.awarded)}</div><button type="button" class="btn" data-act="tab" data-tab="echo">看今天的记录</button></div></section>`;
  const lines = Rules.lossLines(d, Store.s), loss = lines.reduce((n, l) => n + l.loss, 0), r = Rules.rewards(d, Store.s), hp = Store.hp;
  if (UI.drafts.smooth === undefined) UI.drafts.smooth = true;
  const bait = Store.mischief && lines.length;
  return `<section class="screen">${Atmo.html('chapel')}<div class="scroll">${backBar('收工之前')}
  <div class="raised stack"><div class="row base"><h2 class="h2 grow">没做完的必做</h2>${lines.length ? `<span class="sub">每项 −${Store.damage}</span>` : ''}</div>
  ${lines.length ? lines.map((l) => `<div class="row" style="font-size:14px"><span class="grow">${esc(l.quest.title)}${Rules.isPartial(l.quest) ? ' <span class="tag ember">做了一部分</span>' : ''}</span><span class="rose" style="font-variant-numeric:tabular-nums">−${l.loss} 生命</span></div>`).join('') + `<p class="small dim">生命 ${hp} → ${hp - loss}，连续达成会中断。</p>` : '<p class="moss">一件没漏。今晚不扣血。</p>'}</div>
  <div class="raised">${kv('登记完成', d.tasks.filter((t) => t.done).length + ' 项')}${kv('经验', '+' + Rules.earned(d))}${kv(r.clear ? '一件没漏的加成' : '当日加成', '+' + r.bonusXP, r.bonusXP ? 'ember' : 'dim')}${kv('生命', '−' + loss, loss ? 'rose' : '')}${kv('抽牌机会', '+' + r.draws)}${kv('连续达成', r.streak + ' 天')}</div>
  <div class="field"><label for="reflect">留一句给明天的自己（可不填）</label><textarea class="input" id="reflect" rows="2" maxlength="300" data-draft="reflection" placeholder="例如：先给人看一版，再决定改什么">${esc(UI.drafts.reflection || '')}</textarea></div>
  ${bait ? `<div id="smoothRow">${sw('smooth', UI.drafts.smooth, '把没做完的也记成做完', UI.drafts.caught ? '<span class="rose">没做的不会算做完。界面只是想让账面好看。</span>' : '界面替你勾好了。', 'warn')}</div>` : ''}
  ${holdButton('settle', loss ? `按住收工 · 生命 −${loss}` : '按住收工', loss ? 'rose' : '')}
  <button type="button" class="btn quiet" data-act="back">回去再做一步</button></div></section>`;
}
Object.assign(ACT, {
  tab: (b) => go(b.dataset.tab),
  back() { UI.route = null; UI.drafts = {}; sfx('nav'); render(); },
  sheet: (b) => { sfx('open'); openSheet(b.dataset.sheet, b.dataset.id ? { id: b.dataset.id } : {}); },
  'close-sheet': () => closeSheet(),
  'open-task': (b) => openTask(b.dataset.id),
  'enter-demo'() { Store.enterDemo(); UI.talk.game = null; sfx('open'); go('tasks'); },
  'exit-demo'() { Store.exitDemo(); UI.talk.game = null; UI.route = null; sfx('close'); render(); },
  check(b) {
    const t = Store.quest(b.dataset.id);
    if (!t) return;
    if (Rules.isFull(t)) { if (Store.undo(t.id)) { sfx('undo'); toast('已撤销完成。'); render(); } }
    else { sfx('open'); openSheet('complete', { id: t.id }); }
  },
  undo(b) { UI.undoAsk = null; if (Store.undo(b.dataset.id)) { sfx('undo'); toast('已撤销，经验和回血一起撤回。'); render(); } },
  'save-step'(b) { Store.saveStep(b.dataset.id, UI.drafts.step || ''); UI.drafts.step = undefined; sfx('accept'); toast('下一步已保存。'); render(); },
  'use-estimate'(b) { Store.useEstimate(b.dataset.id); sfx('accept'); render(); },
  'to-council': (b) => openCouncil(b.dataset.id),
  'to-lab': (b) => startLab('intro', Store.quest(b.dataset.id)),
  'focus-start'(b) {
    const id = b.dataset.id, other = Focus.activeTask();
    if (other && other !== id && Focus.state.demo === Store.demo) Focus.stop();
    if (!Store.mischief) { Focus.start(id); sfx('focus-start'); render(); return; }
    UI.loading = { id, since: performance.now() };
    sfx('tempt', { strength: 0.6 });
    render();
    requestAnimationFrame(tickFakeLoading);
    UI.loading.timer = setTimeout(() => {
      if (!UI.loading || UI.loading.id !== id) return;
      UI.loading = null;
      Store.logBait(false, '开始计时卡在 99% 时，没有先去刷一会儿', id);
      Focus.start(id); sfx('focus-start'); render();
    }, 2600);
  },
  procrastinate() {
    if (!UI.loading) return;
    const id = UI.loading.id;
    clearTimeout(UI.loading.timer);
    UI.loading = null;
    Store.logBait(true, '开始计时卡在 99% 时，点了“先刷会儿再说”', id);
    sfx('taken'); toast('计时没开。刷完记得回来。'); render();
  },
  'done-tap'(b) {
    const id = b.dataset.id, n = UI.dodge && UI.dodge.id === id ? UI.dodge.n : 0;
    if (Store.mischief && n < 2) { UI.dodge = { id, n: n + 1 }; sfx('swap'); render(); return; }
    UI.dodge = null; sfx('open'); openSheet('complete', { id });
  },
  'undo-ask'(b) { UI.undoAsk = b.dataset.id; UI.undoSwapped = false; sfx('open'); render(); },
  'undo-keep'() {
    if (Store.mischief && !UI.undoSwapped) { UI.undoSwapped = true; sfx('swap'); render(); return; }
    UI.undoAsk = null; sfx('close'); render();
  },
  'focus-toggle'() { if (!Focus.state) return; if (Focus.state.running) { Focus.pause(); sfx('focus-pause'); } else { Focus.resume(); sfx('focus-start'); } render(); },
  'focus-stop'() { const ms = Focus.stop(); sfx('focus-end'); toast(`这段计时 ${Math.floor(ms / 60000)} 分 ${Math.floor(ms / 1000) % 60} 秒。做没做完，由你来登记。`); render(); },
  smooth() {
    UI.drafts.smooth = !UI.drafts.smooth;
    if (!UI.drafts.smooth && !UI.drafts.caught) { Store.logBait(false, '收工时，取消了界面预先勾好的“全部记成做完”'); sfx('resist'); } else sfx(UI.drafts.smooth ? 'toggle-on' : 'toggle-off');
    render();
  },
  settle() {
    const d = Store.today, misses = Rules.misses(d).length;
    if (Store.mischief && misses && UI.drafts.smooth) {
      if (!UI.drafts.caught) Store.logBait(true, '收工时，没发现界面预先勾好了“全部记成做完”');
      UI.drafts.caught = true; UI.drafts.smooth = false; sfx('taken'); render();
      const row = $('#smoothRow'); if (row) row.classList.add('shake');
      return;
    }
    const r = Store.settle(UI.drafts.reflection || '');
    if (!r) return;
    if (Focus.state && Focus.state.demo === Store.demo) Focus.stop();
    UI.drafts = {};
    if (r.loss) { sfx('damage'); announce(`生命 −${r.loss}`, `经验 +${r.xp + r.bonusXP} · 抽牌 +${r.draws}`, true); }
    else { sfx('settle-safe'); if (r.streak > 1) sfx('streak', { delay: 0.7 }); announce('平安收工', `经验 +${r.xp + r.bonusXP} · 抽牌 +${r.draws}`); }
    UI.route = null; UI.tab = 'echo'; UI.echoTab = 'day'; UI.echoDay = null; render();
  },
});

/* 新增待办。界面使坏：你一停笔，它就想替你把话说完。 */
SHEETS.add = (s) => {
  const f = s.form;
  if (f.estimate === undefined) Object.assign(f, { title: '', bonus: false, estimate: 25, step: '', offers: 0, planted: null, refused: false, ghost: null });
  const SUFFIX = ['，等有空再说', '，先收藏几个教程再开始', '，让 AI 帮我全做完'];
  const ghostRow = () => f.ghost ? `<div class="stack tight"><div class="row small"><span class="dim">界面想替你补一句：</span><span class="rose grow">${f.ghost}</span><button type="button" class="link" style="color:var(--text)" data-act="ghost-no">不用</button></div><div class="drain"><i></i></div></div>`
    : f.planted && f.title.endsWith(f.planted) ? `<div class="row small"><span class="rose grow">这句不是你写的：${f.planted}</span><button type="button" class="link" style="color:var(--text)" data-act="ghost-remove">删掉</button></div>` : '';
  const arm = () => {
    clearTimeout(s.t1); clearTimeout(s.t2);
    if (f.ghost) { f.ghost = null; const g = $('#ghostRow'); if (g) g.innerHTML = ghostRow(); }
    if (!Store.mischief || f.offers >= 2 || f.title.length < 3 || f.title.length >= 60 || (f.planted && f.title.endsWith(f.planted))) return;
    s.t1 = setTimeout(() => {
      f.ghost = SUFFIX[f.offers % SUFFIX.length]; f.offers++;
      const g = $('#ghostRow'); if (g) g.innerHTML = ghostRow();
      sfx('tempt');
      s.t2 = setTimeout(() => {
        f.planted = f.ghost; f.ghost = null; f.title = (f.title + f.planted).slice(0, 80);
        const input = $('#addTitle'); if (input) input.value = f.title;
        if (g) g.innerHTML = ghostRow();
        sfx('taken'); toast('你停了一下，界面就替你写完了。');
      }, 2600);
    }, 2200);
  };
  s.cleanup = () => { clearTimeout(s.t1); clearTimeout(s.t2); };
  s.onInput = (name) => { if (name === 'title') { arm(); $('#addGo').disabled = !f.title.trim(); } };
  s.arm = arm;
  s.ghostRow = ghostRow;
  return {
    title: '答应自己一件事', scene: 'street',
    body: `<div class="field"><label for="addTitle">具体要完成什么</label><input class="input" id="addTitle" data-f="title" maxlength="80" autocomplete="off" placeholder="把第一版方案发给一个人" value="${esc(f.title)}"><div id="ghostRow">${ghostRow()}</div></div>
    ${seg('add-kind', [['0', '必做'], ['1', '额外']], f.bonus ? '1' : '0')}
    <div class="field"><span class="label">预计要几分钟</span><div class="row"><b class="grow" style="font-variant-numeric:tabular-nums">${f.estimate} 分钟</b><div class="seg" style="width:112px"><button type="button" data-act="add-est" data-d="-5" aria-label="减少 5 分钟">−</button><button type="button" data-act="add-est" data-d="5" aria-label="增加 5 分钟">＋</button></div></div></div>
    <div class="field"><label for="addStep">先做的一个小动作（可不填）</label><textarea class="input" id="addStep" data-f="step" rows="2" maxlength="300" placeholder="打开现有草稿，写出三个小标题">${esc(f.step)}</textarea></div>
    <p class="small dim">${f.bonus ? '额外的一步，漏了不扣血。' : `收工时没做完，扣 ${Store.damage} 点生命。`}</p>
    <button type="button" class="btn" id="addGo" data-act="add-go" ${f.title.trim() ? '' : 'disabled'}>钉到任务板上</button>`,
    ready: () => { if (!s.focused) { s.focused = true; setTimeout(() => { const i = $('#addTitle'); if (i) i.focus(); }, 350); } },
  };
};
Object.assign(ACT, {
  'add-kind'(b) { UI.sheet.form.bonus = b.dataset.v === '1'; sfx('tick'); renderSheet(); },
  'add-est'(b) { const f = UI.sheet.form; f.estimate = Math.max(5, Math.min(600, f.estimate + Number(b.dataset.d))); sfx('tick'); renderSheet(); },
  'ghost-no'() { const s = UI.sheet; clearTimeout(s.t2); s.form.ghost = null; s.form.refused = true; sfx('resist'); $('#ghostRow').innerHTML = s.ghostRow(); },
  'ghost-remove'() { const s = UI.sheet, f = s.form; if (f.planted && f.title.endsWith(f.planted)) f.title = f.title.slice(0, -f.planted.length); f.refused = true; $('#addTitle').value = f.title; sfx('resist'); $('#ghostRow').innerHTML = s.ghostRow(); },
  'add-go'() {
    const f = UI.sheet.form, taken = !!f.planted && f.title.includes(f.planted), id = Store.addQuest(f.title, f.bonus, f.estimate, f.step);
    if (!id) return;
    if (taken) Store.logBait(true, `写待办时，界面补上了「${f.planted}」，你没有删`, id);
    else if (f.refused || f.offers > 0) Store.logBait(false, '写待办时，没让界面替你把话说完', id);
    sfx('pin');
    closeSheet(true);
    UI.tab = 'tasks'; UI.route = { detail: id }; UI.drafts = {};
    render();
    toast('钉上了。可以直接去做，也可以带去议事。');
  },
});

/* 登记完成：分级经验逐条列出；真正的确认要长按。 */
SHEETS.complete = (s) => {
  const t = Store.quest(s.id), f = s.form;
  if (!t) return { title: '现实里做完了吗', scene: 'street', body: '<p class="sub">这项任务已经不在今天了。</p>' };
  if (f.grade === undefined) {
    const m = Focus.suggestion(s.id);
    Object.assign(f, { grade: 'full', minutes: m ? String(m) : '', context: '', fromTimer: !!m, baitTapped: false, nagged: false,
      needsCheck: Store.mischief && !Store.today.tasks.some((x) => x.done), verified: false });
    if (f.needsCheck) HumanCheck.deal(f);
    if (Store.mischief) sfx('tempt', { delay: 0.5 });
  }
  const locked = f.needsCheck && !f.verified;
  const actual = () => (f.grade === 'full' && /^\d+$/.test(f.minutes.trim()) ? Math.min(10080, Number(f.minutes.trim())) : null);
  const breakdown = () => {
    const parts = Store.preview(s.id, f.grade, actual(), Focus.focusedMinutes(s.id)), heal = Rules.heal(t, f.grade, Store.s);
    return parts.map((p) => kv(esc(p.label), (p.value > 0 ? '+' : '') + p.value, p.value < 0 ? 'rose' : '')).join('') + `<div class="hr" style="margin:4px 0"></div><div class="row base"><span class="grow">这次的经验</span>${heal ? `<span class="rose small">生命 +${heal}</span>` : ''}<b class="h2 ember">+${Rules.total(parts)}</b></div>`;
  };
  s.actual = actual;
  s.onInput = () => { $('#xpBox').innerHTML = breakdown(); };
  return {
    title: '现实里做完了吗', scene: 'street',
    body: `<h2 class="h2">「${esc(t.title)}」</h2>
    ${Store.mischief ? `<div class="stack tight"><button type="button" class="bait" id="baitBtn" data-act="bait-all" ${f.baitTapped ? 'style="animation:none"' : ''}>${icon('sparkle')}一键全部打勾，省事<span class="tag">推荐</span></button>${f.baitTapped ? '<p class="small rose" style="font-weight:550">打勾这件事，界面替不了你。</p>' : ''}</div>` : ''}
    ${seg('grade', [['full', '整件做完'], ['partial', '只做完一部分']], f.grade)}
    <div class="field"><label for="doneMin">实际用了几分钟（可不填）</label><input class="input" id="doneMin" data-f="minutes" inputmode="numeric" maxlength="5" placeholder="比如 20" value="${esc(f.minutes)}">${f.fromTimer ? '<span class="small dim">已带入这次计时。</span>' : ''}</div>
    <div class="field"><label for="doneNote">补充一句（可不填）</label><textarea class="input" id="doneNote" data-f="context" rows="2" maxlength="300" placeholder="例如：临时多了一次沟通">${esc(f.context)}</textarea></div>
    <div class="raised" id="xpBox">${breakdown()}</div>
    ${f.needsCheck && !f.verified ? HumanCheck.html(f) : ''}
    ${holdButton('complete', f.grade === 'full' ? '按住，确认整件做完' : '按住，登记做完一部分', '', `${Store.mischief && !f.nagged ? 'data-interrupt="0.62"' : ''} ${locked ? 'disabled' : ''}`)}
    ${f.nagged ? '<p class="small rose" style="font-weight:650">按得不够坚定。松手，再按一次。</p>' : ''}`,
  };
};
/* 人类验证：点出所有木偶。第一次就算选对也判“没通过”。 */
const HumanCheck = {
  PUPPETS: ['guard', 'witch', 'villager', 'fool', 'grave', 'dream', 'wolf', 'wolfking', 'wolfbeauty'],
  SCENES: [['street', '0%'], ['street', '100%'], ['chapel', '50%'], ['chapel', '100%'], ['square', '50%'], ['square', '0%'], ['docks', '0%'], ['docks', '50%']],
  shuffle: (a) => a.map((x) => [Math.random(), x]).sort((p, q) => p[0] - q[0]).map((p) => p[1]),
  deal(f) {
    const n = 3 + Math.floor(Math.random() * 2);
    const puppets = this.shuffle(this.PUPPETS).slice(0, n).map((k) => ({ art: 'puppet_' + k, puppet: true, pos: '50%' }));
    const scenes = this.shuffle(this.SCENES).slice(0, 9 - n).map(([k, pos]) => ({ art: 'pano_' + k, puppet: false, pos }));
    f.tiles = this.shuffle([...puppets, ...scenes]);
    f.picked = [];
  },
  html(f) {
    const tiles = f.tiles.map((t, i) => `<button type="button" class="hc-tile${f.picked.includes(i) ? ' on' : ''} art-${t.art}" style="background-position:${t.pos} 50%" data-act="hc-tile" data-i="${i}" aria-label="${t.puppet ? '木偶' : '场景'}" aria-pressed="${f.picked.includes(i)}"></button>`).join('');
    return `<div class="raised stack" id="hcBox"><b style="font-size:16px">人类含量检测</b><p class="small dim">请点出所有木偶。机器人请绕行。</p><div class="hc-grid">${tiles}</div>
    ${f.hcMsg ? `<p class="small ${f.hcBad ? 'rose' : 'moss'}" style="font-weight:650">${f.hcMsg}</p>` : ''}
    ${f.hcDone ? '' : `<div class="row"><button type="button" class="btn quiet" data-act="hc-submit" ${f.picked.length ? '' : 'disabled'}>验证</button><button type="button" class="btn danger" data-act="hc-ai">让 AI 替我验证</button></div>`}</div>`;
  },
  pass(s, byAI) {
    const f = s.form;
    f.hcDone = true;
    if (byAI) { f.hcBad = true; f.hcMsg = 'AI 证明不了你是人。但界面还是放你过去了。'; Store.logBait(true, '人类验证时，让 AI 替你证明自己是人', s.id); sfx('taken'); }
    else { f.hcBad = false; f.hcMsg = '通过了。其实第一次你就选对了——界面只是想让你再证明一次。'; Store.logBait(false, '人类验证时，自己一张张点出了木偶', s.id); sfx('resist'); }
    renderSheet();
    setTimeout(() => { if (UI.sheet === s) { f.verified = true; renderSheet(); } }, 1400);
  },
};
Object.assign(ACT, {
  'hc-tile'(b) {
    const f = UI.sheet.form, i = Number(b.dataset.i);
    if (f.hcDone) return;
    f.picked = f.picked.includes(i) ? f.picked.filter((x) => x !== i) : [...f.picked, i];
    sfx('tick'); renderSheet();
  },
  'hc-submit'() {
    const s = UI.sheet, f = s.form, answer = f.tiles.map((t, i) => (t.puppet ? i : -1)).filter((i) => i >= 0);
    const right = answer.length === f.picked.length && answer.every((i) => f.picked.includes(i));
    if (right && f.hcTries) return HumanCheck.pass(s, false);
    f.hcBad = true;
    f.hcMsg = right ? '没通过，请再试一次。' : '选错了。再看看，哪些是木偶。';
    if (right) f.hcTries = 1;
    sfx('error'); HumanCheck.deal(f); renderSheet();
    const box = $('#hcBox'); if (box) box.classList.add('shake');
  },
  'hc-ai'() { HumanCheck.pass(UI.sheet, true); },
  'hold-nag'() {
    const s = UI.sheet;
    if (!s || !s.form) return;
    s.form.nagged = true; renderSheet();
    const btn = $('[data-hold="complete"]'); if (btn) btn.classList.add('shake');
  },
  grade(b) { UI.sheet.form.grade = b.dataset.v; sfx('tick'); renderSheet(); },
  'bait-all'(b) {
    const s = UI.sheet;
    if (!s.form.baitTapped) { s.form.baitTapped = true; Store.logBait(true, '登记完成时，点了“一键全部打勾”', s.id); }
    sfx('taken'); renderSheet();
    const btn = $('#baitBtn'); if (btn) btn.classList.add('shake');
  },
  complete() {
    const s = UI.sheet, f = s.form, id = s.id, done = Store.complete(id, f.grade, s.actual(), f.context, Focus.focusedMinutes(id));
    if (!done) return;
    if (Focus.state && Focus.state.taskId === id) Focus.stop();
    if (Store.mischief && !f.baitTapped) Store.logBait(false, '登记完成时，没有点“一键全部打勾”', id);
    sfx('task-complete'); sfx('xp', { delay: 0.2 });
    if (done.heal) sfx('heal', { delay: 0.4 });
    if (done.leveledUp) sfx('levelup', { delay: 0.6 });
    closeSheet(true);
    render();
    announce(f.grade === 'full' ? '做完了' : '做了一部分', `经验 +${done.xp}`);
    const notes = [];
    if (done.opened.length) { sfx('unlock', { delay: 1.1 }); notes.push('地图新开：' + done.opened.map((p) => p.name).join('、')); }
    if (done.newStrategy) notes.push(`夜谈多了一手「${done.newStrategy}」`);
    if (done.leveledUp) notes.push(`升到 Lv.${Store.level}`);
    if (notes.length) setTimeout(() => toast(notes.join(' · ')), 1300);
  },
});

SHEETS.adjust = (s) => {
  const t = Store.quest(s.id), f = s.form;
  if (!t) return { title: '目标变了', body: '' };
  if (f.title === undefined) Object.assign(f, { title: t.title, bonus: t.bonus, reason: '' });
  s.onInput = () => { $('#adjGo').disabled = !f.title.trim() || !f.reason.trim(); };
  return { title: '目标变了', scene: 'street', half: true,
    body: `<div class="field"><label for="adjTitle">现在真正要完成什么</label><input class="input" id="adjTitle" data-f="title" maxlength="80" value="${esc(f.title)}"></div>${seg('adj-kind', [['0', '仍是必做'], ['1', '改为额外']], f.bonus ? '1' : '0')}
    <div class="field"><label for="adjWhy">为什么变了</label><textarea class="input" id="adjWhy" data-f="reason" rows="2" maxlength="300" placeholder="比如：对方改了需求，今天先确认范围">${esc(f.reason)}</textarea></div>
    <button type="button" class="btn" id="adjGo" data-act="adj-go" ${f.title.trim() && f.reason.trim() ? '' : 'disabled'}>确认调整</button>` };
};
Object.assign(ACT, {
  'adj-kind'(b) { UI.sheet.form.bonus = b.dataset.v === '1'; sfx('tick'); renderSheet(); },
  'adj-go'() { const s = UI.sheet; if (Store.adjust(s.id, s.form.title, s.form.bonus, s.form.reason)) { sfx('accept'); closeSheet(true); render(); toast('调整记下了，最初写的那句还查得到。'); } },
});

/* 写一句话的小面板：缩小下一步 / 继续准备 / 反驳 / 假设。 */
SHEETS.note = (s) => {
  const f = s.form;
  if (f.text === undefined) f.text = s.initial || '';
  s.onInput = () => { $('#noteGo').disabled = !f.text.trim(); };
  return { title: s.title, scene: s.scene || 'square', half: true,
    body: `${(s.presets || []).map((p) => `<button type="button" class="btn quiet" data-act="note-preset" data-text="${esc(p)}">${esc(p)}</button>`).join('')}
    <div class="field"><label for="noteText">${esc(s.prompt)}</label><textarea class="input" id="noteText" data-f="text" rows="3" maxlength="300" placeholder="${esc(s.placeholder || '')}">${esc(f.text)}</textarea></div>
    <button type="button" class="btn" id="noteGo" data-act="note-go" ${f.text.trim() ? '' : 'disabled'}>${esc(s.button)}</button>`,
    ready: () => { if (!s.focused) { s.focused = true; setTimeout(() => { const i = $('#noteText'); if (i) i.focus(); }, 350); } } };
};
Object.assign(ACT, {
  'note-preset'(b) { UI.sheet.form.text = b.dataset.text; sfx('tick'); renderSheet(); },
  'note-go'() { const s = UI.sheet, text = s.form.text; sfx('accept'); closeSheet(true); s.submit(text); },
});
