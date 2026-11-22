/* 牌局 · 四夜之约（网页演示版）
   十个人围一张桌，三个提线人藏在中间。你每一夜的抉择同时决定两件事：
   这一夜谁出事、谁被请出山庄；你在 E/I · S/N · T/F · J/P 上往哪边偏。
   对外只有 window.Fate。所有文案来自 window.FATE_DATA（HumanContent/Resources/fate.json）。 */
(function () {
  'use strict';

  const KEY = 'human-content-demo-fate-v1';
  const CN = ['', '一', '二', '三', '四'];
  const CANCEL = { cancelled: true };
  const D = () => window.FATE_DATA;

  const esc = (s) => String(s === null || s === undefined ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
  const fast = () => window.FATE_FAST === true;
  const calm = () => !!(window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches);
  const cue = (name, o) => {
    try {
      if (typeof sfx === 'function') sfx(name, o || {});
    } catch (e) {}
  };
  const art = (key) => (window.ASSET && window.ASSET[key]) || '';
  const fill = (text, vars) => String(text).replace(/\{(\w+)\}/g, (m, k) => (vars[k] === undefined ? m : vars[k]));
  const shuffle = (list) => {
    const a = list.slice();
    for (let i = a.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      [a[i], a[j]] = [a[j], a[i]];
    }
    return a;
  };

  /* ---------- 存档 ---------- */
  let G = null; // 当前这一局
  let LAST = null; // 最近一次走完的结果

  function load() {
    try {
      const raw = JSON.parse(localStorage.getItem(KEY) || 'null');
      if (raw && typeof raw === 'object') {
        G = raw.game && raw.game.v === 1 && Array.isArray(raw.game.seats) ? raw.game : null;
        LAST = raw.last && raw.last.type ? raw.last : null;
      }
    } catch (e) {
      G = null;
      LAST = null;
    }
  }
  function save() {
    try {
      localStorage.setItem(KEY, JSON.stringify({ game: G, last: LAST }));
    } catch (e) {}
  }

  /* ---------- 规则 ---------- */
  function build(opts) {
    const d = D();
    const npcs = shuffle(d.npcs);
    const pullerAt = new Set(shuffle(npcs.map((_, i) => i)).slice(0, 3));
    const good = shuffle(d.goodPuppets);
    const bad = shuffle(d.pullerPuppets);
    const seats = [{ id: 'me', name: '你', tag: '', art: opts.roleArt || 'puppet_guard', side: 'good', alive: true, me: true }];
    npcs.forEach((p, i) => {
      const puller = pullerAt.has(i);
      const key = puller ? bad.pop() : good.pop() || 'villager';
      seats.push({ id: 'n' + i, name: p.n, tag: p.t, art: 'puppet_' + key, puppet: key, side: puller ? 'puller' : 'good', alive: true, me: false });
    });
    const doubt = {};
    // 提线人在细看之下更显眼：起点高一格。
    seats.forEach((s) => (doubt[s.id] = s.side === 'puller' ? 3 : 2));
    return {
      v: 1, seats, doubt, dead: [], exiled: [], right: 0, wrong: 0, answers: {}, picks: {}, tb: {},
      step: { s: 'intro', n: 1 }, replay: [], clue: '', noDeath: false, done: false, reported: false,
      role: opts.role || 'Guard', roleName: opts.roleName || '守门人', roleArt: opts.roleArt || 'puppet_guard',
    };
  }
  const seat = (id) => G.seats.find((s) => s.id === id);
  const alive = () => G.seats.filter((s) => s.alive);
  const pullersAlive = () => G.seats.filter((s) => s.alive && s.side === 'puller').length;
  const goodAlive = () => G.seats.filter((s) => s.alive && s.side === 'good').length;
  const caseFor = (n, kind) => D().cases.find((c) => c.night === n && c.kind === kind);

  function applyNight(fxKey) {
    const fx = D().nightFx[fxKey] || {};
    G.noDeath = !!fx.noDeath;
    G.clue = fx.clue || '';
    if (fx.doubt) {
      // 细看会让提线人更显眼，凭感觉则会把他们藏起来。
      G.seats.filter((s) => s.alive && s.side === 'puller').forEach((s) => {
        G.doubt[s.id] = Math.max(0, Math.min(9, (G.doubt[s.id] || 0) + fx.doubt));
      });
    }
  }
  /* 提线人动手：挑三个最不被怀疑的守夜人之一，从不挑你。 */
  function resolveNight() {
    const cands = G.seats.filter((s) => s.alive && s.side === 'good' && !s.me);
    if (!cands.length || G.noDeath) return null;
    const sorted = cands.slice().sort((a, b) => (G.doubt[a.id] || 0) - (G.doubt[b.id] || 0));
    const victim = sorted[Math.floor(Math.random() * Math.min(3, sorted.length))] || cands[0];
    victim.alive = false;
    G.dead.push(victim.id);
    return victim;
  }
  function resolveExile(strategy) {
    const cands = G.seats.filter((s) => s.alive && !s.me);
    if (!cands.length) return null;
    const jitter = {};
    cands.forEach((s) => (jitter[s.id] = (G.doubt[s.id] || 0) + Math.random() * 1.2));
    const byDoubt = cands.slice().sort((a, b) => jitter[b.id] - jitter[a.id]);
    let target;
    if (strategy === 'evidence') target = byDoubt[0];
    else if (strategy === 'heart') target = byDoubt[byDoubt.length - 1];
    else if (strategy === 'instinct') target = cands[Math.floor(Math.random() * cands.length)];
    else target = byDoubt[1] || byDoubt[0];
    target.alive = false;
    G.exiled.push(target.id);
    if (target.side === 'puller') G.right++;
    else G.wrong++;
    return target;
  }
  function score(g) {
    const d = D(), s = { EI: 0, SN: 0, TF: 0, JP: 0 };
    for (const c of d.cases) {
      const v = g.answers[c.id];
      if (typeof v === 'number') s[c.axis] += v;
    }
    for (const k in g.tb) s[k] += g.tb[k];
    return s;
  }
  function tally() {
    const d = D(), s = score(G), pct = {}, letters = [];
    for (const k of d.axisOrder) {
      const A = d.axes[k], p = Math.round(((s[k] + 6) / 12) * 100);
      pct[A.a] = p;
      pct[A.b] = 100 - p;
      letters.push(s[k] >= 0 ? A.a : A.b);
    }
    const type = letters.join('');
    const meta = d.types[type] || d.types.INFP;
    const fit = d.roleFit[type] || d.roleFit.INFP;
    const w = pullersAlive(), g = goodAlive();
    const win = w === 0 ? 'good' : w >= g ? 'puller' : 'good';
    return {
      type, nick: meta.nick, kin: d.kinName[meta.kin] || '', fitKey: fit.main, fitName: d.puppets[fit.main] || '', pct, win,
      rightVotes: G.right, wrongVotes: G.wrong,
      roleName: G.roleName,
      pullers: G.seats.filter((x) => x.side === 'puller').map((x) => x.name),
    };
  }
  const answered = (g) => (g ? D().cases.filter((c) => typeof g.answers[c.id] === 'number').length : 0);
  const stepNight = (g) => (!g ? 1 : g.step.s === 'intro' ? 1 : ['finale', 'ties', 'verdict'].includes(g.step.s) ? 4 : g.step.n);

  /* ---------- 界面 ---------- */
  let root = null, opts = null, runTok = 0, cancelers = new Set(), lastType = 0, keyHandler = null;

  const $ = (sel) => (root ? root.querySelector(sel) : null);
  function guard(tok) {
    if (tok !== runTok || !root) throw CANCEL;
  }
  /* 可以被关闭打断的等待。 */
  function waitable(start) {
    return new Promise((resolve, reject) => {
      const cancel = () => reject(CANCEL);
      cancelers.add(cancel);
      start((v) => {
        cancelers.delete(cancel);
        resolve(v);
      });
    });
  }
  const sleep = (ms) => waitable((done) => setTimeout(done, fast() ? 0 : ms));

  function shellHTML() {
    const scene = window.Atmo && window.Atmo.html ? window.Atmo.html('square', true) : '';
    return `${scene}<div class="fate-tint" aria-hidden="true"></div>
      <header class="fate-top"><div class="fate-top-l"><b id="fate-night">第一夜</b><span id="fate-role"></span></div>
      <div class="fate-top-r"><span id="fate-alive"></span><button type="button" class="fate-x" id="fate-x" aria-label="收起牌局"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="m6 6 12 12M18 6 6 18"/></svg></button></div></header>
      <div class="fate-seats" id="fate-seats"></div>
      <div class="fate-stage" id="fate-stage"><p class="fate-narr" id="fate-narr" aria-live="polite"></p><p class="fate-ask" id="fate-ask"></p><div class="fate-opts" id="fate-opts"></div></div>
      <div class="fate-dials" id="fate-dials" aria-hidden="true"></div>
      <div class="fate-verdict" id="fate-verdict" hidden></div>`;
  }
  function mood(m) {
    if (root) root.dataset.mood = m;
  }
  function renderTop() {
    if (!root || !G) return;
    const n = stepNight(G);
    $('#fate-night').textContent = D().nightNames[n] || '第' + CN[n] + '夜';
    $('#fate-role').textContent = `${G.roleName} · 守夜人`;
    $('#fate-alive').textContent = `${alive().length} 人在场`;
    renderSeats();
    renderDials();
  }
  function renderSeats(speaker) {
    const box = $('#fate-seats');
    if (!box) return;
    box.innerHTML = G.seats
      .map((s) => {
        const open = s.me || !s.alive;
        const face = open && art(s.art) ? `<i class="fate-face" style="background-image:url('${art(s.art)}')"></i>` : '<i class="fate-face fate-back"></i>';
        const cls = ['fate-seat', s.alive ? '' : 'out', s.me ? 'me' : '', !s.alive && s.side === 'puller' ? 'puller' : '', speaker && speaker === s.name ? 'say' : ''].join(' ');
        const label = s.me ? '你' : s.name;
        const state = s.me ? '你的座位' : !s.alive ? (s.side === 'puller' ? '提线人' : '守夜人') + (G.exiled.includes(s.id) ? '，已被请出山庄' : '，已出事') : '身份未知';
        return `<span class="${cls}" title="${esc(label)}" aria-label="${esc(label)}，${state}">${face}<b>${esc(label)}</b></span>`;
      })
      .join('');
  }
  function renderDials() {
    const box = $('#fate-dials');
    if (!box || !G) return;
    const d = D(), s = score(G);
    box.innerHTML = d.axisOrder
      .map((k) => {
        // 分数为正偏向左边的字母（E/S/T/J），指针往左走。
        const A = d.axes[k], p = Math.max(6, Math.min(94, ((6 - s[k]) / 12) * 100));
        return `<span class="fate-dial"><i>${A.a}</i><em><b style="left:${p.toFixed(0)}%"></b></em><i>${A.b}</i></span>`;
      })
      .join('');
  }

  /* 打字机：标点处停一拍。点一下打完这句，再点一下跳过停顿。 */
  function typeLine(tok, text, speed = 36) {
    const el = $('#fate-narr');
    if (!el) return Promise.reject(CANCEL);
    guard(tok);
    return waitable((done) => {
      el.textContent = '';
      if (fast() || calm()) {
        el.textContent = text;
        done();
        return;
      }
      let i = 0, timer = 0;
      const finish = () => {
        clearTimeout(timer);
        el.textContent = text;
        root && root.removeEventListener('fate-tap', finish);
        done();
      };
      const step = () => {
        if (!root) return;
        i++;
        el.textContent = text.slice(0, i);
        const now = performance.now();
        if (now - lastType > 90 && i % 3 === 0) {
          lastType = now;
          cue('type', { strength: 0.25 });
        }
        if (i >= text.length) return finish();
        const ch = text.charAt(i - 1);
        const extra = '，、；：'.includes(ch) ? 170 : '。！？'.includes(ch) ? 300 : ch === '…' || ch === '—' ? 220 : 0;
        timer = setTimeout(step, speed + extra);
      };
      root.addEventListener('fate-tap', finish, { once: true });
      timer = setTimeout(step, speed);
    });
  }
  function pause(tok, ms) {
    guard(tok);
    return waitable((done) => {
      if (fast()) return done();
      const t = setTimeout(fin, ms);
      function fin() {
        clearTimeout(t);
        root && root.removeEventListener('fate-tap', fin);
        done();
      }
      root.addEventListener('fate-tap', fin, { once: true });
    });
  }
  async function say(tok, item, speed) {
    const text = typeof item === 'string' ? item : item.t;
    const who = typeof item === 'string' ? '' : item.who || '';
    renderSeats(who);
    await typeLine(tok, text, speed);
    await pause(tok, Math.max(1100, text.replace(/\n/g, '').length * 46));
    renderSeats();
  }
  async function sayAll(tok, list, speed) {
    for (const item of list) await say(tok, item, speed);
  }
  /* 场上的人开口：只挑还在桌边的人。 */
  function chatter(pool, count) {
    const living = {};
    G.seats.forEach((s) => s.alive && (living[s.name] = true));
    const out = [];
    for (const c of shuffle(D().chatter[pool] || [])) {
      if (c.who && !living[c.who]) continue;
      const t = !c.who ? c.t : c.t.charAt(0) === '（' ? c.who + c.t : `${c.who}：「${c.t}」`;
      out.push({ who: c.who || '', t });
      if (out.length >= count) break;
    }
    return out;
  }
  function setAsk(text) {
    const el = $('#fate-ask');
    if (el) el.textContent = text || '';
  }
  function choose(tok, list) {
    guard(tok);
    const box = $('#fate-opts');
    return waitable((done) => {
      const letters = D().letters;
      box.innerHTML = list.map((t, i) => `<button type="button" class="fate-opt" data-i="${i}"><span class="fate-letter">${letters[i] || i + 1}</span><span class="fate-opt-t">${esc(t)}</span></button>`).join('');
      box.classList.add('on');
      const stage = $('#fate-stage');
      if (stage) stage.scrollTop = stage.scrollHeight;
      const once = (e) => {
        const b = e.target.closest('.fate-opt');
        if (!b) return;
        box.removeEventListener('click', once);
        box.classList.remove('on');
        box.innerHTML = '';
        cue('click');
        done(Number(b.dataset.i));
      };
      box.addEventListener('click', once);
    });
  }
  /* 问一题：先念情境，再给甲乙丙。已经答过的题直接沿用。 */
  async function ask(tok, item) {
    if (typeof G.answers[item.id] === 'number' && typeof G.picks[item.id] === 'number') return G.picks[item.id];
    await say(tok, item.text, 32);
    setAsk(item.ask);
    const i = await choose(tok, item.opts.map((o) => o.t));
    setAsk('');
    G.answers[item.id] = item.opts[i].v;
    G.picks[item.id] = i;
    renderDials();
    return i;
  }
  async function playReplay(tok) {
    for (const item of G.replay) {
      if (item.cue) cue(item.cue, item.opts);
      if (item.mood) mood(item.mood);
      if (item.top) renderTop();
      await say(tok, item, item.speed || 28);
    }
    G.replay = [];
    save();
  }
  function advance(next) {
    G.step = next;
    save();
  }

  /* ---------- 主流程 ---------- */
  async function run(tok, resuming) {
    const d = D();
    renderTop();
    if (resuming && G.step.s !== 'intro') {
      mood('night');
      await say(tok, d.lines.resume, 30);
      if (G.replay.length) await playReplay(tok);
    }
    for (;;) {
      guard(tok);
      const { s, n } = G.step;
      if (s === 'intro') {
        mood('night');
        await sayAll(tok, d.lines.opening, 34);
        advance({ s: 'night', n: 1 });
      } else if (s === 'night') {
        if (n >= 2 && (opts.completed || 0) < n - 1) return gate(tok, n);
        mood('night');
        renderTop();
        cue('countdown', { strength: 0.4 });
        const lead = d.roleLead[G.role];
        await sayAll(tok, [d.lines.night].concat(lead ? [lead] : []), 30);
        await sayAll(tok, chatter('night', 1), 32);
        const c = caseFor(n, 'night');
        const i = await ask(tok, c);
        applyNight(c.opts[i].fx);
        G.replay = [{ t: c.opts[i].r, speed: 26 }];
        advance({ s: 'dawn', n });
        await playReplay(tok);
      } else if (s === 'dawn') {
        const victim = resolveNight();
        const line = victim ? fill(d.lines.dawnDeath, { name: victim.name }) : fill(d.lines.dawnSafe, { n: alive().length });
        G.replay = [{ t: line, mood: 'dawn', top: true, cue: victim ? 'damage' : 'settle-safe' }].concat(chatter(victim ? 'dawnDeath' : 'dawnSafe', 1));
        if (G.clue) G.replay.push({ t: G.clue });
        advance({ s: 'day', n });
        await playReplay(tok);
      } else if (s === 'day') {
        mood('day');
        renderTop();
        await sayAll(tok, chatter('day', 2), 32);
        const c = caseFor(n, 'say');
        const i = await ask(tok, c);
        G.replay = [{ t: c.opts[i].r, speed: 26 }].concat(chatter('afterSay', 1));
        advance({ s: 'vote', n });
        await playReplay(tok);
      } else if (s === 'vote') {
        mood('day');
        const c = caseFor(n, 'vote');
        const i = await ask(tok, c);
        const out = resolveExile(c.opts[i].fx);
        G.replay = [{ t: c.opts[i].r, speed: 26 }];
        if (out) {
          const hit = out.side === 'puller';
          const lines = d.lines[hit ? 'exileHit' : 'exileMiss'];
          G.replay.push({ t: fill(lines[0], { name: out.name }), cue: 'vote', mood: hit ? 'blood' : 'day', top: true });
          G.replay.push({ t: lines[1], cue: hit ? 'reveal-success' : 'reveal-wrong' });
          G.replay = G.replay.concat(chatter(hit ? 'voteHit' : 'voteMiss', 1));
        }
        G.replay.push({ t: fill(d.lines.count, { n: alive().length, w: pullersAlive() }), top: true });
        advance(n >= 4 ? { s: 'finale', n: 4 } : { s: 'night', n: n + 1 });
        if (out) setTimeout(() => cue('stamp'), fast() ? 0 : 140);
        await playReplay(tok);
      } else if (s === 'finale') {
        mood('night');
        await sayAll(tok, d.lines.finale, 28);
        advance({ s: 'ties', n: 4 });
      } else if (s === 'ties') {
        const sc = score(G);
        const ties = d.axisOrder.filter((k) => sc[k] === 0 && G.tb[k] === undefined);
        if (ties.length) {
          mood('dawn');
          await say(tok, d.lines.ties, 26);
          for (const k of ties) {
            const t = d.tiebreak[k];
            await say(tok, t.text, 28);
            setAsk(t.ask);
            const i = await choose(tok, t.opts.map((o) => o.t));
            setAsk('');
            G.tb[k] = t.opts[i].v;
            renderDials();
            G.replay = [{ t: t.opts[i].r, speed: 26 }];
            save();
            await playReplay(tok);
          }
        }
        const res = tally();
        G.done = true;
        LAST = res;
        advance({ s: 'verdict', n: 4 });
        await sleep(400);
        guard(tok);
        return showVerdict(res, true);
      } else {
        return showVerdict(LAST || tally(), true);
      }
    }
  }

  /* 下一夜要等现实里再做完一件事。 */
  async function gate(tok, n) {
    mood('night');
    renderTop();
    await typeLine(tok, fill(D().lines.gate, { night: CN[n] || n }), 32);
    setAsk('');
    const box = $('#fate-opts');
    box.innerHTML = `<button type="button" class="fate-btn" data-exit="tasks">去任务板</button><button type="button" class="fate-btn quiet" data-exit="close">先收着</button>`;
    box.classList.add('on', 'gate');
    cue('lock');
    box.addEventListener('click', (e) => {
      const b = e.target.closest('[data-exit]');
      if (b) exit(b.dataset.exit);
    });
  }

  /* ---------- 结算页 ---------- */
  function showVerdict(res, fresh) {
    const box = $('#fate-verdict');
    if (!box) return;
    const d = D();
    const fit = d.roleFit[res.type] || d.roleFit.INFP;
    const meta = d.types[res.type] || d.types.INFP;
    const axis = (k) => {
      const A = d.axes[k], p = res.pct[A.a];
      return `<div class="fate-axis"><div class="fate-axis-top"><b class="${p >= 50 ? 'hi' : ''}">${A.a} ${A.an}</b><span>${p}% · ${100 - p}%</span><b class="${p < 50 ? 'hi' : ''}">${A.b} ${A.bn}</b></div><div class="fate-axis-bar"><i style="left:${Math.max(3, Math.min(97, 100 - p))}%"></i></div><p>${esc(p >= 50 ? A.ad : A.bd)}</p></div>`;
    };
    const inProgress = G && !G.done;
    box.innerHTML = `<div class="fate-v-head"><span class="fate-kicker">四夜之约 · 结算</span><b class="fate-code">${esc(res.type)}</b><span class="fate-nick">${esc(meta.nick)} · ${esc(res.kin || d.kinName[meta.kin] || '')}</span><span class="fate-stack">${esc(meta.stack)}</span></div>
      <section class="fate-block"><h3>四个维度</h3>${d.axisOrder.map(axis).join('')}</section>
      <section class="fate-block"><h3>你是这样的人</h3><p class="fate-drive">${esc(meta.drive)}</p><div class="fate-two"><div><span>最强</span>${esc(meta.best)}</div><div><span>最怕</span>${esc(meta.fear)}</div></div></section>
      <section class="fate-block"><h3>最像你的木偶</h3><div class="fate-fit"><div class="fate-fit-card"><i style="background-image:url('${art('puppet_' + fit.main)}')"></i><b>${esc(d.puppets[fit.main] || '')}</b></div><div class="fate-fit-body"><p>${esc(fit.why)}</p><small>也很像：${fit.alt.map((k) => esc(d.puppets[k] || '')).join(' · ')}</small></div></div></section>
      <section class="fate-block"><h3>这一局的账</h3><div class="fate-ledger"><div><span>你的身份</span><b>${esc(res.roleName || (G && G.roleName) || '')} · 守夜人</b></div><div><span>提线人是谁</span><b>${esc((res.pullers || []).join('、'))}</b></div><div><span>请对 / 请错</span><b>${res.rightVotes} / ${res.wrongVotes}</b></div><div><span>结局</span><b class="${res.win === 'good' ? 'good' : 'bad'}">${res.win === 'good' ? '守夜人胜' : '提线人胜'}</b></div></div><p class="fate-note">${esc(d.note)}</p></section>
      <div class="fate-v-actions"><button type="button" class="fate-btn" data-v="home">回山庄</button><button type="button" class="fate-btn quiet" data-v="again">${inProgress ? '接着打这一局' : '再打一局'}</button></div>`;
    box.hidden = false;
    box.scrollTop = 0;
    root.classList.add('fate-v-on');
    box.onclick = (e) => {
      const b = e.target.closest('[data-v]');
      if (!b) return;
      cue('click');
      if (b.dataset.v === 'home') return exit('done');
      box.hidden = true;
      root.classList.remove('fate-v-on');
      if (!inProgress) G = build(opts);
      save();
      start(false);
    };
    if (fresh) {
      cue('levelup');
      if (G && G.done && !G.reported) {
        G.reported = true;
        save();
        try {
          opts.onResult && opts.onResult(res);
        } catch (e) {}
      }
    }
  }

  /* ---------- 开关 ---------- */
  function start(resuming) {
    const tok = ++runTok;
    $('#fate-narr').textContent = '';
    setAsk('');
    const box = $('#fate-opts');
    box.innerHTML = '';
    box.className = 'fate-opts';
    run(tok, resuming).catch((e) => {
      if (e !== CANCEL) console.error(e);
    });
  }
  function teardown() {
    runTok++;
    for (const c of cancelers) c();
    cancelers = new Set();
    if (keyHandler) document.removeEventListener('keydown', keyHandler);
    keyHandler = null;
    if (root) root.remove();
    root = null;
  }
  function exit(reason) {
    if (!root) return;
    save();
    const cb = opts && opts.onExit;
    teardown();
    cue('close');
    try {
      cb && cb(reason);
    } catch (e) {}
  }

  window.Fate = {
    open(o) {
      if (root) return false;
      const shell = document.getElementById('shell');
      if (!shell || !D()) return false;
      opts = Object.assign({ completed: 0, role: 'Guard', roleName: '守门人', roleArt: 'puppet_guard' }, o || {});
      load();
      root = document.createElement('div');
      root.className = 'fate';
      root.id = 'fate-root';
      root.dataset.mood = 'night';
      root.setAttribute('role', 'dialog');
      root.setAttribute('aria-label', '牌局 · 四夜之约');
      root.innerHTML = shellHTML();
      shell.appendChild(root);
      $('#fate-x').addEventListener('click', () => exit('close'));
      $('#fate-stage').addEventListener('click', (e) => {
        if (!e.target.closest('button')) root.dispatchEvent(new Event('fate-tap'));
      });
      keyHandler = (e) => {
        if (e.key === 'Escape') {
          e.stopPropagation();
          exit('close');
        }
      };
      document.addEventListener('keydown', keyHandler);
      cue('whoosh');
      if (opts.toVerdict && LAST) {
        if (G) renderTop();
        else {
          $('#fate-alive').textContent = '';
          $('#fate-role').textContent = `${opts.roleName} · 守夜人`;
        }
        showVerdict(LAST, false);
        return true;
      }
      const resuming = !!G && !G.done;
      if (!G || G.done) G = build(opts);
      G.role = opts.role;
      G.roleName = opts.roleName;
      if (!G.seats[0].alive) G.seats[0].alive = true;
      G.seats[0].art = opts.roleArt;
      G.roleArt = opts.roleArt;
      save();
      start(resuming);
      return true;
    },
    close() {
      exit('close');
    },
    isOpen() {
      return !!root;
    },
    status(completed) {
      load();
      const g = G;
      const done = !!LAST;
      const live = g && !g.done;
      const n = live ? stepNight(g) : 1;
      let nextNeed = 0;
      if (live && g.step.s === 'night' && n >= 2) nextNeed = Math.max(0, n - 1 - (completed || 0));
      return {
        started: !!live && (answered(g) > 0 || g.step.s !== 'intro'),
        done,
        answered: live ? answered(g) : done ? 12 : 0,
        night: n,
        nextNeed,
        type: LAST ? LAST.type : '',
        nick: LAST ? LAST.nick : '',
        fitName: LAST ? LAST.fitName : '',
        fitArt: LAST ? 'puppet_' + LAST.fitKey : '',
      };
    },
    reset() {
      G = null;
      LAST = null;
      try {
        localStorage.removeItem(KEY);
      } catch (e) {}
    },
  };
})();
