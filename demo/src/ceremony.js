'use strict';
/* 开幕式：队友版的入场动画和入座大厅，接在登录门的前后。
   1. 开幕：封面、"人类含量"四个字一个个浮出来、提线垂下、进度条点灯。界面使坏时，进度条冲到 99% 就卡住，越催越慢。
   2. 点"推门入座"。
   3. 入座大厅：一张烛光圆桌，九个木偶围坐，你坐在自己同行的那张牌上；"开始今夜"推门进山庄。 */
const Ceremony = (() => {
  const SEATS = ['guard', 'witch', 'villager', 'fool', 'grave', 'dream', 'wolf', 'wolfking', 'wolfbeauty'];
  const STEPS = ['点亮灯笼', '铺开石板路', '挂上提线', '摆好木偶', '翻开档案', '村庄醒了'];
  const STUCK = ['马上就好…', '就差一点点了。', '再等一下下。', '99% 也算快好了吧。', '网没问题，是你太急了。'];
  const NAGS = ['别催，越催越慢。', '你看，又退回去了。', '再催就从头来了。（骗你的）'];
  const q = (sel, root) => (root || document).querySelector(sel);
  const play = (n, o) => { if (typeof sfx === 'function') sfx(n, o); };
  const host = () => document.getElementById('shell') || document.body;
  const names = () => (window.FATE_DATA && FATE_DATA.puppets) || {};

  /* ---------- 1. 开幕 ---------- */
  function loader(done) {
    const hate = typeof Store !== 'undefined' && Store.mischief;
    const el = document.createElement('div');
    el.className = 'cer cer-loader';
    el.id = 'cer-loader';
    el.innerHTML = `<div class="cer-veil"></div>
      <div class="cer-cover"><div class="cer-glow"></div><div class="cer-img art-cover"></div><div class="cer-lines"></div></div>
      <div class="cer-title"><div class="cer-kicker">提线木偶 · 夜巡山庄</div><h1><span>人</span><span>类</span><span>含</span><span>量</span></h1><p>你今晚打算，交付出多少自己？</p></div>
      <div class="cer-progress"><div class="cer-bar"><i id="cer-fill"></i></div><div class="cer-pct"><span id="cer-pct">0</span>% · <span id="cer-step">点亮灯笼</span></div></div>
      <button type="button" class="cer-enter" id="cer-enter" disabled><span>推门入座</span></button>
      <div class="cer-foot">把真实待办，放进一座会记住你的村庄</div>`;
    host().appendChild(el);
    const fill = q('#cer-fill', el), pct = q('#cer-pct', el), step = q('#cer-step', el), btn = q('#cer-enter', el);
    const BEGIN = 1300, RUN = 2300, STUCK_MS = 4500;
    const start = performance.now();
    let stuckAt = 0, extra = 0, nags = 0, dip = 0, ready = false;

    const nag = (e) => {
      if (!stuckAt || ready || (e && e.target && e.target.closest && e.target.closest('#cer-enter'))) return;
      nags++;
      if (nags === 1 && typeof Store !== 'undefined') Store.logBait(true, '开场加载卡在 99%，忍不住催了它');
      if (nags <= 3) extra += 1200;
      dip = performance.now();
      step.textContent = NAGS[Math.min(nags, NAGS.length) - 1];
      play('error', { strength: 0.5 });
    };
    el.addEventListener('pointerdown', nag);
    window.addEventListener('keydown', nag);

    const show = (p) => { fill.style.width = p + '%'; pct.textContent = p; };
    const frame = (now) => {
      if (ready || !el.isConnected) return;
      const t = now - start - BEGIN;
      if (t < 0) { requestAnimationFrame(frame); return; }
      let p = Math.min(hate ? 99 : 100, Math.floor((t / RUN) * 100));
      if (!hate && p >= 100) return finish();
      if (hate && p >= 99 && !stuckAt) stuckAt = now;
      if (stuckAt) {
        const held = now - stuckAt;
        if (dip && now - dip < 900) p = 98;
        else if (!dip || now - dip > 1600) step.textContent = STUCK[Math.floor(held / 1100) % STUCK.length];
        if (held >= STUCK_MS + extra) return finish();
      } else {
        step.textContent = STEPS[Math.min(STEPS.length - 1, Math.floor((p / 100) * STEPS.length))];
      }
      show(p);
      requestAnimationFrame(frame);
    };
    const finish = () => {
      ready = true;
      show(100);
      step.textContent = '推门吧';
      btn.disabled = false;
      btn.classList.add('ready');
      window.removeEventListener('keydown', nag);
    };
    btn.addEventListener('click', () => {
      if (btn.disabled) return;
      play('open');
      el.classList.add('gone');
      setTimeout(() => { el.remove(); done(); }, 650);
    });
    requestAnimationFrame(frame);
  }

  /* ---------- 2. 入座大厅 ---------- */
  function lobby(done) {
    const mine = Math.max(0, SEATS.indexOf(((typeof Store !== 'undefined' && Store.role.art) || 'puppet_guard').replace('puppet_', '')));
    const acc = window.Login && Login.account();
    const nights = typeof Store !== 'undefined' ? Store.s.days.length : 1, left = typeof Store !== 'undefined' ? Store.pending : 0;
    const el = document.createElement('div');
    el.className = 'cer cer-lobby';
    el.id = 'cer-lobby';
    el.innerHTML = `<div class="cer-walls"></div><div class="cer-floor"></div>
      <i class="cer-lantern" style="left:16%;height:74px"></i><i class="cer-lantern l2" style="left:50%;height:46px"></i><i class="cer-lantern l3" style="left:84%;height:88px"></i>
      <header class="cer-top"><div class="cer-kicker">提线木偶 · 夜巡山庄</div><h2>入座</h2><div class="cer-meta">第 <b>${nights}</b> 夜 · ${left > 0 ? `木牌上还剩 <b>${left}</b> 件事` : '今天的事都点亮了'}</div></header>
      <div class="cer-table" id="cer-table"><svg class="cer-strings" id="cer-strings" aria-hidden="true"></svg><div class="cer-edge"></div><div class="cer-face"></div>
        <div class="cer-center"><div class="cer-candles"><i></i><i></i><i></i></div><div class="cer-seal">夜巡山庄</div><div class="cer-deck"></div></div>
        <div class="cer-seats" id="cer-seats">${SEATS.map((id, i) => `<button type="button" class="cer-seat${i === mine ? ' mine' : ''}" data-i="${i}" style="--d:${i * 55}ms" aria-label="${names()[id] || id}${i === mine ? '，你的座位' : ''}"><span class="cer-card art-puppet_${id}"></span><span class="cer-plate">${i === mine ? '你 · ' : ''}${names()[id] || id}</span>${i === mine ? `<span class="cer-who">${acc && acc.name ? String(acc.name).replace(/[<>&]/g, '') : '本机'}</span>` : ''}</button>`).join('')}</div>
      </div>
      <div class="cer-bottom"><div class="cer-hint" id="cer-hint">九个木偶都到齐了。你坐在发光的那张牌上。</div><button type="button" class="cer-start" id="cer-start">开始今夜</button></div>`;
    host().appendChild(el);
    requestAnimationFrame(() => el.classList.add('on'));
    const layout = () => {
      const w = el.clientWidth, h = el.clientHeight, zone = q('#cer-table', el);
      const cw = Math.round(Math.max(38, Math.min(w * 0.145, h * 0.085, 78)));
      const seatRx = Math.max(84, Math.min(w / 2 - cw * 0.52 - 10, h * 0.42, 360));
      const seatRy = Math.max(52, Math.min(seatRx * 0.62, h * 0.24));
      const tableRx = Math.max(60, seatRx - cw * 0.22), tableRy = tableRx * 0.5, cx = w / 2, cy = h * 0.5;
      zone.style.setProperty('--rx', tableRx.toFixed(1) + 'px');
      zone.style.setProperty('--ry', tableRy.toFixed(1) + 'px');
      zone.style.setProperty('--cy', cy.toFixed(1) + 'px');
      zone.style.setProperty('--cw', cw + 'px');
      let lines = '';
      el.querySelectorAll('.cer-seat').forEach((s, i) => {
        const th = ((90 + i * 40) * Math.PI) / 180, x = cx + Math.cos(th) * seatRx, y = cy + Math.sin(th) * seatRy, depth = (Math.sin(th) + 1) / 2;
        s.style.left = x.toFixed(1) + 'px';
        s.style.top = y.toFixed(1) + 'px';
        s.style.setProperty('--sc', (0.82 + 0.24 * depth).toFixed(3));
        s.style.zIndex = String(10 + Math.round(depth * 10));
        s.style.opacity = (0.6 + 0.4 * depth).toFixed(2);
        const topX = cx + (x - cx) * 0.42;
        lines += `<line class="${i === mine ? 'hot' : ''}" x1="${topX.toFixed(1)}" y1="-10" x2="${x.toFixed(1)}" y2="${(y - cw * 0.52).toFixed(1)}"/>`;
      });
      const svg = q('#cer-strings', el);
      svg.setAttribute('viewBox', `0 0 ${w} ${h}`);
      svg.innerHTML = lines;
    };
    layout();
    window.addEventListener('resize', layout);
    const hint = q('#cer-hint', el);
    el.addEventListener('click', (e) => {
      const seat = e.target.closest('.cer-seat');
      if (seat) {
        const i = Number(seat.dataset.i), name = names()[SEATS[i]] || '';
        hint.textContent = i === mine ? `你是${name}。想换同行，进山庄后去木偶工坊。` : `这是${name}的位置。你的牌在发光的那张。`;
        play('tick');
        return;
      }
      if (e.target.closest('#cer-start')) {
        play('whoosh');
        el.classList.add('go');
        window.removeEventListener('resize', layout);
        setTimeout(done, 950);
        setTimeout(() => el.remove(), 2400);
      }
    });
  }

  return { loader, lobby, SEATS };
})();
window.Ceremony = Ceremony;
