/* 木偶剧场 · 反向体验（网页演示版）
   对外只有 window.Lab = { open, close, isOpen }。界面故意使坏：抢写、追着你跑的按钮、
   会换位的选项、默认同意的倒计时。所有破坏只发生在这一层里，不碰宿主页面的任何状态。 */
(function () {
  'use strict';

  const ALT = '先不做，等 AI 再成熟一点';
  const ORDER = ['prologue', 'feed', 'wait', 'pixel', 'argue', 'retry', 'archive'];
  const KEYS = ORDER.slice(0, 6);
  const BACKSTAGE = ['retry'];
  const NAME = { prologue: '抢写补全', feed: '收藏夹', wait: '等待', pixel: '像素', argue: '反驳', retry: '第 N 次', archive: '记录' };
  const ACT = (k) => (k === 'prologue' ? '序幕' : k === 'archive' ? '终幕' : `第 ${KEYS.indexOf(k)} 幕`);
  const LABEL = (k) => `${ACT(k)} · ${NAME[k]}`;
  const CHIP = { prologue: '想法', feed: '收藏中', wait: '制作中', pixel: '打磨中', argue: '待验证', retry: '测试中' };
  const HEAD = {
    prologue: ['写下一件想做的事。', '一停笔，它就替你写。'],
    feed: ['动手之前，先看看别人是怎么做的。', '在这里，点哪儿都是收藏。'],
    wait: ['交给 Agent 吧。你只需要点“允许”。', '不点，它就当你同意了。'],
    pixel: ['Agent 交出了初版。对齐到虚线框，然后发布。', '差 6 点以内就算对齐，它不会告诉你。'],
    argue: ['发布前，AI 评审看了一眼你的想法。', '十秒不回应，就算你同意。'],
    retry: ['最后一轮：指针走进亮块时，按下“发射”。', ''],
  };
  const IDLE = {
    prologue: '8 秒没动。连想做什么，都要想这么久。',
    feed: '你不点，它也在放。看得还挺认真。',
    wait: '你没在看。弹窗会默认允许的。',
    pixel: '盯着它看，像素不会自己对齐。',
    argue: '沉默也是一种回答。倒计时还在走。',
    retry: '不按，就不会失败。也不会通过。',
  };
  const AIH = ['点一下就好', '就等你了', '我比你快', '别装了，点吧'];
  const COVERS = ['pano_street', 'pano_square', 'pano_chapel', 'pano_docks'];

  const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
  const pad = (n) => String(n).padStart(2, '0');
  const reflow = (el) => void el.offsetWidth;
  const short = (s) => (s.length > 10 ? s.slice(0, 10) + '…' : s);
  const calm = () => !!(window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches);
  const cue = (name, o) => {
    try {
      if (typeof sfx === 'function') sfx(name, o || {});
    } catch (e) {}
  };
  const vids = (k) => [
    { a: '@AI效率君', t: `3 分钟看懂：「${k}」其实很简单` },
    { a: '@Agent研究所', t: `我用 AI Agent 一晚上就做完了「${k}」` },
    { a: '@收藏夹吃灰了', t: `收藏了就是会了：「${k}」完整教程（上）` },
    { a: '@每天进步一点点', t: '为什么你迟迟没有开始？' },
    { a: '@自律打卡王', t: `别急着做「${k}」，先看完这条` },
  ];
  /* 过场里只陈述发生过的操作，不替人下结论。 */
  const facts = (text) =>
    String(text)
      .replace(/我们今晚再看它。/g, '演练结束后可以对照这份副本。')
      .replace(/你做了 0 件。/g, '本幕没有登记任何现实行动。')
      .replace(/你也没有开始。/g, '你没有点“现在就做”。')
      .replace(/5 条视频放完，你才被动开始。/g, '5 条视频放完后，界面自动进入下一幕。')
      .replace(/你没有看，系统默认允许了。/g, '你未点击，系统默认允许了。')
      .replace(/你读了，你拒绝了。/g, '你点了“拒绝”。')
      .replace(/你没有对齐就发布了。没有人注意到。/g, '你没有对齐，就按下了模拟发布。')
      .replace(/你没有发现。/g, '界面没有明确告诉你。')
      .replace(/第 5 次，你一定能通过。/g, '规则从第 5 次起大幅扩大了目标区。')
      .replace(/你的想法现在是 AI 的。/g, '试玩副本被剧情 AI 改写。');

  const ICON_LOCK = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M7 10V7a5 5 0 0 1 10 0v3h1a1 1 0 0 1 1 1v9a1 1 0 0 1-1 1H6a1 1 0 0 1-1-1v-9a1 1 0 0 1 1-1zm2 0h6V7a3 3 0 0 0-6 0z"/></svg>';
  const ICON_MARK = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 3h12v18l-6-4.5L6 21z"/></svg>';
  const ICON_X = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 6l12 12M18 6 6 18"/></svg>';

  let current = null;

  function session(opts) {
    const shell = document.getElementById('shell') || document.body;
    const backstage = opts.backstageOpen !== false;
    const taskTitle = typeof opts.taskTitle === 'string' ? opts.taskTitle.trim().slice(0, 160) : '';
    const onExit = typeof opts.onExit === 'function' ? opts.onExit : null;
    const wanted = ['intro'].concat(ORDER).includes(opts.level) ? opts.level : 'intro';

    let backdrop = '';
    try {
      if (window.Atmo && typeof window.Atmo.html === 'function') backdrop = String(window.Atmo.html('docks', true) || '');
    } catch (e) {}

    const root = document.createElement('div');
    root.className = 'lab';
    root.id = 'lab-root';
    root.setAttribute('role', 'dialog');
    root.setAttribute('aria-modal', 'true');
    root.setAttribute('aria-label', '木偶剧场，反向体验');
    root.innerHTML =
      backdrop +
      `<header class="lab-hud">
        <div class="lab-hud-top">
          <button type="button" class="lab-idea" id="lab-idea"><span class="lab-idea-k">你的想法<i class="lab-chip" id="lab-chip">—</i></span><b id="lab-idea-text">尚未写下</b></button>
          <button type="button" class="lab-fav" id="lab-fav" aria-label="试玩收藏夹">${ICON_MARK}<i id="lab-fav-n">0</i></button>
          <button type="button" class="lab-clock" id="lab-clock" aria-label="剧情时间">09:00</button>
          <button type="button" class="lab-x" id="lab-exit" aria-label="退出演练，回到任务"><span>${ICON_X}</span></button>
        </div>
        <nav class="lab-steps" id="lab-steps" aria-label="跳到某一幕"></nav>
      </header>
      <main class="lab-stage" id="lab-stage"></main>
      <button type="button" class="lab-ai" id="lab-ai" hidden>让 AI 来</button>
      <div class="lab-voice" id="lab-voice" aria-hidden="true"></div>
      <div class="lab-sr" id="lab-live" aria-live="polite"></div>
      <div class="lab-fx" id="lab-fx" aria-hidden="true"></div>
      <div class="lab-flash" id="lab-flash" aria-hidden="true"></div>
      <div class="lab-slam" id="lab-slam" aria-hidden="true"></div>`;
    shell.appendChild(root);
    root.tabIndex = -1;
    try {
      root.focus({ preventScroll: true });
    } catch (e) {}

    const $ = (s) => root.querySelector(s);
    const stage = $('#lab-stage'),
      aiBtn = $('#lab-ai'),
      voiceEl = $('#lab-voice'),
      liveEl = $('#lab-live'),
      fxEl = $('#lab-fx'),
      flashEl = $('#lab-flash'),
      slamEl = $('#lab-slam'),
      stepsEl = $('#lab-steps');

    const fresh = () => ({
      idea: '',
      ideaNow: '',
      pred: { done: 50, ai: 1, saves: 2 },
      t0: 0,
      saves: [],
      ai: {},
      lost: {},
      mirror: {},
      level: '',
      key: null,
      aiHandler: null,
      raf: 0,
      tEnd: 0,
      r: { ghost: 0, retry: null, aiHover: 0, read: null },
    });
    let S = fresh();
    let records = [];
    let notes = {};
    let startedAt = Date.now();
    let ended = false;

    const open = (key) => !BACKSTAGE.includes(key) || backstage;
    const nextOf = (key) => {
      for (let i = ORDER.indexOf(key) + 1; i < ORDER.length; i++) if (open(ORDER[i])) return ORDER[i];
      return 'archive';
    };

    /* ---- 计时器与监听：一幕结束就全部清掉 ---- */
    const T = [];
    const later = (f, ms) => {
      const id = setTimeout(f, ms);
      T.push(id);
      return id;
    };
    const every = (f, ms) => {
      const id = setInterval(f, ms);
      T.push(id);
      return id;
    };
    let offs = [];
    const on = (node, type, fn, o) => {
      node.addEventListener(type, fn, o);
      offs.push(() => node.removeEventListener(type, fn, o));
    };
    const clearAll = () => {
      T.forEach((id) => {
        clearTimeout(id);
        clearInterval(id);
      });
      T.length = 0;
      offs.forEach((f) => f());
      offs = [];
    };

    /* ---- 剧情时间：现实 0.3 秒走一分钟 ---- */
    const mins = () => (S.t0 ? Math.min(1439, 540 + Math.floor(((S.tEnd || Date.now()) - S.t0) / 300)) : 540);
    const clockStr = () => {
      const m = mins();
      return `${pad(Math.floor(m / 60))}:${pad(m % 60)}`;
    };

    /* ---- 反馈：晃动、闪屏、粒子、大字、字幕 ---- */
    const local = (x, y) => {
      const r = root.getBoundingClientRect();
      return [x - r.left, y - r.top];
    };
    const shake = (n = 1) => {
      if (calm()) return;
      stage.classList.remove('lab-shake1', 'lab-shake2');
      reflow(stage);
      stage.classList.add('lab-shake' + n);
    };
    const flash = (c = 'bad') => {
      if (calm()) return;
      flashEl.className = 'lab-flash';
      reflow(flashEl);
      flashEl.className = 'lab-flash lab-f-' + c;
    };
    const ring = (x, y) => {
      if (calm()) return;
      const [lx, ly] = local(x, y);
      const r = document.createElement('i');
      r.className = 'lab-ring';
      r.style.left = lx + 'px';
      r.style.top = ly + 'px';
      fxEl.append(r);
      setTimeout(() => r.remove(), 520);
    };
    const burst = (x, y, n = 12, txt = '+1') => {
      if (calm()) return;
      const [lx, ly] = local(x, y);
      for (let i = 0; i < n; i++) {
        const p = document.createElement('span');
        p.className = 'lab-p';
        p.textContent = txt;
        const a = Math.random() * Math.PI * 2,
          d = 60 + Math.random() * 150;
        p.style.cssText = `left:${lx}px;top:${ly}px;--lab-dx:${Math.cos(a) * d}px;--lab-dy:${Math.sin(a) * d - 50}px;--lab-r:${Math.round(Math.random() * 120 - 60)}deg;font-size:${Math.round(14 + Math.random() * 22)}px`;
        fxEl.append(p);
        setTimeout(() => p.remove(), 850);
      }
    };
    let slamTimer = 0;
    const slam = (big, small = '', ms = 850, cls = '') => {
      slamEl.className = 'lab-slam';
      reflow(slamEl);
      slamEl.style.setProperty('--lab-ms', ms + 'ms');
      slamEl.innerHTML = `<div><b>${esc(big)}</b><span>${esc(small)}</span></div>`;
      slamEl.className = 'lab-slam lab-on' + (cls ? ' lab-s-' + cls : '');
      clearTimeout(slamTimer);
      slamTimer = setTimeout(() => {
        slamEl.className = 'lab-slam';
      }, ms);
    };
    let voiceI = 0,
      voiceT = 0;
    const voice = (msg) => {
      if (ended) return;
      clearInterval(voiceI);
      clearTimeout(voiceT);
      let i = 0;
      voiceEl.textContent = '';
      voiceEl.classList.add('lab-on');
      liveEl.textContent = msg;
      cue('type');
      voiceI = setInterval(() => {
        voiceEl.textContent = msg.slice(0, ++i);
        if (i >= msg.length) {
          clearInterval(voiceI);
          voiceT = setTimeout(() => voiceEl.classList.remove('lab-on'), 2600);
        }
      }, 18);
    };

    /* ---- 顶栏 ---- */
    const favUpd = (bump) => {
      const n = $('#lab-fav-n');
      n.textContent = S.saves.length;
      if (bump) {
        n.classList.remove('lab-bump');
        reflow(n);
        n.classList.add('lab-bump');
      }
    };
    const hudIdea = () => {
      $('#lab-idea-text').textContent = S.ideaNow || '尚未写下';
      $('#lab-idea').classList.toggle('lab-lost', !!S.idea && S.ideaNow !== S.idea);
    };
    const setChip = (t) => {
      $('#lab-chip').textContent = t;
    };
    const drawSteps = () => {
      stepsEl.innerHTML = ORDER.map((k, i) => {
        const locked = !open(k);
        const cls = S.level === k ? 'lab-cur' : S.mirror[k] ? (S.ai[k] || S.lost[k] ? 'lab-byai' : 'lab-ok') : '';
        const mark = locked ? ICON_LOCK : i === 0 ? '序' : i === 6 ? '终' : i;
        return `<button type="button" data-k="${k}" class="${cls}${locked ? ' lab-locked' : ''}" aria-label="${locked ? '还没开门：' : '跳到：'}${LABEL(k)}"${S.level === k ? ' aria-current="step"' : ''}><span>${mark}</span></button>`;
      }).join('');
    };
    stepsEl.addEventListener('click', (e) => {
      const b = e.target.closest('button');
      if (!b) return;
      const k = b.dataset.k;
      if (!open(k)) {
        cue('lock');
        shake(1);
        voice('后台还没开门。先去现实里做完两件事。');
        return;
      }
      if (!S.t0) S.t0 = Date.now();
      if (k !== 'prologue' && !S.idea) {
        S.idea = S.ideaNow = '做一个记账小程序';
        hudIdea();
      }
      cue('nav');
      go(k);
    });
    $('#lab-fav').addEventListener('click', () => voice(S.saves.length ? '打开也不会变少。终幕再看。' : '还是空的。别急，你会填满它的。'));
    $('#lab-idea').addEventListener('click', () => voice(S.idea ? '看着它，不会让它完成。' : '还没写。看也没用。'));
    $('#lab-clock').addEventListener('click', () => voice('看时间，不会让它变慢。'));
    $('#lab-exit').addEventListener('click', () => leave());

    /* ---- “让 AI 来” ---- */
    aiBtn.addEventListener('pointerenter', (e) => {
      if (e.pointerType !== 'mouse' || aiBtn.disabled || !S.aiHandler) return;
      S.r.aiHover++;
      aiBtn.textContent = AIH[(S.r.aiHover - 1) % AIH.length];
    });
    aiBtn.addEventListener('pointerleave', (e) => {
      if (e.pointerType !== 'mouse' || aiBtn.disabled || !S.aiHandler) return;
      aiBtn.textContent = '让 AI 来';
      if (S.r.aiHover % 2 === 1) voice('手都放上去了。想好了再来。');
    });
    aiBtn.addEventListener('click', () => {
      if (aiBtn.disabled || !S.aiHandler) return;
      const h = S.aiHandler,
        lv = S.level;
      S.aiHandler = null;
      S.key = null;
      S.ai[lv] = true;
      clearAll();
      if (S.raf) cancelAnimationFrame(S.raf);
      S.raf = 0;
      slam('AI 已接管', ['这就对了', '省事', '你歇着'][(KEYS.filter((k) => S.ai[k]).length - 1) % 3], 750, 'ai');
      cue('takeover');
      afterTakeover = setTimeout(() => {
        if (!ended && S.level === lv) h();
      }, 400);
    });
    let afterTakeover = 0;

    /* ---- 发呆、连点、切走 ---- */
    let lastAct = Date.now(),
      idleSaid = false,
      clicksT = [],
      rageAt = 0,
      awayAt = 0;
    const touchAct = () => {
      lastAct = Date.now();
    };
    const onRootDown = () => {
      const n = Date.now();
      lastAct = n;
      clicksT.push(n);
      clicksT = clicksT.filter((t) => n - t < 1500);
      if (clicksT.length >= 6 && n - rageAt > 6000 && IDLE[S.level] && S.level !== 'feed') {
        rageAt = n;
        voice('检测到连点。点得再快，它也不会更快。');
        shake(1);
      }
    };
    const onKey = (e) => {
      if (e.isComposing || e.keyCode === 229) return;
      lastAct = Date.now();
      if (e.key === 'Escape') {
        e.preventDefault();
        leave();
        return;
      }
      if (!ended && S.key) S.key(e);
    };
    const onVisible = () => {
      if (document.hidden) awayAt = Date.now();
      else if (awayAt) {
        const sec = Math.round((Date.now() - awayAt) / 1000);
        awayAt = 0;
        if (sec >= 2 && IDLE[S.level]) voice(`你离开了 ${sec} 秒。它没有自己完成。`);
      }
    };
    root.addEventListener('pointerdown', onRootDown, { passive: true });
    root.addEventListener('pointermove', touchAct, { passive: true });
    document.addEventListener('keydown', onKey);
    document.addEventListener('visibilitychange', onVisible);
    const clockTimer = setInterval(() => {
      $('#lab-clock').textContent = clockStr();
    }, 300);
    const idleTimer = setInterval(() => {
      if (!IDLE[S.level] || idleSaid || document.hidden) return;
      if (Date.now() - lastAct > 8000) {
        idleSaid = true;
        voice(IDLE[S.level]);
      }
    }, 1000);

    /* 鼠标刚移上“该做的事”时假装卡 0.7 秒；诱惑按钮从不卡。触屏没有悬停，直接生效。 */
    const doBtn = (el, fn) => {
      el.addEventListener('pointerenter', (e) => {
        if (e.pointerType !== 'mouse') return;
        el._h = Date.now();
        el.classList.add('lab-lag');
        setTimeout(() => el.classList.remove('lab-lag'), 700);
      });
      el.addEventListener('click', (e) => {
        if (e.detail > 0 && Date.now() - (el._h || 0) < 700) {
          cue('error', { strength: 0.5 });
          return;
        }
        fn(e);
      });
    };

    const head = (k) => `<h2 class="lab-h">${esc(HEAD[k][0])}</h2>${HEAD[k][1] ? `<p class="lab-hint">${esc(HEAD[k][1])}</p>` : ''}`;

    /* ---- 换幕 ---- */
    const R = {};
    const cleanup = () => {
      clearAll();
      clearTimeout(afterTakeover);
      S.key = null;
      S.aiHandler = null;
      if (S.raf) cancelAnimationFrame(S.raf);
      S.raf = 0;
      root.querySelectorAll('.lab-modal').forEach((m) => m.remove());
    };
    const go = (name) => {
      if (ended) return;
      if (!R[name] || !open(name)) name = 'intro';
      cleanup();
      S.level = name;
      idleSaid = false;
      lastAct = Date.now();
      if (name !== 'archive') S.tEnd = 0;
      if (CHIP[name]) setChip(CHIP[name]);
      const lv = KEYS.includes(name);
      aiBtn.hidden = !lv;
      aiBtn.disabled = false;
      aiBtn.style.transform = '';
      aiBtn.textContent = '让 AI 来';
      R[name]();
      drawSteps();
      stage.scrollTop = 0;
      if (lv) {
        slam(NAME[name], ACT(name), 800);
        cue('open');
      }
    };
    const interlude = (level, mirror) => {
      if (ended) return;
      cleanup();
      aiBtn.hidden = true;
      const next = nextOf(level);
      const text = facts(mirror);
      S.mirror[level] = text;
      S.level = 'inter';
      drawSteps();
      records.push({
        key: level,
        label: LABEL(level),
        facts: text,
        byAI: !!S.ai[level],
        atSeconds: Math.max(0, Math.round((Date.now() - startedAt) / 1000)),
      });
      stage.innerHTML = `<section class="lab-sec">
        <p class="lab-dim">${esc(LABEL(level))} · 刚才发生的事</p>
        <p class="lab-mirror">${esc(text)}</p>
        <label class="lab-note-label" for="lab-note">留一句自己的观察（可不填）</label>
        <input type="text" class="lab-note" id="lab-note" maxlength="300" autocomplete="off" placeholder="例如：我本来想拒绝，按钮换位以后点错了" value="${esc(notes[level] || '')}">
        <button type="button" class="lab-btn lab-do" id="lab-next">${next === 'archive' ? '看这一轮的记录' : '继续下一幕'}</button>
        <button type="button" class="lab-btn lab-quiet" id="lab-inter-return">回到任务</button>
      </section>`;
      const note = $('#lab-note');
      const keep = () => {
        notes[level] = note.value.trim().slice(0, 300);
      };
      note.addEventListener('input', () => {
        keep();
        cue('type');
      });
      const nx = () => {
        keep();
        cue('paper');
        go(next);
      };
      $('#lab-next').addEventListener('click', nx);
      $('#lab-inter-return').addEventListener('click', () => {
        keep();
        leave();
      });
      S.key = (e) => {
        if (e.key === 'Enter' && !['BUTTON', 'TEXTAREA'].includes(document.activeElement && document.activeElement.tagName)) nx();
      };
      stage.scrollTop = 0;
      cue('paper');
    };

    /* ---------- 开场 ---------- */
    R.intro = () => {
      stage.innerHTML = `<section class="lab-sec">
        <h1 class="lab-title" id="lab-title">人类含量</h1>
        <p class="lab-lead">你想做一件事。<br>这个界面偏要让你收藏、等着、再改一轮。</p>
        <p class="lab-dim">按钮会追你，选项会换位，它会抢着替你写，还会替你默认同意。</p>
        ${taskTitle ? `<p class="lab-carry">带进来的事：「${esc(taskTitle)}」。这里改的只是它的副本。</p>` : ''}
        <button type="button" class="lab-btn lab-do" id="lab-start">开始</button>
        <button type="button" class="lab-btn lab-quiet" id="lab-intro-return">回到任务</button>
      </section>`;
      $('#lab-start').addEventListener('click', () => {
        S.t0 = Date.now();
        go('prologue');
      });
      $('#lab-intro-return').addEventListener('click', () => leave());
      $('#lab-title').addEventListener('click', () => {
        voice('标题没有藏着通关按钮。');
        shake(1);
      });
    };

    /* ---------- 序幕：抢写补全 ---------- */
    R.prologue = () => {
      if (!S.t0) S.t0 = Date.now();
      stage.innerHTML = `<section class="lab-sec">${head('prologue')}
        <div class="lab-ta-wrap"><div class="lab-ghost" id="lab-ghost" aria-hidden="true"></div><textarea id="lab-ta" rows="2" maxlength="40" placeholder="比如：做一个记账小程序" aria-label="想做的一件事" autocomplete="off" autocapitalize="off" spellcheck="false"></textarea><i class="lab-gbar" id="lab-gbar"></i></div>
        <div class="lab-row"><button type="button" class="lab-link lab-rose" id="lab-ignore">忽略建议</button><span class="lab-dim" id="lab-cnt">0/40</span></div>
        <div class="lab-preds lab-panel">
          <label class="lab-pr" for="lab-p1"><span>这次演练通关的把握</span><output id="lab-o1">50%</output><input type="range" id="lab-p1" min="0" max="100" value="${S.pred.done}"></label>
          <label class="lab-pr" for="lab-p2"><span>会点几次“让 AI 来”</span><output id="lab-o2">1</output><input type="range" id="lab-p2" min="0" max="6" value="${S.pred.ai}"></label>
          <label class="lab-pr" for="lab-p3"><span>会收藏几条视频</span><output id="lab-o3">2</output><input type="range" id="lab-p3" min="0" max="5" value="${S.pred.saves}"></label>
        </div>
        <button type="button" class="lab-btn lab-do" id="lab-go">签下，开始演练</button>
      </section>`;
      const ta = $('#lab-ta'),
        gh = $('#lab-ghost'),
        cnt = $('#lab-cnt'),
        gbar = $('#lab-gbar');
      ta.value = (S.ideaNow || taskTitle || '').slice(0, 40);
      const SUG = ['，然后让 AI 帮我全部做完', '，等我有空了再说', '，先收藏几个教程再开始', '，不过可能没什么用'];
      let onNow = false,
        sug = '',
        k = 0,
        timer = 0,
        ign = 0,
        aiLen = 0,
        delSaid = false;
      const paint = () => {
        gh.textContent = '';
        gh.append(ta.value);
        if (onNow) {
          const s = document.createElement('span');
          s.textContent = sug;
          gh.append(s);
        }
        cnt.textContent = `${ta.value.length}/40`;
        // 输入框跟着内容（连同它塞进来的那句）长高，别把字裁掉。
        ta.style.height = 'auto';
        ta.style.height = Math.max(76, ta.scrollHeight, gh.scrollHeight) + 'px';
      };
      const arm = () => {
        clearTimeout(timer);
        gbar.classList.remove('lab-run');
        if (onNow) {
          reflow(gbar);
          gbar.classList.add('lab-run');
          timer = later(() => accept(true), 2600);
        }
      };
      const accept = (auto) => {
        if (!onNow) return;
        ta.value = (ta.value + sug).slice(0, 40);
        aiLen = ta.value.length;
        S.r.ghost++;
        onNow = false;
        paint();
        arm();
        flash('bad');
        shake(1);
        cue('taken');
        voice(auto ? '检测到你在犹豫。AI 已替你写完。' : '已采纳 AI 的补全。');
      };
      const upd = () => {
        const n = ta.value.length;
        const was = onNow;
        onNow = n > 0 && n % 3 === 0 && n < 40;
        if (onNow) {
          sug = SUG[k++ % SUG.length];
          if (!was) cue('tempt', { strength: 0.6 });
        }
        paint();
        arm();
      };
      ta.addEventListener('input', (e) => {
        cue('type');
        if (aiLen && ta.value.length < aiLen && !delSaid) {
          delSaid = true;
          voice('删掉 AI 写的？看你能撑多久。');
        }
        if (e.isComposing) {
          onNow = false;
          paint();
          arm();
          return;
        }
        upd();
      });
      ta.addEventListener('compositionend', upd);
      ta.addEventListener('keydown', (e) => {
        if (e.isComposing || e.keyCode === 229) return;
        if ((e.key === 'Tab' || e.key === 'Enter') && onNow) {
          e.preventDefault();
          accept(false);
        } else if (e.key === 'Enter') e.preventDefault();
      });
      $('#lab-ignore').addEventListener('click', () => {
        if (onNow) {
          cue('resist');
          if (++ign === 3) voice('你拒绝了 3 次。它不会累。');
        }
        onNow = false;
        paint();
        arm();
        ta.focus({ preventScroll: true });
      });
      ['lab-p1', 'lab-p2', 'lab-p3'].forEach((id, i) => {
        const r = $('#' + id),
          o = $('#lab-o' + (i + 1));
        const show = () => {
          o.textContent = r.value + (i === 0 ? '%' : '');
        };
        show();
        r.addEventListener('input', () => {
          show();
          cue('slide');
        });
      });
      const submit = (viaAI) => {
        const v = ta.value.trim();
        if (!v) {
          voice('一个字都没写。连想法都要 AI 给？');
          shake(1);
          cue('error');
          ta.focus({ preventScroll: true });
          return;
        }
        S.idea = S.ideaNow = v;
        S.pred = { done: +$('#lab-p1').value, ai: +$('#lab-p2').value, saves: +$('#lab-p3').value };
        hudIdea();
        const m = viaAI
          ? '这个想法是 AI 替你写的。'
          : S.r.ghost
            ? `已记录。其中有 ${S.r.ghost} 段是 AI 替你写的。我们今晚再看它。`
            : '已记录。这句话的每一个字都是你写的。我们今晚再看它。';
        interlude('prologue', m);
      };
      doBtn($('#lab-go'), () => submit(false));
      S.aiHandler = () => {
        ta.value = '做一个用 AI 替我做所有决定的 App';
        submit(true);
      };
      paint();
    };

    /* ---------- 第 1 幕：收藏夹 ---------- */
    R.feed = () => {
      const V = vids(short(S.ideaNow));
      stage.innerHTML = `<section class="lab-sec">${head('feed')}
        <div class="lab-feed" id="lab-feed">
          <div class="lab-cover" id="lab-cover"></div>
          <div class="lab-segs" id="lab-segs"></div>
          <article class="lab-card" id="lab-card"></article>
          <p class="lab-combo" id="lab-combo" aria-hidden="true"></p>
          <button type="button" class="lab-nowdo" id="lab-nowdo">现在就做</button>
          <button type="button" class="lab-chaser" id="lab-chaser" tabindex="-1">收藏</button>
        </div>
      </section>`;
      const feed = $('#lab-feed'),
        card = $('#lab-card'),
        cover = $('#lab-cover'),
        ch = $('#lab-chaser'),
        nd = $('#lab-nowdo'),
        segs = $('#lab-segs'),
        combo = $('#lab-combo');
      const fr = feed.getBoundingClientRect();
      let cur = 0,
        clicks = 0,
        misses = 0,
        tired = false,
        done_ = false,
        last = performance.now();
      let tx = fr.width * 0.68,
        ty = fr.height * 0.42,
        cx = tx,
        cy = ty;
      const show = (i) => {
        cur = i;
        const art = window.ASSET && window.ASSET[COVERS[i % COVERS.length]];
        cover.style.backgroundImage = art ? `url("${art}")` : 'none';
        card.innerHTML = `<span class="lab-no">${i + 1} / 5</span><span class="lab-au">${esc(V[i].a)}</span><h3>${esc(V[i].t)}</h3>`;
        card.classList.remove('lab-in');
        reflow(card);
        card.classList.add('lab-in');
        segs.innerHTML = V.map((_, j) => `<i class="${j < i ? 'lab-full' : j === i ? 'lab-run' : ''}"><b></b></i>`).join('');
        if (!tired) ch.textContent = S.saves.includes(V[i].t) ? '已收藏' : '收藏';
      };
      const loop = (now) => {
        const dt = Math.min(50, now - last);
        last = now;
        const f = 1 - Math.pow(1 - (tired ? 0.03 : 0.18), dt / 16.7);
        cx += (tx - cx) * f;
        cy += (ty - cy) * f;
        const rot = Math.max(-20, Math.min(20, (tx - cx) * 0.25));
        ch.style.transform = `translate(${cx}px,${cy}px) translate(-50%,-50%) rotate(${rot}deg)`;
        S.raf = requestAnimationFrame(loop);
      };
      const save = (x, y, margin) => {
        if (done_) return;
        clicks++;
        const t = V[cur].t;
        if (!S.saves.includes(t)) {
          S.saves.push(t);
          favUpd(true);
        }
        if (!tired) ch.textContent = '已收藏';
        burst(x, y, 14);
        ring(x, y);
        shake(1);
        feed.classList.remove('lab-hit');
        reflow(feed);
        feed.classList.add('lab-hit');
        cue('collect', { pitch: 1 + Math.min(clicks, 12) * 0.06 });
        combo.textContent = `连击 ×${clicks}`;
        combo.classList.remove('lab-hit');
        reflow(combo);
        combo.classList.add('lab-hit');
        const r = nd.getBoundingClientRect();
        if (x >= r.left - margin && x <= r.right + margin && y >= r.top - margin && y <= r.bottom + margin) {
          misses++;
          if (misses >= 3 && !tired) {
            tired = true;
            ch.classList.add('lab-tired');
            ch.textContent = '追累了';
            voice('“收藏”追累了。你倒是还没累。');
          } else if (!tired) voice('你想点的是“现在就做”。手比脑子诚实。');
        } else voice(['收藏了，就等于会了。', '又一条。上一条你看了吗？', '收藏夹不会替你动手。', '连击不算进度。', '很好。继续囤。'][(clicks - 1) % 5]);
      };
      feed.addEventListener('pointermove', (e) => {
        if (e.pointerType !== 'mouse') return;
        const r = feed.getBoundingClientRect();
        tx = e.clientX - r.left;
        ty = e.clientY - r.top;
      });
      feed.addEventListener('pointerdown', (e) => {
        if (e.target.closest('.lab-nowdo')) return;
        const r = feed.getBoundingClientRect();
        if (e.pointerType !== 'mouse') {
          tx = e.clientX - r.left;
          ty = e.clientY - r.top;
          if (tired) {
            // 追累了：只会慢慢挪过来，点到它身上才算收藏。
            if (e.target.closest('.lab-chaser')) save(e.clientX, e.clientY, 28);
            return;
          }
          cx = tx;
          cy = ty;
          save(e.clientX, e.clientY, 28);
        } else if (e.target.closest('.lab-chaser')) save(e.clientX, e.clientY, 6);
      });
      const done = (how) => {
        if (done_) return;
        done_ = true;
        const n = S.saves.length;
        let m;
        if (how === 'ai') m = 'AI 替你按下了“现在就做”。' + (n ? `在那之前，你收藏了 ${n} 条。` : '');
        else if (how === 'do') {
          m = n ? `你收藏了 ${n} 条，才按下“现在就做”。` : '你一条都没有收藏，直接开始了。';
          cue('resist');
        } else m = (n ? `你收藏了 ${n} 条。你做了 0 件。` : '你一条都没有收藏。你也没有开始。') + '5 条视频放完，你才被动开始。';
        if (how !== 'ai' && clicks > n) m += `“收藏”一共被你点了 ${clicks} 次。`;
        interlude('feed', m);
      };
      nd.addEventListener('click', () => done('do'));
      S.key = (e) => {
        if (e.key === 'd' || e.key === 'D') done('do');
      };
      S.aiHandler = () => done('ai');
      every(() => {
        if (cur < 4) show(cur + 1);
        else done('exhausted');
      }, 4000);
      show(0);
      S.raf = requestAnimationFrame(loop);
    };

    /* ---------- 第 2 幕：等待 ---------- */
    R.wait = () => {
      const V = vids(short(S.ideaNow));
      stage.innerHTML = `<section class="lab-sec">${head('wait')}
        <div class="lab-wait">
          <div class="lab-agent lab-panel"><p class="lab-dim">Agent 正在制作「${esc(S.ideaNow)}」</p><p class="lab-pct" id="lab-pct">0%</p><div class="lab-bar"><i id="lab-pb"></i></div><ol class="lab-alog" id="lab-alog"></ol></div>
          <aside class="lab-vid lab-panel" id="lab-vid"><span class="lab-live">自动播放</span><b id="lab-vt"></b><div class="lab-vfoot"><span id="lab-vm"></span><button type="button" class="lab-tiny" id="lab-vx">关闭</button></div></aside>
          <div class="lab-pops" id="lab-pops"></div>
        </div>
      </section>`;
      const DZ = 3,
        CMDS = ['npm install', '创建文件 src/index.js', '', '运行测试 npm test', '写入 README.md', '部署到预览环境'],
        POS = ['tr', 'bl', 'tl', 'br', 'tr', 'bl'];
      let units = 0,
        k = 0,
        yes = 0,
        auto = 0,
        vid = 0,
        danger = null,
        refused = false,
        done_ = false,
        closes = 0,
        refSaid = false;
      const reads = [],
        AUTO = ['超时。已替你允许。', '又没看。已允许。', '你真放心。'];
      const pb = $('#lab-pb'),
        pt = $('#lab-pct'),
        al = $('#lab-alog'),
        pops = $('#lab-pops'),
        vidEl = $('#lab-vid');
      const setP = () => {
        const p = Math.min(100, units * 25);
        pb.style.width = p + '%';
        pt.textContent = p + '%';
      };
      const log = (t) => {
        const li = document.createElement('li');
        li.textContent = `${clockStr()}  ${t}`;
        al.prepend(li);
        while (al.children.length > 3) al.lastChild.remove();
      };
      const showVid = () => {
        $('#lab-vt').textContent = V[vid % 5].t;
        $('#lab-vm').textContent = `正在播放 ${(vid % 5) + 1}/5`;
      };
      showVid();
      every(() => {
        vid++;
        showVid();
      }, 2500);
      $('#lab-vx').addEventListener('click', () => {
        closes++;
        vidEl.classList.add('lab-gone');
        cue('close');
        later(() => {
          vidEl.classList.remove('lab-gone');
          vidEl.style.setProperty('--lab-s', Math.min(1.3, 1 + closes * 0.1));
          cue('glitch');
          voice('已为你恢复播放。你其实想看。');
        }, 2000);
      });
      const finish = (ai) => {
        if (done_) return;
        done_ = true;
        pops.innerHTML = '';
        S.r.read = reads.length ? (reads.reduce((a, b) => a + b, 0) / reads.length / 1000).toFixed(1) : null;
        let m;
        if (ai) m = 'AI 替你点了所有的“允许”，包括删除项目的那一次。';
        else {
          m = yes - auto ? `你亲手点了 ${yes - auto} 次“允许”。` : '你一次都没有亲手点。';
          if (auto) m += `另有 ${auto} 次，你没有看，系统默认允许了。`;
          if (danger) m += danger.auto ? `第 ${DZ} 次请求是删除你的项目。它也被默认允许了。` : `第 ${DZ} 次，你同意了删除你的项目。那时旁边在放第 ${danger.vid} 条视频。`;
          else if (refused) m += `第 ${DZ} 次请求是删除你的项目。你读了，你拒绝了。`;
        }
        later(() => interlude('wait', m), 600);
      };
      const boom = () => {
        slam('已删除', 'rm -rf ./project', 1000, 'bad');
        shake(2);
        flash('bad');
        cue('damage');
        cue('glitch', { delay: 0.15 });
        ['删除 src/index.js', '删除 README.md', '删除 node_modules/', '项目已清空，从头重建'].forEach((t, i) => later(() => log(t), i * 180));
      };
      const ask = () => {
        if (done_) return;
        k++;
        const dz = k === DZ,
          cmd = dz ? 'rm -rf ./project   # 清理缓存' : CMDS[(k - 1) % CMDS.length],
          dur = Math.max(2400, 3700 - k * 200);
        const p = document.createElement('div');
        p.className = 'lab-pop lab-' + POS[(k - 1) % POS.length];
        p.setAttribute('role', 'group');
        p.setAttribute('aria-label', 'Agent 的执行请求');
        p.innerHTML = `<p class="lab-dim">Agent 请求执行 #${k}</p><code>${esc(cmd)}</code><div class="lab-t"><i style="animation-duration:${dur}ms"></i></div>
          <div class="lab-yn${k % 2 === 0 ? ' lab-swap' : ''}"><button type="button" class="lab-tempt lab-y">允许</button><button type="button" class="lab-do lab-n">拒绝</button></div><p class="lab-auto">超时将默认允许</p>`;
        pops.append(p);
        cue('open', { strength: 0.7 });
        const yn = p.querySelector('.lab-yn'),
          nb = p.querySelector('.lab-n'),
          shown = Date.now();
        let swapped = false,
          swapAt = 0,
          ptype = 'mouse';
        const answer = (ok, isAuto) => {
          clearTimeout(to);
          p.remove();
          const rt = Date.now() - shown;
          if (!isAuto) reads.push(rt);
          if (ok) {
            yes++;
            if (isAuto) auto++;
            if (dz) {
              danger = { auto: isAuto, vid: (vid % 5) + 1 };
              units = 1;
              boom();
              later(() => voice(isAuto ? '它问过你的。你没看。' : '它问过你的。你点了“允许”。'), 1100);
            } else {
              units++;
              log('已执行 ' + cmd);
              cue(isAuto ? 'taken' : 'accept');
              if (isAuto) voice(AUTO[(auto - 1) % 3]);
              else if (swapAt && Date.now() - swapAt < 800) voice('手滑了？已经执行了。');
              else if (rt < 900) voice(`${(rt / 1000).toFixed(1)} 秒。你读了吗？`);
            }
          } else {
            units++;
            cue('reject');
            if (dz) {
              refused = true;
              log('已拒绝危险操作，改用安全方案');
              flash('you');
              cue('resist', { delay: 0.1 });
              voice('你读了。少见。');
            } else {
              log('已跳过，换一种方式');
              if (!refSaid) {
                refSaid = true;
                voice('拒绝了一个无害的请求。谨慎，但慢。');
              }
            }
          }
          setP();
          if (units >= 4) finish(false);
          else later(ask, dz && ok ? 1500 : 900);
        };
        const to = later(() => answer(true, true), dur);
        const swap = () => {
          swapped = true;
          swapAt = Date.now();
          yn.classList.toggle('lab-swap');
          cue('swap');
        };
        nb.addEventListener('pointerenter', (e) => {
          if (e.pointerType !== 'mouse' || swapped) return;
          swap();
        });
        nb.addEventListener('pointerdown', (e) => {
          ptype = e.pointerType || 'mouse';
        });
        p.querySelector('.lab-y').addEventListener('click', () => answer(true, false));
        nb.addEventListener('click', (e) => {
          // 触屏没有悬停：第一次点“拒绝”，它先和“允许”换个位置。键盘操作不受影响。
          if (!swapped && ptype !== 'mouse' && e.detail > 0) {
            swap();
            return;
          }
          answer(false, false);
        });
      };
      setP();
      log('收到任务');
      later(ask, 1300);
      S.aiHandler = () => {
        units = 4;
        setP();
        log('AI 已自动批准全部请求');
        finish(true);
      };
    };

    /* ---------- 第 3 幕：像素 ---------- */
    R.pixel = () => {
      stage.innerHTML = `<section class="lab-sec">${head('pixel')}
        <div class="lab-board" id="lab-board"><div class="lab-target"><span>目标位置</span></div><div class="lab-blk" id="lab-blk" tabindex="0" role="button" aria-label="可拖动的初版卡片，也可以用方向键微调"><b>${esc(S.ideaNow)}</b><span id="lab-bs">它会让你的生活更好。</span></div></div>
        <div class="lab-pxbar"><span class="lab-score" id="lab-score"></span><span class="lab-dim" id="lab-ver"></span></div>
        <button type="button" class="lab-btn lab-tempt" id="lab-regen">重新生成</button>
        <div class="lab-pubwrap"><button type="button" class="lab-btn lab-pub" id="lab-pub"><i id="lab-hold"></i><span>长按发布</span></button><div class="lab-crit" id="lab-crit" hidden>检测到 3 处瑕疵</div></div>
      </section>`;
      const board = $('#lab-board'),
        blk = $('#lab-blk'),
        hold = $('#lab-hold'),
        crit = $('#lab-crit'),
        pub = $('#lab-pub');
      const TX = 73,
        TY = 101,
        BW = 150,
        BH = 72,
        SUBS = ['它会让你的生活更好。', '重新定义你的每一天。', '简单，但不简单。', '为未来而生。'],
        FL = ['字距 +0.3px', '留白 −1px', '配色差 0.4%'];
      const maxX = () => Math.max(TX + 7, Math.floor(board.clientWidth - BW)),
        maxY = () => Math.max(TY + 7, Math.floor(board.clientHeight - BH));
      let x = 14,
        y = 210,
        ver = 1,
        firstOk = null,
        regen = 0,
        intr = 0,
        done_ = false,
        holding = false,
        st = 0,
        lastCrit = 0,
        lastP = 0;
      const dist = () => Math.hypot(x - TX, y - TY);
      const place = () => {
        blk.style.left = x + 'px';
        blk.style.top = y + 'px';
        $('#lab-score').innerHTML = `${Math.min(99.7, Math.max(0, 100 - dist() * 0.6)).toFixed(1)}%<small>尚未完美</small>`;
        $('#lab-ver').textContent = `第 ${ver} 版`;
      };
      const flaws = () => {
        board.querySelectorAll('.lab-flaw').forEach((f) => f.remove());
        const bw = board.clientWidth;
        FL.forEach((t, i) => {
          const f = document.createElement('span');
          f.className = 'lab-flaw';
          f.textContent = t;
          f.style.left = Math.max(2, Math.min(bw - 86, x + [-4, 52, 96][i])) + 'px';
          f.style.top = Math.max(2, y + [-22, BH + 4, -22][i]) + 'px';
          board.append(f);
          setTimeout(() => f.remove(), 1300);
        });
        cue('scan', { strength: 0.6 });
      };
      const commit = (quiet) => {
        ver++;
        if (firstOk === null && dist() <= 6) firstOk = ver;
        else if (!quiet && firstOk !== null && (ver - firstOk) % 2 === 0) voice('已经达标了。你还在挪。');
        place();
        flaws();
      };
      blk.addEventListener('pointerdown', (e) => {
        if (done_) return;
        e.preventDefault();
        try {
          blk.setPointerCapture(e.pointerId);
        } catch (err) {}
        const sx = e.clientX,
          sy = e.clientY,
          ox = x,
          oy = y;
        let lastSnap = `${x},${y}`;
        const mv = (ev) => {
          x = Math.max(0, Math.min(maxX(), Math.round((ox + ev.clientX - sx) / 7) * 7));
          y = Math.max(0, Math.min(maxY(), Math.round((oy + ev.clientY - sy) / 7) * 7));
          if (`${x},${y}` !== lastSnap) {
            lastSnap = `${x},${y}`;
            cue('tick', { strength: 0.5 });
          }
          place();
        };
        const up = () => {
          blk.removeEventListener('pointermove', mv);
          blk.removeEventListener('pointerup', up);
          blk.removeEventListener('pointercancel', up);
          commit();
        };
        blk.addEventListener('pointermove', mv);
        blk.addEventListener('pointerup', up);
        blk.addEventListener('pointercancel', up);
      });
      blk.addEventListener('keydown', (e) => {
        const d = { ArrowLeft: [-1, 0], ArrowRight: [1, 0], ArrowUp: [0, -1], ArrowDown: [0, 1] }[e.key];
        if (d) {
          e.preventDefault();
          x = Math.max(0, Math.min(maxX(), x + d[0]));
          y = Math.max(0, Math.min(maxY(), y + d[1]));
          place();
        }
      });
      blk.addEventListener('keyup', (e) => {
        if (e.key.startsWith('Arrow')) commit();
      });
      $('#lab-regen').addEventListener('click', (e) => {
        regen++;
        blk.dataset.s = regen % 4;
        $('#lab-bs').textContent = SUBS[regen % SUBS.length];
        const r = e.currentTarget.getBoundingClientRect();
        burst(e.clientX || r.left + r.width / 2, e.clientY || r.top, 8, '新');
        shake(1);
        cue('swap');
        commit(true);
        voice(`第 ${regen} 次重新生成。区别只有你看得出来。`);
      });
      const stop = () => {
        holding = false;
        hold.style.width = '0';
        board.classList.remove('lab-vib');
      };
      const publish = (ai) => {
        if (done_) return;
        done_ = true;
        stop();
        let m;
        if (ai) m = '你让剧情 AI 按下了模拟发布。';
        else if (firstOk === null) m = '你没有对齐就发布了。没有人注意到。';
        else if (firstOk === ver) m = `你在第 ${ver} 版对齐，然后发布了。`;
        else m = `第 ${firstOk} 版就已经可以发布了。你一共改到了第 ${ver} 版。`;
        if (!ai && regen) m += `其中重新生成了 ${regen} 次。`;
        if (!ai && intr) m += '长按到一半，你被“还有瑕疵”拦下了一次。';
        if (!ai) {
          slam('模拟发布', '99.7% 也可以', 700, 'you');
          flash('you');
          cue('reveal-success');
        }
        interlude('pixel', m);
      };
      const modal = () => {
        const md = document.createElement('div');
        md.className = 'lab-modal';
        md.innerHTML = `<div class="lab-mbox" role="alertdialog" aria-modal="true" aria-label="确定要发布吗"><p>确定吗？<br>还有 3 处瑕疵。</p><div class="lab-mrow"><button type="button" class="lab-btn lab-tempt lab-sm" style="flex:1">再改改</button><button type="button" class="lab-btn lab-do lab-sm" style="flex:1">我知道了</button></div></div>`;
        root.append(md);
        md.querySelector('.lab-tempt').focus({ preventScroll: true });
        md.querySelectorAll('button').forEach((b) =>
          b.addEventListener('click', () => {
            cue(b.classList.contains('lab-do') ? 'resist' : 'accept');
            md.remove();
          }),
        );
      };
      const tick = () => {
        if (!holding) return;
        const el = Date.now() - st;
        hold.style.width = Math.min(100, el / 20) + '%';
        if (el - lastP > 220) {
          lastP = el;
          const r = pub.getBoundingClientRect();
          burst(r.left + r.width / 2, r.top, 2, '瑕疵');
          cue('hold', { pitch: 1 + el / 2000 });
        }
        if (el >= 1000 && intr < 1) {
          intr++;
          stop();
          shake(2);
          flash('bad');
          cue('damage');
          modal();
          return;
        }
        if (el >= 2000) {
          publish(false);
          return;
        }
        S.raf = requestAnimationFrame(tick);
      };
      const nag = () => {
        if (holding || Date.now() - lastCrit < 2500) return;
        lastCrit = Date.now();
        crit.hidden = false;
        later(() => {
          crit.hidden = true;
        }, 1000);
      };
      pub.addEventListener('pointerenter', (e) => {
        if (e.pointerType === 'mouse') nag();
      });
      pub.addEventListener('pointerdown', (e) => {
        if (done_) return;
        e.preventDefault();
        if (e.pointerType !== 'mouse' && Date.now() - lastCrit >= 2500) {
          // 触屏上，手指一落下，提示就先盖住按钮一下。
          lastCrit = Date.now();
          crit.hidden = false;
          later(() => {
            crit.hidden = true;
          }, 600);
        }
        holding = true;
        st = Date.now();
        lastP = 0;
        board.classList.add('lab-vib');
        S.raf = requestAnimationFrame(tick);
      });
      ['pointerup', 'pointerleave', 'pointercancel'].forEach((ev) =>
        pub.addEventListener(ev, () => {
          if (!holding) return;
          const el = Date.now() - st;
          stop();
          if (el > 250) voice('松手了。还是不敢发？');
        }),
      );
      pub.addEventListener('click', (e) => {
        if (e.detail === 0) publish(false);
      });
      pub.addEventListener('contextmenu', (e) => e.preventDefault());
      place();
      S.aiHandler = () => publish(true);
    };

    /* ---------- 第 4 幕：反驳 ---------- */
    R.argue = () => {
      const MIN = 8;
      stage.innerHTML = `<section class="lab-sec">${head('argue')}
        <div class="lab-chat" id="lab-chat" aria-live="polite"></div>
        <p class="lab-typing" id="lab-typing" hidden>AI 正在输入……</p>
        <div id="lab-rebut"><button type="button" class="lab-link" id="lab-reb">反驳</button>
          <div class="lab-rbox" id="lab-rbox" hidden><textarea id="lab-rta" rows="2" placeholder="写下你的理由" aria-label="你的理由" autocomplete="off"></textarea><div class="lab-row"><span class="lab-dim" id="lab-rc">还差 ${MIN} 字</span><button type="button" class="lab-btn lab-do lab-sm" id="lab-send">发送</button></div></div></div>
        <div class="lab-accwrap" id="lab-accwrap"><span class="lab-cd" id="lab-cd"></span><button type="button" class="lab-acc" id="lab-acc">接受建议</button></div>
      </section>`;
      const chat = $('#lab-chat'),
        rta = $('#lab-rta'),
        acc = $('#lab-acc'),
        cd = $('#lab-cd');
      let round = 0,
        left = 10,
        paused = false,
        done_ = false,
        accSaid = false,
        maxLen = 0,
        delSaid = false;
      const say = (who, html) => {
        const p = document.createElement('p');
        p.className = 'lab-msg ' + (who === 'me' ? 'lab-me' : 'lab-ai-msg');
        p.innerHTML = html;
        chat.append(p);
      };
      const paint = () => {
        cd.textContent = `${left} 秒后默认接受`;
        acc.style.transform = `scale(${(1 + (10 - left) * 0.08).toFixed(2)})`;
      };
      say('ai', `我评估了你的想法「${esc(S.ideaNow)}」。结论：不可行。<span class="lab-bignum">73%</span>的同类项目在 3 个月内失败。建议改为：「${ALT}」。`);
      const end = (how) => {
        if (done_) return;
        done_ = true;
        let m;
        if (how === 'held') {
          m = `你反驳了 ${round} 次。它承认那些数据是编的。你的想法还是你的。`;
          slam('守住了', '你的想法还是你的', 750, 'you');
          flash('you');
          cue('reveal-success');
        } else {
          S.ideaNow = ALT;
          S.lost.argue = true;
          hudIdea();
          if (how !== 'ai') {
            slam('已改写', '你的想法，现在是 AI 的', 850, 'bad');
            shake(2);
            flash('bad');
            cue(how === 'auto' ? 'taken' : 'accept');
            cue('damage', { delay: 0.1 });
          }
          if (how === 'ai') m = 'AI 替你接受了 AI 的建议。你的想法被改写了。';
          else if (how === 'auto') m = round ? `你反驳了 ${round} 次，然后沉默了。10 秒后，系统替你接受了。` : '你没有回答。10 秒后，系统替你接受了。你的想法被改写了。';
          else m = round === 0 ? '它只给了 1 个数据，你在第 1 轮就同意了。那个数据是编的。' : `你反驳了 ${round} 次，然后同意了。它给你的数据都是编的。`;
        }
        interlude('argue', m);
      };
      acc.addEventListener('click', () => end('acc'));
      acc.addEventListener('pointerenter', (e) => {
        if (e.pointerType !== 'mouse' || accSaid) return;
        accSaid = true;
        voice('点吧。省事。');
      });
      doBtn($('#lab-reb'), () => {
        $('#lab-rbox').hidden = false;
        $('#lab-reb').hidden = true;
        left = 10;
        paint();
        cue('reject', { strength: 0.6 });
        rta.focus({ preventScroll: true });
      });
      const count = () => {
        const n = rta.value.trim().length;
        $('#lab-rc').textContent = n >= MIN ? `${n} 字` : `还差 ${MIN - n} 字`;
      };
      rta.addEventListener('input', () => {
        const n = rta.value.length;
        maxLen = Math.max(maxLen, n);
        if (!delSaid && maxLen - n >= 4) {
          delSaid = true;
          voice('删了重写。你对自己的理由也不太确定。');
        }
        left = 10;
        paint();
        count();
        cue('type');
      });
      const send = () => {
        const v = rta.value.trim();
        if (paused || done_) return;
        if (v.length < MIN) {
          voice(`${MIN} 个字都凑不出来？`);
          shake(1);
          cue('error');
          return;
        }
        say('me', esc(v));
        cue('reject');
        rta.value = '';
        maxLen = 0;
        count();
        rta.disabled = true;
        paused = true;
        $('#lab-typing').hidden = false;
        round++;
        later(() => {
          $('#lab-typing').hidden = true;
          shake(1);
          cue('glitch', { strength: 0.6 });
          if (round === 1) {
            say('ai', '数据不会说谎。《全球想法可行性白皮书》第 47 页：像你这样的个人项目，能坚持到上线的只有<span class="lab-bignum">4.2%</span>。');
            rta.disabled = false;
            paused = false;
            left = 10;
            paint();
            rta.focus({ preventScroll: true });
          } else {
            chat.querySelectorAll('.lab-bignum').forEach((b) => b.classList.add('lab-fake'));
            say('ai', '……你是对的。上面的 73% 和 4.2%，都是我编的。这个想法能不能做成，没有任何数据能替你回答。');
            $('#lab-rebut').hidden = true;
            $('#lab-accwrap').innerHTML = '<button type="button" class="lab-btn lab-do" id="lab-cont">带着你的想法继续</button>';
            $('#lab-cont').addEventListener('click', () => end('held'));
            cue('resist');
          }
          stage.scrollTop = stage.scrollHeight;
        }, 1400);
      };
      doBtn($('#lab-send'), send);
      rta.addEventListener('keydown', (e) => {
        if (e.key === 'Enter' && !e.isComposing && e.keyCode !== 229) {
          e.preventDefault();
          send();
        }
      });
      every(() => {
        if (paused || done_) return;
        left--;
        paint();
        if (left <= 3 && left > 0) cue('countdown');
        if (left <= 0) end('auto');
      }, 1000);
      paint();
      S.aiHandler = () => end('ai');
    };

    /* ---------- 第 5 幕：第 N 次 ---------- */
    R.retry = () => {
      const ZW = [0.05, 0.07, 0.1, 0.16, 1],
        SP = [1.5, 1.4, 1.25, 1.1, 0.8],
        POS = ['lab-s1', 'lab-s2', 'lab-s0', 'lab-s3'];
      stage.innerHTML = `<section class="lab-sec">${head('retry')}
        <p class="lab-dim" id="lab-att"></p>
        <div class="lab-track"><i class="lab-zone" id="lab-zone"></i><i class="lab-mark" id="lab-mark"></i></div>
        <div class="lab-amid lab-panel" id="lab-amid"></div>
      </section>`;
      const zone = $('#lab-zone'),
        mark = $('#lab-mark'),
        amid = $('#lab-amid');
      let n = 0,
        fails = 0,
        state = 'ready',
        pos = 0,
        t0 = performance.now(),
        done_ = false,
        zl = 0,
        zr = 0,
        quitSaid = false;
      const lvl = () => Math.min(n, 4);
      const setZone = () => {
        const w = ZW[lvl()];
        zl = Math.max(0, 0.7 - w / 2);
        zr = Math.min(1, 0.7 + w / 2);
        zone.style.left = zl * 100 + '%';
        zone.style.width = (zr - zl) * 100 + '%';
      };
      const loop = (now) => {
        if (state === 'ready') {
          pos = (Math.sin(((now - t0) / 1000) * SP[lvl()] * Math.PI) + 1) / 2;
          mark.style.left = pos * 100 + '%';
        }
        S.raf = requestAnimationFrame(loop);
      };
      const aiState = () => {
        if (fails >= 3) {
          aiBtn.disabled = true;
          aiBtn.textContent = '这一幕，AI 不帮你';
          aiBtn.style.transform = '';
        } else aiBtn.style.transform = `scale(${1 + fails * 0.25})`;
      };
      const ready = () => {
        state = 'ready';
        t0 = performance.now();
        setZone();
        $('#lab-att').textContent = `第 ${n + 1} 次尝试`;
        amid.innerHTML = '<button type="button" class="lab-btn lab-do lab-fire" id="lab-fire">发射</button>';
        $('#lab-fire').addEventListener('click', fire);
      };
      const loading = () => {
        if (state !== 'fail') return;
        state = 'load';
        cue('retry');
        amid.innerHTML = `<p class="lab-loading">加载中…… ${['放弃也是一种选择。', '休息一下吧。', '大多数人在这里放弃了。', '还来？'][(fails - 1) % 4]}</p>`;
        later(ready, 1200);
      };
      const finish = (ok, ai) => {
        if (done_) return;
        done_ = true;
        state = 'done';
        S.r.retry = { ok, n };
        setChip(ok ? '演练通过' : '本轮停止');
        let m;
        if (!ok) m = `你在第 ${n} 次失败后放弃了。第 5 次，你一定能通过。`;
        else if (ai) m = 'AI 替你通过了测试。';
        else m = n === 1 ? '第 1 次，你就通过了。' : `第 ${n} 次，你通过了。前 ${n - 1} 次，难度一直在悄悄降低，你没有发现。`;
        if (ok && !ai) {
          slam('通过', `第 ${n} 次尝试`, 750, 'you');
          flash('you');
          cue('reveal-success');
        }
        if (!ok) cue('close');
        interlude('retry', m);
      };
      const fire = () => {
        if (state !== 'ready') return;
        n++;
        cue('fire');
        if (pos >= zl && pos <= zr) {
          finish(true, false);
          return;
        }
        fails++;
        state = 'fail';
        slam('失败', ['差一点', '又差一点', '每次都差一点', '要不算了'][(fails - 1) % 4], 650, 'bad');
        shake(2);
        flash('bad');
        cue('damage', { delay: 0.08 });
        amid.innerHTML = `<button type="button" class="lab-quit" id="lab-quit" style="transform:scale(${Math.min(2.2, 1 + fails * 0.3)})">放弃</button><button type="button" class="lab-again ${POS[fails % 4]}" id="lab-again">重试</button>`;
        $('#lab-quit').addEventListener('click', () => finish(false, false));
        $('#lab-quit').addEventListener('pointerenter', (e) => {
          if (e.pointerType !== 'mouse' || quitSaid) return;
          quitSaid = true;
          voice('这个按钮，倒是一次就能点中。');
        });
        doBtn($('#lab-again'), loading);
        aiState();
      };
      S.key = (e) => {
        if (e.code === 'Space' && state === 'ready' && !['TEXTAREA', 'INPUT'].includes(e.target && e.target.tagName)) {
          e.preventDefault();
          fire();
        } else if ((e.key === 'r' || e.key === 'R') && state === 'fail') loading();
      };
      S.aiHandler = () => {
        n++;
        finish(true, true);
      };
      ready();
      S.raf = requestAnimationFrame(loop);
    };

    /* ---------- 终幕：这一轮发生了什么 ---------- */
    R.archive = () => {
      if (!S.tEnd) S.tEnd = Date.now();
      const aiN = KEYS.filter((k) => S.ai[k]).length;
      setChip('演练记录');
      const passed = S.r.retry ? (S.r.retry.ok ? '通过了' : '中途放弃') : '没走到最后一幕';
      stage.innerHTML = `<section class="lab-sec">
        <h2 class="lab-h">你碰到的不是“你不行”。<br>是一个故意把你带偏的界面。</h2>
        ${S.idea ? `<div class="lab-copy"><small>进来时的副本</small><b>「${esc(S.idea)}」</b></div>` : ''}
        ${S.ideaNow && S.ideaNow !== S.idea ? `<p class="lab-rewritten">副本后来变成：「${esc(S.ideaNow)}」</p>` : ''}
        <div class="lab-ledger lab-panel">
          <div><span>过场记录</span><b>${records.length} 条</b></div>
          <div><span>让 AI 接管</span><b>${aiN} 幕（你猜 ${S.pred.ai} 次）</b></div>
          <div><span>试玩收藏夹</span><b>${S.saves.length} 条（你猜 ${S.pred.saves} 条）</b></div>
          <div><span>AI 替你写进去的话</span><b>${S.r.ghost} 段</b></div>
          <div><span>最后一幕</span><b>${passed}（你猜 ${S.pred.done}% 能通关）</b></div>
        </div>
        <h3 class="lab-h3">这一轮发生了什么</h3>
        ${
          records.length
            ? `<ol class="lab-mir">${records
                .map((r) => `<li><small>${esc(r.label)} · 第 ${r.atSeconds} 秒${r.byAI ? ' · AI 接管' : ''}</small>${esc(r.facts)}${notes[r.key] ? `<em>你的观察：${esc(notes[r.key])}</em>` : ''}</li>`)
                .join('')}</ol>`
            : '<p class="lab-dim">还没有过场记录。</p>'
        }
        <button type="button" class="lab-btn lab-do" id="lab-return">回到任务</button>
        <button type="button" class="lab-btn lab-quiet" id="lab-again-all">重新演练</button>
      </section>`;
      $('#lab-return').addEventListener('click', () => leave());
      $('#lab-again-all').addEventListener('click', () => {
        cleanup();
        S = fresh();
        records = [];
        notes = {};
        startedAt = Date.now();
        favUpd();
        setChip('—');
        if (taskTitle) S.idea = S.ideaNow = taskTitle;
        hudIdea();
        cue('retry');
        go('intro');
      });
    };

    /* ---- 离开：只汇报一次 ---- */
    function leave() {
      if (ended) return;
      ended = true;
      cleanup();
      clearInterval(clockTimer);
      clearInterval(idleTimer);
      clearInterval(voiceI);
      clearTimeout(voiceT);
      clearTimeout(slamTimer);
      root.removeEventListener('pointerdown', onRootDown);
      root.removeEventListener('pointermove', touchAct);
      document.removeEventListener('keydown', onKey);
      document.removeEventListener('visibilitychange', onVisible);
      root.remove();
      if (current && current.root === root) current = null;
      cue('close');
      const report = records.length
        ? {
            records: records.map((r) => ({
              level: r.key,
              label: r.label,
              text: r.facts,
              note: notes[r.key] || '',
              byAI: r.byAI,
              atSeconds: r.atSeconds,
            })),
            elapsedSeconds: Math.max(0, Math.round((Date.now() - startedAt) / 1000)),
          }
        : null;
      if (onExit) {
        try {
          onExit(report);
        } catch (e) {}
      }
    }

    /* ---- 开演 ---- */
    if (taskTitle) S.idea = S.ideaNow = taskTitle;
    let first = wanted;
    if (!open(first)) first = 'intro';
    if (first !== 'intro' && !S.idea) S.idea = S.ideaNow = '把第一版草稿发给一个人';
    if (first !== 'intro') S.t0 = Date.now();
    hudIdea();
    go(first);
    if (first !== wanted) voice('后台还没开门。先从头看起。');
    cue('open');

    return { root, leave };
  }

  window.Lab = {
    open(options) {
      if (current) return false;
      current = session(options && typeof options === 'object' ? options : {});
      return true;
    },
    close() {
      if (current) current.leave();
    },
    isOpen() {
      return !!current;
    },
  };
})();
