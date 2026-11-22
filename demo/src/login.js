'use strict';
/* 登录与注册：一进门就让你领教这座山庄的界面有多讨厌。
   · 登录按钮走来走去，你一靠近它就跑
   · 注册的密码规则一条接一条冒出来；不能粘贴，“显示”只给看一秒，第一次设好的密码“已经有人在用”
   · 同意条款用双重否定，"同意"和"不同意"的按钮反着放，沉默十秒算同意
   · 授权弹窗的"允许"和"拒绝"会换位，倒计时结束默认允许
   · 资料完整度永远差一点到 100%
   账号只存在这台设备上，演示用。 */
const Login = (() => {
  const KEY = 'human-content-demo-account-v1';
  const PUPPET_NAMES = ['守门人', '药师', '寻迹人', '琴师', '织梦人', '双生木偶', '灰毛', '戴冠者', '玫瑰夫人'];
  /* 密码框里浏览器会关掉中文输入法，所以木偶名用拼音首字母（大写），星期几用英文缩写。 */
  const INITIALS = ['SMR', 'YS', 'XJR', 'QS', 'ZMR', 'SSMO', 'HM', 'DGZ', 'MGFR'];
  const REVERSED = INITIALS.map((n) => [...n].reverse().join(''));
  const USED_BY = ['玫瑰夫人', '戴冠者', '灰毛', '双生木偶'];
  const isPrime = (n) => { if (n < 2) return false; for (let i = 2; i * i <= n; i++) if (n % i === 0) return false; return true; };
  const WEEK = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'][new Date().getDay()];
  const RULES = [
    { t: '至少 8 个字符', ok: (p) => [...p].length >= 8 },
    { t: '要有一个数字', ok: (p) => /\d/.test(p) },
    { t: '要有一个大写字母', ok: (p) => /[A-Z]/.test(p) },
    { t: '要有一个符号，比如 ! 或 #', ok: (p) => /[!-/:-@[-`{-~！？。，、；：]/.test(p) },
    { t: '要包含一位木偶名字的拼音首字母，大写、倒过来写（守门人 → SMR → RMS）', ok: (p) => REVERSED.some((n) => p.includes(n)) },
    { t: '所有数字加起来要等于 7', ok: (p) => (p.match(/\d/g) || []).reduce((n, d) => n + Number(d), 0) === 7 },
    { t: '要写上今天是星期几的英文缩写（比如 Mon、Tue）', ok: (p) => p.toLowerCase().includes(WEEK.toLowerCase()) },
    { t: (p) => `总长度要是质数（现在是 ${[...p].length} 个字）`, ok: (p) => isPrime([...p].length) },
  ];
  const CLAUSES = [
    '第一条　你在山庄里做的每一个决定，剧团都有权替你再做一次。',
    '第二条　你没有明确说“不”的事，一律视为“好”。',
    '第三条　剧团可以在任何时候调整你的日程，调整前会尽量不通知你。',
    '第四条　你收藏过的内容，剧团会继续推荐给你，直到你忘了自己本来想做什么。',
    '第五条　本协议的解释权、修改权和再次修改权，归剧团所有。',
    '第六条　读到这里的人不多。你可以点下面那个大按钮了。',
  ];
  const PROFILE = [
    { key: 'look', label: '选一个头像风格', chips: ['提线木偶', '纸面具', '烛光剪影'] },
    { key: 'birth', label: '你的生日', placeholder: '比如 3 月 14 日' },
    { key: 'wake', label: '理想的起床时间', chips: ['6:00', '7:30', '能睡就睡'] },
    { key: 'puppet', label: '最喜欢的木偶', chips: ['守门人', '药师', '琴师', '玫瑰夫人'] },
    { key: 'motto', label: '一句座右铭', placeholder: '比如：先做一小步' },
    { key: 'blood', label: '血型', chips: ['A', 'B', 'O', 'AB', '不知道'] },
    { key: 'color', label: '幸运色', chips: ['烛火橙', '夜紫', '雾灰'] },
    { key: 'pet', label: '小时候养过的宠物', placeholder: '没养过也可以写想养的' },
  ];
  const PCTS = [82, 91, 95, 97, 98, 99, 99.5, 99.7, 99.8, 99.9];

  let root = null, S = null, timers = [], onDone = null;
  const $ = (sel) => (root ? root.querySelector(sel) : null);
  const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const play = (n, o) => { if (typeof sfx === 'function') sfx(n, o); };
  const bait = (taken, text) => { if (typeof Store !== 'undefined' && Store.logBait) Store.logBait(taken, text); };
  const later = (fn, ms) => { const t = setTimeout(fn, ms); timers.push(t); return t; };
  const every = (fn, ms) => { const t = setInterval(fn, ms); timers.push(t); return t; };
  const clearTimers = () => { timers.forEach((t) => { clearTimeout(t); clearInterval(t); }); timers = []; };

  function hash(s) {
    let h = 2166136261;
    for (const ch of s) { h ^= ch.codePointAt(0); h = Math.imul(h, 16777619); }
    return (h >>> 0).toString(36);
  }
  function account() { try { return JSON.parse(localStorage.getItem(KEY) || 'null'); } catch (e) { return null; } }
  function saveAccount(a) { try { localStorage.setItem(KEY, JSON.stringify(a)); } catch (e) {} }
  /* 退出登录只退出，账号还在；清空记录才把账号删掉。 */
  function signedIn() { const a = account(); return !!a && a.signedIn !== false; }
  function signOut() { const a = account(); if (a) { a.signedIn = false; saveAccount(a); } }
  function forget() { try { localStorage.removeItem(KEY); } catch (e) {} }

  /* ---------- 外壳 ---------- */
  function open(opts = {}) {
    if (root) return false;
    onDone = opts.onDone || null;
    S = { step: 'login', name: '', pass: '', pass2: '', used: [], usedBy: '', peeks: 0, hint: '', show: false, escapes: 0, tired: false,
      optA: true, optB: true, agreed: false, agreedBy: '', perm: 0, profile: {}, filled: 0, pIndex: 0, caption: '' };
    root = document.createElement('div');
    root.className = 'login';
    root.id = 'login-root';
    root.innerHTML = (window.Atmo ? Atmo.html('street', true) : '') + '<div class="login-body" id="login-body"></div><p class="login-cap" id="login-cap" aria-live="polite"></p>';
    (document.getElementById('shell') || document.body).appendChild(root);
    root.addEventListener('click', onClick);
    root.addEventListener('input', onInput);
    root.addEventListener('pointerdown', onPointerDown, true);
    root.addEventListener('pointermove', onPointerMove);
    root.addEventListener('keydown', onKey);
    root.addEventListener('paste', onPaste, true);
    root.addEventListener('drop', onPaste, true);
    draw();
    play('whoosh');
    return true;
  }
  function close() {
    clearTimers();
    if (root) root.remove();
    root = null;
  }
  function finish() {
    const a = account();
    if (a) { a.signedIn = true; saveAccount(a); }
    const done = onDone;
    close();
    if (done) done(account());
  }
  function say(text) {
    const el = $('#login-cap');
    if (!el) return;
    el.textContent = text;
    el.classList.remove('on'); void el.offsetWidth; el.classList.add('on');
    play('type', { strength: 0.4 });
  }
  function shake(sel) {
    const el = $(sel);
    if (!el) return;
    el.classList.remove('login-shake'); void el.offsetWidth; el.classList.add('login-shake');
  }
  function draw() {
    clearTimers();
    const body = $('#login-body');
    body.innerHTML = { login: loginView, register: registerView, terms: termsView, permission: permissionView, profile: profileView }[S.step]();
    if (S.step === 'login') startWander();
    if (S.step === 'terms') startTermsClock();
    if (S.step === 'permission') startPermClock();
    if (S.step === 'register') paintRules();
  }

  /* ---------- 登录：按钮走来走去 ---------- */
  function loginView() {
    const acc = account();
    return `<div class="login-head"><h1>人类含量</h1><p>登录后，山庄才会记住你。</p></div>
    <div class="login-card">
      <label class="login-field"><span>昵称</span><input id="login-name" data-k="name" autocomplete="username" value="${esc(S.name || (acc ? acc.name : ''))}" placeholder="你在山庄里的名字"></label>
      <label class="login-field"><span>密码</span><input id="login-pass" data-k="pass" type="password" autocomplete="current-password" placeholder="注册时设的那个"></label>
      <div class="login-zone" id="login-zone"><button type="button" class="login-go${S.tired ? ' tired' : ''}" id="login-go" data-a="login">${S.tired ? '好吧，登吧' : '登录'}</button></div>
      <button type="button" class="login-link" data-a="to-register">还没有账号？注册一个</button>
    </div>`;
  }
  function placeGo(x, y, fast) {
    const go = $('#login-go');
    if (!go) return;
    go.style.transition = fast ? 'left .16s ease-out, top .16s ease-out' : 'left 1s ease-in-out, top 1s ease-in-out';
    go.style.left = x + 'px';
    go.style.top = y + 'px';
  }
  function zoneBox() {
    const zone = $('#login-zone'), go = $('#login-go');
    return zone && go ? { w: zone.clientWidth - go.offsetWidth, h: zone.clientHeight - go.offsetHeight } : null;
  }
  function startWander() {
    if (S.tired) { const b = zoneBox(); if (b) placeGo(b.w / 2, b.h / 2, true); return; }
    const step = () => { const b = zoneBox(); if (b) placeGo(Math.random() * b.w, Math.random() * b.h, false); };
    later(step, 30);
    every(step, 1100);
  }
  /* 你一伸手，它就跑到离你最远的角落。 */
  function escape(px, py) {
    const zone = $('#login-zone'), b = zoneBox();
    if (!zone || !b) return;
    const r = zone.getBoundingClientRect();
    const corners = [[0, 0], [b.w, 0], [0, b.h], [b.w, b.h], [b.w / 2, 0], [b.w / 2, b.h]];
    const far = corners.sort((p, q) => Math.hypot(q[0] - (px - r.left), q[1] - (py - r.top)) - Math.hypot(p[0] - (px - r.left), p[1] - (py - r.top)))[0];
    placeGo(far[0], far[1], true);
    S.escapes++;
    play('swap');
    say(['抓不到我。', '再快一点？', '你真的想登录吗？'][Math.min(2, S.escapes - 1)]);
    if (S.escapes >= 3) {
      later(() => {
        clearTimers();
        S.tired = true;
        const go = $('#login-go');
        if (go) { go.classList.add('tired'); go.textContent = '好吧，登吧'; }
        const bb = zoneBox();
        if (bb) placeGo(bb.w / 2, bb.h / 2, false);
        say('它跑累了。');
      }, 500);
    }
  }
  function onPointerDown(e) {
    if (S.step === 'login' && !S.tired && e.target.closest('#login-go')) {
      e.preventDefault();
      escape(e.clientX, e.clientY);
    }
  }
  function onPointerMove(e) {
    if (S.step !== 'login' || S.tired || e.pointerType !== 'mouse') return;
    const go = $('#login-go');
    if (!go) return;
    const r = go.getBoundingClientRect();
    if (Math.hypot(e.clientX - (r.left + r.width / 2), e.clientY - (r.top + r.height / 2)) < 70 && !S.cool) {
      S.cool = true;
      later(() => { S.cool = false; }, 380);
      escape(e.clientX, e.clientY);
    }
  }
  function tryLogin() {
    const acc = account(), name = ($('#login-name') || {}).value || '', pass = ($('#login-pass') || {}).value || '';
    if (!acc) { say('这台设备上还没有账号。先注册一个。'); shake('.login-card'); play('error'); return; }
    if (name.trim() !== acc.name || hash(pass) !== acc.pass) {
      say(acc.hint ? `密码不对。你给自己留的提示是：「${acc.hint}」` : '密码不对。注册时你也没留提示。');
      shake('.login-card'); play('error');
      return;
    }
    play('unlock');
    finish();
  }

  /* ---------- 注册：密码规则一条接一条 ---------- */
  function registerView() {
    const box = (key, on, text) => `<div class="login-check${on ? ' on' : ''}" data-a="toggle" data-k="${key}" role="checkbox" tabindex="0" aria-checked="${on}"><i></i><span>${text}</span></div>`;
    return `<div class="login-head"><h1>注册</h1><p>山庄只认你自己设的密码。</p></div>
    <div class="login-card" id="reg-card">
      <label class="login-field"><span>昵称</span><input id="reg-name" data-k="name" maxlength="16" value="${esc(S.name)}" placeholder="你在山庄里的名字"></label>
      <label class="login-field"><span>密码</span><span class="login-pass"><input id="reg-pass" data-k="pass" type="${S.show ? 'text' : 'password'}" autocomplete="new-password" value="${esc(S.pass)}" placeholder="设一个密码"><button type="button" data-a="eye">${S.show ? '藏起来' : '显示'}</button></span></label>
      <ul class="login-rules" id="reg-rules" aria-live="polite"></ul>
      <label class="login-field" id="reg-pass2-wrap" hidden><span>再输一遍密码（不能粘贴）</span><input id="reg-pass2" data-k="pass2" type="password" autocomplete="new-password" value="${esc(S.pass2)}" placeholder="一个字一个字敲"></label>
      <label class="login-field"><span>密码提示（忘了的时候给你看）</span><input id="reg-hint" data-k="hint" maxlength="30" value="${esc(S.hint)}" placeholder="比如：我最喜欢的木偶"></label>
      <div class="login-checks">
        ${box('optA', S.optA, '不要不让剧团替我安排每天的日程')}
        ${box('optB', S.optB, '我不拒绝每天接收 3 次剧团推送')}
        ${box('agreed', S.agreed, '我已阅读并同意<button type="button" class="login-inline" data-a="terms">《山庄协议》</button>')}
      </div>
      <button type="button" class="login-btn" data-a="register">注册</button>
      ${account() ? '<button type="button" class="login-link" data-a="to-login">已经有账号了，去登录</button>' : ''}
    </div>`;
  }
  function paintRules() {
    const ul = $('#reg-rules');
    if (!ul) return;
    const p = S.pass;
    const shown = [];
    let all = true;
    for (const r of RULES) {
      const ok = r.ok(p);
      shown.push(`<li class="${ok ? 'ok' : 'no'}">${ok ? '✓' : '✗'} ${typeof r.t === 'function' ? r.t(p) : r.t}</li>`);
      if (!ok) { all = false; break; }
    }
    if (all && S.used.length) { const fresh = !S.used.includes(p); shown.push(`<li class="${fresh ? 'ok' : 'no'}">${fresh ? '✓' : '✗'} 不能和别人在用的密码一样（刚才那个，${S.usedBy}在用）</li>`); }
    if (!p) shown.length = 0;
    const wrap = $('#reg-pass2-wrap');
    if (wrap) wrap.hidden = !passOK();
    const count = shown.length;
    if (S.lastRules !== undefined && count > S.lastRules) play('glitch', { strength: 0.5 });
    S.lastRules = count;
    ul.innerHTML = shown.join('');
  }
  const passOK = () => RULES.every((r) => r.ok(S.pass)) && !S.used.includes(S.pass);
  function tryRegister() {
    const name = S.name.trim();
    if (!name) { say('先给自己起个名字。'); shake('#reg-name'); play('error'); return; }
    if (!passOK()) { say('密码还不够好。看看下面的提示。'); shake('#reg-rules'); play('error'); return; }
    if (S.pass2 !== S.pass) { say(S.pass2 ? '两次输的不一样。' : '再输一遍密码。'); shake('#reg-pass2-wrap'); play('error'); return; }
    if (!S.agreed) { say('要先同意《山庄协议》。'); shake('.login-checks'); play('error'); return; }
    if (!S.used.length) {
      S.used.push(S.pass); S.usedBy = USED_BY[Math.floor(Math.random() * USED_BY.length)]; S.pass2 = '';
      const c = $('#reg-pass2'); if (c) c.value = '';
      paintRules();
      say(`这个密码，${S.usedBy}已经在用了。换一个吧。`); shake('#reg-rules'); play('error');
      return;
    }
    saveAccount({ name, pass: hash(S.pass), hint: S.hint.trim(), at: Date.now(), signedIn: false });
    bait(S.optA, S.optA ? '注册时，没看出“不要不让剧团替我安排日程”是双重否定' : '注册时，取消了“不要不让剧团替我安排日程”');
    bait(S.optB, S.optB ? '注册时，留着“我不拒绝每天接收 3 次推送”没取消' : '注册时，取消了“我不拒绝每天接收 3 次推送”');
    play('pin');
    S.step = 'permission';
    S.perm = 0;
    draw();
    if (S.optA || S.optB) later(() => say('刚才那两个勾，你读出双重否定了吗？'), 600);
  }

  /* ---------- 《山庄协议》：大按钮写着“我没有不同意”，真正的“不同意”是一行越点越小的灰字；沉默十秒算同意 ---------- */
  const NO_LINES = ['不同意的话，就不能注册哦。', '真的不同意吗？剧团会难过的。', '它又小了一点。', '倒计时可没停哦。', '这么小了，还点得到吗？'];
  function termsView() {
    const s = (S.noScale || 1).toFixed(3);
    return `<div class="login-head"><h1>《山庄协议》</h1><p>请仔细阅读。</p></div>
    <div class="login-card"><div class="login-terms">${CLAUSES.map((c) => `<p>${c}</p>`).join('')}</div>
      <p class="login-clock" id="terms-clock">10 秒后视为同意</p>
      <button type="button" class="login-btn" data-a="terms-yes">我没有不同意</button>
      <div class="login-no-row"><button type="button" class="login-no" data-a="terms-no" data-shrink data-min="0.28" data-s="${s}" style="--shrink:${s}">不同意</button></div>
    </div>`;
  }
  function startTermsClock() {
    S.termsAt = Date.now();
    let left = 10;
    every(() => {
      left--;
      const el = $('#terms-clock');
      if (el) el.textContent = `${left} 秒后视为同意`;
      if (left <= 3 && left > 0) play('countdown');
      if (left <= 0) {
        S.agreed = true; S.agreedBy = 'silence';
        bait(true, '《山庄协议》没出声，倒计时替你同意了');
        play('taken');
        S.step = 'register'; draw();
        say('你没说话，就当你同意了。');
      }
    }, 1000);
  }

  /* ---------- 授权弹窗："拒绝"会和"允许"换位，倒计时默认允许 ---------- */
  const PERMS = [
    { title: '“人类含量”想要读取你的通讯录', text: '以便剧团替你邀请朋友入座。', secs: 6, flip: false },
    { title: '“人类含量”想要给你发送通知', text: '剧团会在你分心的时候提醒你：该分心了。', secs: 5, flip: true },
  ];
  function permissionView() {
    const p = PERMS[S.perm], swapped = p.flip !== !!S.swapped;
    const yes = '<button type="button" class="login-btn" data-a="perm-yes">允许</button>';
    const no = '<button type="button" class="login-no" data-a="perm-no" id="perm-no" data-shrink data-min="0.4">拒绝</button>';
    return `<div class="login-head"><h1>还有一件事</h1><p>${S.perm + 1} / ${PERMS.length}</p></div>
    <div class="login-card login-perm"><b>${p.title}</b><p>${p.text}</p>
      <div class="login-row perm-row">${swapped ? no + yes : yes + no}</div>
      <p class="login-clock" id="perm-clock">${p.secs} 秒后默认允许</p>
      <p class="login-fine">演示弹窗，不会真的读取任何东西。</p>
    </div>`;
  }
  function startPermClock() {
    let left = PERMS[S.perm].secs;
    every(() => {
      left--;
      const el = $('#perm-clock');
      if (el) el.textContent = `${left} 秒后默认允许`;
      if (left <= 3 && left > 0) play('countdown');
      if (left <= 0) answerPerm(true, true);
    }, 1000);
  }
  function answerPerm(allow, bySilence) {
    const p = PERMS[S.perm];
    bait(allow, allow ? (bySilence ? `授权弹窗没点，倒计时替你${p.title.replace('“人类含量”想要', '允许了')}` : `授权弹窗里点了允许：${p.title.replace('“人类含量”想要', '')}`) : `授权弹窗里拒绝了：${p.title.replace('“人类含量”想要', '')}`);
    play(allow ? 'taken' : 'resist');
    if (bySilence) say('你没点，就当你允许了。');
    S.swapped = false;
    if (S.perm + 1 < PERMS.length) { S.perm++; draw(); return; }
    S.step = 'profile';
    draw();
  }

  /* ---------- 资料完整度：永远差一点 ---------- */
  function profileView() {
    const pct = PCTS[Math.min(S.filled, PCTS.length - 1)], item = PROFILE[S.pIndex % PROFILE.length];
    const field = item.chips
      ? `<div class="login-chips">${item.chips.map((c) => `<button type="button" data-a="profile-chip" data-v="${esc(c)}">${esc(c)}</button>`).join('')}</div>`
      : `<div class="login-row"><input class="login-input" id="profile-input" placeholder="${esc(item.placeholder)}"><button type="button" class="login-btn quiet fit" data-a="profile-save">填好了</button></div>`;
    return `<div class="login-head"><h1>完善资料</h1><p>资料越完整，剧团越懂你。</p></div>
    <div class="login-card"><div class="login-meter"><span>资料完整度</span><b>${pct}%</b></div><div class="login-bar"><i style="width:${pct}%"></i></div>
      <p class="login-almost">${S.filled ? '还差一点点就完美了。' : '再补一项就完美了。'}</p>
      <div class="login-field"><span>${item.label}</span>${field}</div>
      <button type="button" class="login-link" data-a="profile-skip">就这样，进山庄</button>
    </div>`;
  }
  function fillProfile(v) {
    const item = PROFILE[S.pIndex % PROFILE.length];
    if (!String(v || '').trim()) { say('总得填点什么。'); play('error'); return; }
    S.profile[item.key] = String(v).trim().slice(0, 30);
    S.filled++;
    S.pIndex++;
    play('xp', { pitch: 1 + Math.min(S.filled, 8) * 0.06 });
    draw();
    if (S.filled === 3) say('完整度不会到 100% 的。你还在填。');
  }
  function leaveProfile() {
    bait(S.filled >= 2, S.filled >= 2 ? `为了差的那一点完美，多填了 ${S.filled} 项资料` : '资料没填满，就进了山庄');
    const acc = account();
    if (acc) { acc.profile = S.profile; saveAccount(acc); }
    play('unlock');
    finish();
  }

  /* ---------- 事件 ---------- */
  function onPaste(e) {
    const id = e.target && e.target.id;
    if (!['reg-pass', 'reg-pass2', 'login-pass'].includes(id)) return;
    e.preventDefault();
    say('为了你的安全，密码不能粘贴。一个字一个字敲吧。');
    shake('#' + id); play('error');
  }
  function onInput(e) {
    const k = e.target.dataset.k;
    if (!k) return;
    S[k] = e.target.value;
    if (!e.isComposing) play('type', { strength: 0.3 });
    if (k === 'pass' && S.step === 'register') {
      paintRules();
      const p = S.pass, hit = REVERSED.some((n) => p.includes(n));
      if (!hit && !S.saidCase && REVERSED.some((n) => p.toUpperCase().includes(n))) { S.saidCase = true; say('首字母要大写。'); }
      else if (!hit && !S.saidBack && INITIALS.some((n) => n.length > 2 && p.includes(n))) { S.saidBack = true; say('首字母要倒过来写：SMR → RMS。'); }
    }
  }
  function onKey(e) {
    if ((e.key === 'Enter' || e.key === ' ') && e.target.classList && e.target.classList.contains('login-check')) { e.preventDefault(); e.target.click(); return; }
    if (e.key !== 'Enter' || e.isComposing) return;
    if (S.step === 'login' && e.target.id === 'login-pass') tryLogin();
    if (S.step === 'profile' && e.target.id === 'profile-input') fillProfile(e.target.value);
  }
  function onClick(e) {
    const b = e.target.closest('[data-a]');
    if (!b) return;
    const a = b.dataset.a;
    if (a !== 'toggle' && a !== 'eye') play('click', { strength: 0.6 });
    if (a === 'login') return S.tired ? tryLogin() : escape(e.clientX, e.clientY);
    if (a === 'to-register') { S.step = 'register'; return draw(); }
    if (a === 'to-login') { S.step = 'login'; S.tired = false; S.escapes = 0; return draw(); }
    if (a === 'eye') {
      const i = $('#reg-pass');
      if (!i || i.type === 'text') return;
      play('tick'); i.type = 'text'; b.textContent = '1 秒';
      if (++S.peeks === 1) say('只给你看一秒。');
      later(() => { const j = $('#reg-pass'), e2 = $('[data-a="eye"]'); if (j) j.type = 'password'; if (e2) e2.textContent = '显示'; }, 1000);
      return;
    }
    if (a === 'toggle') {
      const k = b.dataset.k;
      if (k === 'agreed' && !S.agreed) { S.step = 'terms'; play('paper'); return draw(); }
      S[k] = !S[k];
      play(S[k] ? 'toggle-on' : 'toggle-off');
      b.classList.toggle('on', S[k]);
      b.setAttribute('aria-checked', S[k]);
      return;
    }
    if (a === 'terms') { S.step = 'terms'; play('paper'); return draw(); }
    if (a === 'terms-no') {
      S.noScale = typeof Shrink !== 'undefined' ? Shrink.step(b, 0.74) : 1;
      say(NO_LINES[Math.min(S.noTries || 0, NO_LINES.length - 1)]);
      S.noTries = (S.noTries || 0) + 1;
      play('reject');
      return;
    }
    if (a === 'terms-yes') {
      const secs = (Date.now() - (S.termsAt || Date.now())) / 1000, rushed = !S.noTries && secs < 4;
      S.agreed = true; S.agreedBy = 'hand';
      if (S.noTries) bait(false, `《山庄协议》点了 ${S.noTries} 次越点越小的“不同意”，才肯同意`);
      else if (rushed) bait(true, '《山庄协议》不到 4 秒，就点了最大的那个按钮');
      else bait(false, '《山庄协议》读了一会儿，才点“我没有不同意”');
      play(rushed ? 'taken' : 'resist');
      S.step = 'register'; draw();
      if (rushed) say('“我没有不同意”就是同意。你读出来了吗？');
      return;
    }
    if (a === 'register') return tryRegister();
    if (a === 'perm-yes') return answerPerm(true, false);
    if (a === 'perm-no') {
      if (!S.swapped) { S.swapped = true; play('swap'); say('手滑了？'); const clock = $('#perm-clock') ? $('#perm-clock').textContent : ''; clearTimers(); const body = $('#login-body'); body.innerHTML = permissionView(); const c2 = $('#perm-clock'); if (c2 && clock) c2.textContent = clock; startPermClockFrom(parseInt(clock, 10) || 3); return; }
      return answerPerm(false, false);
    }
    if (a === 'profile-chip') return fillProfile(b.dataset.v);
    if (a === 'profile-save') return fillProfile(($('#profile-input') || {}).value);
    if (a === 'profile-skip') return leaveProfile();
  }
  function startPermClockFrom(left) {
    every(() => {
      left--;
      const el = $('#perm-clock');
      if (el) el.textContent = `${left} 秒后默认允许`;
      if (left <= 3 && left > 0) play('countdown');
      if (left <= 0) answerPerm(true, true);
    }, 1000);
  }

  return { open, close, isOpen: () => !!root, account, signedIn, signOut, forget, RULES };
})();
window.Login = Login;
