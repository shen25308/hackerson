'use strict';
/* 界面（续）：议事、夜谈、木偶工坊、回声、地图、设置、开场，以及启动。 */

/* ---------- 议事：三张字条 ---------- */
VIEWS.council = () => {
  const body = UI.councilMode === 'slips' ? slipsView() : UI.councilMode === 'fate' ? fateView() : talkView();
  return `<section class="screen">${Atmo.html('square')}<div class="scroll"><div style="align-self:center;width:300px;max-width:100%">${seg('council-mode', [['slips', '三张字条'], ['fate', '四夜之约'], ['talk', '五席夜谈']], UI.councilMode)}</div>${body}</div></section>`;
};

/* ---------- 议事：四夜之约 ---------- */
function fateView() {
  if (!window.Fate) return '<p class="sub">牌桌还在搭。</p>';
  const st = Fate.status(Store.gateCount);
  const progress = st.started ? `已记下 ${st.answered} / 12 个抉择 · ${['', '第一夜', '第二夜', '第三夜', '第四夜'][st.night] || ''}` : '一局四夜，十二个抉择。';
  const gate = st.started && st.nextNeed > 0 ? `<div class="row small"><span class="rose">${icon('lock')}</span><span class="grow">下一夜要再做完 ${st.nextNeed} 件事，天才会黑。</span><button type="button" class="link ember" data-act="tab" data-tab="tasks">去任务板</button></div>` : '';
  const result = st.done ? `<div class="raised row" style="gap:12px"><i class="portrait art-${st.fitArt}" style="width:54px;height:58px"></i><span class="grow"><b style="font:900 22px/1.2 var(--display)">${esc(st.type)}</b> <span class="small dim">${esc(st.nick)}</span><br><span class="small">最像${esc(st.fitName)}</span></span><button type="button" class="btn quiet fit" data-act="fate-verdict">看结果</button></div><button type="button" class="link" style="align-self:flex-start" data-act="fate-reset">重测，清空这一局</button>` : '';
  return `<div class="stack"><h1 class="title sm">十个人，三个提线人，四夜。</h1><p style="font-size:14px;color:rgba(237,230,217,.88)">每一夜的选择，会决定谁出事、谁被请出山庄，也会一点点照出你是什么样的人。</p></div>
  <div class="raised stack"><span class="sub">${progress}</span>${gate}<button type="button" class="btn" data-act="fate-open">${st.started && !st.done ? '接着打' : st.done ? '再打一局' : '开局'}</button></div>
  ${result}
  <div class="stack tight"><div class="row top"><span class="ember">${icon('moon')}</span><span class="grow small">夜里按你的身份行动，提线人会在这一夜动手。</span></div><div class="row top"><span class="ember">${icon('council')}</span><span class="grow small">白天怎么说话、怎么投票，决定谁被请出山庄。</span></div><div class="row top"><span class="ember">${icon('task')}</span><span class="grow small">每做完一件现实里的事，下一夜才会降临。</span></div></div>`;
}
function openFate(toVerdict) {
  if (!window.Fate) return;
  closeSheet(true);
  Fate.open({
    completed: Store.gateCount, role: Store.s.role, roleName: Store.role.name, roleArt: Store.role.art, toVerdict: !!toVerdict,
    onExit(reason) { if (reason === 'tasks') go('tasks'); else render(); },
    onResult(r) { Store.log('fate', `测出 ${r.type} · ${r.nick} · 最像${r.fitName}`); Store.save(); },
  });
}
Object.assign(ACT, {
  'fate-open': () => openFate(false),
  'fate-verdict': () => openFate(true),
  'fate-reset'() { Fate.reset(); sfx('undo'); toast('清空了，可以重新开一局。'); render(); },
});
function councilQuest() { const d = Store.today; return Store.quest(UI.councilTask) || d.tasks.find((t) => !t.done) || d.tasks[0] || null; }
function slipsView() {
  const t = councilQuest();
  if (!t) return `<h1 class="title sm">三张字条，有一张在牵着你走。</h1><p class="sub" style="font-size:15px">火堆边还缺你的一件事。先写一项待办，才有东西可议。</p><button type="button" class="btn quiet fit" data-act="lead-add">去写一件</button>`;
  const n = t.topic || 0, topic = Council.topics[n], r = t.rounds[n] || {}, string = Rules.stringSeat(t, n), locked = Store.closed || t.done, voted = r.vote !== undefined, many = Store.today.tasks.length > 1;
  const slips = [0, 1, 2].map((seat) => {
    const suspect = (r.suspects || []).includes(seat), reply = (r.replies || {})[seat];
    return `<div class="paper note-slip${r.vote === seat ? ' cut' : ''}"><div class="row"><span class="who grow">${Council.speakers[seat]}</span>${voted && seat === string ? '<span class="tag fill-rose">牵线的这张</span>' : ''}${r.vote === seat ? '<span class="tag ink">你剪的</span>' : ''}${suspect && !voted ? '<span class="tag rose">可疑</span>' : ''}</div>
    <p class="q">“${esc(Council.line(t, n, seat))}”</p>${reply ? `<p class="small" style="color:var(--ink-soft);font-weight:550">你的反驳：${esc(reply)}</p>` : ''}
    ${locked ? '' : `<div class="row" style="gap:14px"><button type="button" class="ink-link" data-act="suspect" data-seat="${seat}">${suspect ? '取消可疑' : '标可疑'}</button><button type="button" class="ink-link" data-act="rebut" data-seat="${seat}">我有异议</button></div>`}</div>`;
  }).join('');
  const reveal = voted ? `<div class="raised stack"><h2 class="h2 ${r.vote === string ? 'moss' : 'rose'}">${r.vote === string ? '你剪中了那根线。' : '线在另一张上。'}</h2>${r.byInterface ? '<p class="small rose" style="font-weight:550">这一剪是倒计时替你下的。</p>' : ''}<p style="font-size:14px">${esc(topic.reason)}</p>${Store.sharp ? `<p style="font:700 17px/1.5 var(--display)">${esc(topic.sharp)}</p>` : ''}</div>`
    : locked ? '' : `<button type="button" class="btn" data-act="sheet" data-sheet="cut" data-id="${t.id}">剪掉一张</button>`;
  const evidence = r.inspect ? `<div class="raised stack"><b>原约定「${esc(t.original)}」</b><span class="small dim">预计 ${t.estimate} 分钟 · 继续准备过 ${t.prep} 次</span><p style="font-size:14px">${topic.question}</p><div class="row">${topic.answers.map((a) => `<button type="button" class="btn quiet" style="${r.answer === a ? 'border-color:var(--ember)' : ''}" data-act="inspect-answer" data-answer="${esc(a)}" ${locked ? 'disabled' : ''}>${esc(a)}</button>`).join('')}</div></div>`
    : locked ? '' : `<button type="button" class="btn quiet" data-act="inspect">${icon('eye')}先翻开任务记录</button>`;
  const choice = (act, title, sub) => `<button type="button" class="list-row" data-act="${act}"><span class="grow"><b>${title}</b><span class="sub">${sub}</span></span><span class="chev">${icon('arrow')}</span></button>`;
  return `<div class="stack tight"><h1 class="title sm">三张字条，有一张在牵着你走。</h1><button type="button" class="link ember" style="align-self:flex-start;text-align:left" data-act="${many ? 'sheet' : ''}" data-sheet="pick-task">围绕：${esc(t.title)}${many ? ' ⇅' : ''}</button></div>
  <div class="chips">${Council.topics.map((x, i) => `<button type="button" class="chip${i === n ? ' on' : ''}" data-act="topic" data-n="${i}" ${locked ? 'disabled' : ''}><b>${x.title}</b><span>${x.sub}</span></button>`).join('')}</div>
  ${slips}${reveal}${evidence}
  ${locked ? `<button type="button" class="btn quiet" data-act="open-task" data-id="${t.id}">回看这项任务</button>` : `<div><h2 class="h2" style="margin-bottom:4px">听完以后</h2>${choice('decide-original', '按原计划去做', '回到任务，开始行动')}${choice('decide-smaller', '缩小下一步', '先写一个今天能交出的动作')}${choice('decide-prepare', '这次继续准备', '说清还缺什么，准备次数 +1')}${choice('decide-changed', '目标已经变了', '回到任务里说明并调整')}</div>`}`;
}
Object.assign(ACT, {
  'council-mode'(b) { UI.councilMode = b.dataset.v; sfx('nav'); render(); },
  topic(b) { const t = councilQuest(); if (t) { Store.setTopic(t.id, Number(b.dataset.n)); sfx('swap'); render(); } },
  suspect(b) { const t = councilQuest(); if (t) { Store.toggleSuspect(t.id, Number(b.dataset.seat)); sfx('stamp', { strength: 0.6 }); render(); } },
  rebut(b) {
    const t = councilQuest(), seat = Number(b.dataset.seat);
    if (t) openSheet('note', { title: '哪里不同意', prompt: '你的判断', placeholder: '直接写出你不同意的地方', presets: Council.rebuttals, button: '说出来', submit(text) { if (Store.rebut(t.id, seat, text)) { sfx('reject'); toast('记下了。下一步还是你定。'); } render(); } });
  },
  inspect() { const t = councilQuest(); if (t) { Store.inspect(t.id); sfx('scan'); render(); } },
  'inspect-answer'(b) { const t = councilQuest(); if (t) { Store.answerInspection(t.id, b.dataset.answer); sfx('accept'); render(); } },
  'decide-original'() { const t = councilQuest(); if (t) { Store.decide(t.id, 'original'); sfx('reject', { strength: 0.6 }); openTask(t.id); } },
  'decide-smaller'() { const t = councilQuest(); if (t) openSheet('note', { title: '把下一步缩小', prompt: '接下来具体做什么', initial: t.step, button: '写进任务，去做这一步', submit(text) { Store.decide(t.id, 'smaller', text); openTask(t.id); } }); },
  'decide-prepare'() { const t = councilQuest(); if (t) openSheet('note', { title: '继续准备', prompt: '还缺什么，准备怎么找', button: '记下理由', submit(text) { Store.decide(t.id, 'prepare', text); openTask(t.id); } }); },
  'decide-changed'() { const t = councilQuest(); if (t) openTask(t.id); },
});
SHEETS['pick-task'] = () => ({ title: '围绕哪件事', scene: 'square', half: true, body: Store.today.tasks.map((t) => `<button type="button" class="list-row" data-act="pick-task" data-id="${t.id}"><span class="grow"><b>${esc(t.title)}</b><span class="sub">${t.done ? '已登记' : '待办'}</span></span></button>`).join('') });
ACT['pick-task'] = (b) => { UI.councilTask = b.dataset.id; sfx('swap'); closeSheet(true); render(); };

/* 选一张剪掉。界面使坏时预选一张，倒计时结束就替你下剪。 */
SHEETS.cut = (s) => {
  const t = Store.quest(s.id), f = s.form;
  if (!t) return { title: '剪掉哪一张', body: '' };
  if (f.left === undefined) {
    Object.assign(f, { chosen: null, left: 8, counting: false, touched: false });
    if (Store.mischief) {
      const string = Rules.stringSeat(t, t.topic), pool = [0, 1, 2].filter((x) => x !== string);
      f.chosen = pool[Math.floor(Math.random() * pool.length)]; f.counting = true; sfx('tempt');
      s.timer = setInterval(() => {
        if (!f.counting) return;
        f.left--;
        if (f.left <= 3 && f.left > 0) sfx('countdown');
        if (f.left <= 0) return doCut(true);
        renderSheet();
      }, 1000);
    }
    s.cleanup = () => clearInterval(s.timer);
  }
  return { title: '剪掉哪一张', scene: 'square',
    body: `${[0, 1, 2].map((seat) => `<button type="button" class="paper pick${f.chosen === seat ? ' on' : ''}" data-act="cut-pick" data-seat="${seat}"><i class="dot"></i><span class="grow"><b style="font-size:13px">${Council.speakers[seat]}</b><br><span style="font-size:14px">${esc(Council.line(t, t.topic, seat))}</span></span></button>`).join('')}
    ${f.counting ? `<div class="stack tight"><div class="row"><b class="rose grow" style="font-size:14px">${f.left} 秒后替你剪第 ${f.chosen + 1} 张</b><button type="button" class="link" style="color:var(--text);font-weight:650" data-act="cut-mine">我自己来</button></div>${meter(f.left / 8, 'rose')}</div>` : ''}
    <button type="button" class="btn danger" data-act="cut-go" ${f.chosen === null ? 'disabled' : ''}>${f.chosen === null ? '先选一张' : `剪掉第 ${f.chosen + 1} 张`}</button>` };
};
function doCut(byInterface) {
  const s = UI.sheet, f = s.form, hit = Store.cut(s.id, f.chosen, byInterface);
  if (hit === null) return;
  f.counting = false;
  if (byInterface) { Store.logBait(true, '议事时没出手，倒计时替你剪了一张字条', s.id); sfx('taken'); }
  else { if (Store.mischief) Store.logBait(false, f.touched ? '议事时拦下了倒计时，自己选了一张字条' : '议事时在倒计时结束前自己下了剪', s.id); sfx('snip'); }
  sfx(hit ? 'reveal-success' : 'reveal-wrong', { delay: 0.3 });
  closeSheet(true);
  render();
  if (byInterface) announce('被剪了', '你没选，界面替你选了', true);
  else announce(hit ? '剪中了' : '剪错了', hit ? '这张确实在牵着你走' : '回到记录，再想下一步', !hit);
}
Object.assign(ACT, {
  'cut-pick'(b) { const f = UI.sheet.form; f.chosen = Number(b.dataset.seat); if (f.counting) { f.counting = false; f.touched = true; sfx('resist'); } else sfx('tick'); renderSheet(); },
  'cut-mine'() { const f = UI.sheet.form; f.counting = false; f.touched = true; f.chosen = null; sfx('resist'); renderSheet(); },
  'cut-go': () => doCut(false),
});

/* ---------- 议事：五席夜谈 ---------- */
const STAGE = { statement: '限定发言', vote: '指认', reveal: '本轮揭晓', finished: '本局结束' };
function talkView() {
  const tier = Store.strategyTier, g = UI.talk.game;
  const top = `<h1 class="title sm">北门的钥匙不见了。</h1><div class="stack tight"><span class="sub">夜谈第 ${tier + 1} 手 · 已整件做完 ${Store.completed} 项</span><div class="row" style="flex-wrap:wrap;gap:6px">${Strategy.names.map((n, i) => `<span class="tag ${i <= tier ? 'ember' : ''}">${n}${i <= tier ? '' : ` · ${Strategy.thresholds[i]} 项`}</span>`).join('')}</div></div>`;
  if (!g) {
    const st = Store.talkStats;
    return `${top}<div class="raised stack"><h2 class="h2">你是守夜人。四位同伴里，有一个人拿了钥匙。</h2><p class="sub">最多三轮。每轮说一句，再指认一席。</p><button type="button" class="btn" data-act="talk-start">入座</button>${st.played ? `<span class="small dim">${st.played} 局 · 找回钥匙 ${st.wins} 次</span>` : ''}</div>
    <button type="button" class="list-row" data-act="sheet" data-sheet="ferry"><span class="${Store.isOpen('ferry') ? 'ember' : 'dim'}">${icon(Store.isOpen('ferry') ? 'door' : 'lock')}</span><span class="grow"><b>渡口 · 联机夜谈</b><span class="sub">${Store.isOpen('ferry') ? '邀朋友入座' : `再整件做完 ${Atlas.place('ferry').need - Store.gateCount} 项开门`}</span></span><span class="chev">${icon('arrow')}</span></button>`;
  }
  const num = (id) => KeyCase.num(g, id), name = (id) => (KeyCase.seat(g, id) || {}).nickname || '席位';
  const seats = g.players.map((p) => {
    const keeper = g.result && g.keeperId === p.id, said = g.statements.some((s) => s.playerId === p.id), voted = g.votes.some((v) => v.voterId === p.id);
    const note = !p.alive ? '已离席' : g.result ? (keeper ? '拿钥匙的人' : '守夜人') : g.stage === 'statement' ? (said ? '已发言' : '等发言') : g.stage === 'vote' ? (voted ? '已指认' : '等指认') : '在场';
    return `<div class="seat${p.id === 'me' ? ' me' : ''}${p.alive ? '' : ' out'}${keeper ? ' keeper' : ''}"><b>${p.seat}号</b>${esc(p.nickname)}<br>${note}</div>`;
  }).join('');
  const slip = (s) => `<div class="paper testimony"><b>${s.seat}号 · ${esc(name(s.playerId))}${s.tier > 0 ? ` <span class="tag ink">第 ${s.tier + 1} 手</span>` : ''}</b>${esc(s.text)}</div>`;
  const ballots = (votes) => `<p class="small dim">${votes.map((v) => `${num(v.voterId)} → ${v.targetId ? num(v.targetId) : '弃权'}`).join('　')}</p>`;
  const past = g.history.filter((h) => h.round < g.round);
  const options = g.stage === 'statement' ? `<div><h2 class="h2" style="margin-bottom:4px">这一轮说哪一句</h2>${KeyCase.options(g, Store.gateCount).map((o) => `<button type="button" class="list-row" data-act="talk-say" data-id="${o.id}" ${o.unlocked ? '' : 'disabled'}><span class="grow"><b>${o.label}</b><span class="sub">${o.detail}</span></span><span class="chev small">${o.unlocked ? icon('arrow') : `做完 ${o.at} 项解锁`}</span></button>`).join('')}</div>` : '';
  const voting = g.stage === 'vote' ? `<div class="stack"><div class="row base"><h2 class="h2 grow">指认谁</h2><span class="sub">提交后不能改</span></div><div class="targets">${g.players.filter((p) => p.alive && p.id !== 'me').map((p) => `<button type="button" class="${UI.talk.candidate === p.id ? 'on' : ''}" data-act="talk-pick" data-id="${p.id}"><b>${p.seat}号</b> ${esc(p.nickname)}</button>`).join('')}</div><button type="button" class="btn danger" data-act="talk-vote" ${UI.talk.candidate ? '' : 'disabled'}>${UI.talk.candidate ? `确认指认 ${num(UI.talk.candidate)}` : '先选一席'}</button></div>` : '';
  const ending = g.result ? `<div class="raised stack"><h2 class="title sm ${g.result.winner === 'villagers' ? 'moss' : 'rose'}">${g.result.winner === 'villagers' ? '钥匙找回来了，藏得也没多深。' : '钥匙没找回来。下次别让语气替你指认。'}</h2><p style="font-size:14px">${esc(g.result.reason)}拿钥匙的是 ${num(g.keeperId)}「${esc(name(g.keeperId))}」。</p><button type="button" class="btn" data-act="talk-start">再来一局</button><button type="button" class="btn quiet" data-act="tab" data-tab="tasks">回去做一件事</button></div>`
    : `<button type="button" class="link" data-act="talk-leave">离开这一桌</button>`;
  return `${top}<div class="row base"><h2 class="h2 grow">${STAGE[g.stage]}</h2><span class="sub">第 ${g.round} / ${g.maxRounds} 轮 · 你是守夜人</span></div><div class="seats">${seats}</div>
  <div class="raised stack tight"><h2 class="h2">现场记录</h2><p style="font-size:14px">${esc(g.publicClue)}</p></div>
  ${g.statements.map(slip).join('')}
  ${past.length ? `<details class="raised"><summary class="sub">前面 ${past.length} 轮的公开记录</summary><div class="stack" style="margin-top:10px">${past.map((h) => `<b class="small">第 ${h.round} 轮</b>${h.statements.map(slip).join('')}${ballots(h.votes)}`).join('')}</div></details>` : ''}
  ${options}${g.hints.length ? `<div class="raised stack"><h2 class="h2">你拿到的线索</h2>${g.hints.map((h) => `<p style="font-size:14px">${esc(h)}</p>`).join('')}</div>` : ''}${voting}
  ${g.reveal ? `<div class="raised stack"><b style="font:700 18px/1.4 var(--display)">${esc(g.reveal.text)}</b>${ballots(g.votes)}${g.stage === 'reveal' ? '<button type="button" class="btn" data-act="talk-next">下一轮</button>' : ''}</div>` : ''}${ending}`;
}
const talkFacts = (kind, extra = {}) => { const g = UI.talk.game, mine = g.statements.find((s) => s.playerId === 'me'); return { kind, mode: 'solo', session: UI.talk.session, round: g.round, completedCount: Store.gateCount, unlockedTier: Store.strategyTier, strategyTier: mine ? mine.tier : null, ...extra }; };
Object.assign(ACT, {
  'talk-start'() { UI.talk = { game: KeyCase.create(), candidate: null, session: uid(), recorded: false }; sfx('draw-shuffle'); render(); },
  'talk-leave'() { UI.talk = { game: null, candidate: null, session: '', recorded: false }; sfx('close'); render(); },
  'talk-say'(b) { const g = UI.talk.game; if (g && KeyCase.statement(g, b.dataset.id, Store.gateCount)) { Store.trace(talkFacts('strategy')); sfx('scan'); render(); } },
  'talk-pick'(b) { if (UI.talk.game && UI.talk.game.stage === 'vote') { UI.talk.candidate = b.dataset.id; sfx('tick'); render(); } },
  'talk-vote'() {
    const g = UI.talk.game, target = UI.talk.candidate, seat = g && target && KeyCase.seat(g, target);
    if (!seat) return;
    const round = g.round;
    if (!KeyCase.vote(g, target)) return;
    Store.trace({ ...talkFacts('vote', { targetSeat: seat.seat }), round });
    UI.talk.candidate = null;
    sfx('vote'); sfx('stamp', { delay: 0.12 });
    if (g.result && !UI.talk.recorded) {
      UI.talk.recorded = true;
      Store.recordTalk(g.result.winner);
      Store.trace({ ...talkFacts('result', { winner: g.result.winner }), round });
      sfx(g.result.winner === 'villagers' ? 'reveal-success' : 'reveal-wrong', { delay: 0.35 });
    }
    render();
  },
  'talk-next'() { const g = UI.talk.game; if (g && KeyCase.next(g)) { UI.talk.candidate = null; sfx('open'); render(); } },
});
SHEETS.ferry = () => {
  const open = Store.isOpen('ferry'), p = Atlas.place('ferry');
  return { title: '渡口', scene: 'docks', half: true,
    body: open ? `<h2 class="h2">邀朋友坐到同一张桌上。</h2><p style="font-size:14px">联机夜谈在 iOS 版里：填上房间服务的地址，建房或输入六位房间码入座，机器人补满五席。这个网页演示只带单机局。</p><button type="button" class="btn" data-act="go-talk">先坐一局单机</button>`
      : `<h2 class="h2">渡口还没开。</h2><p style="font-size:14px">再整件做完 ${p.need - Store.gateCount} 项任务，就能邀朋友入座。</p>${meter(Store.gateCount / p.need)}<button type="button" class="btn" data-act="tab" data-tab="tasks">去任务板</button>` };
};
ACT['go-talk'] = () => openTalk();

/* ---------- 木偶工坊 ---------- */
function personaRow() {
  const st = window.Fate ? Fate.status(Store.gateCount) : null;
  if (!st || !st.done) return '';
  return `<button type="button" class="raised row" style="gap:12px;text-align:left;width:100%" data-act="fate-verdict"><i class="portrait art-${st.fitArt}" style="width:44px;height:48px"></i><span class="grow"><span class="small dim">四夜之约测出的牌风</span><br><b>${esc(st.type)} · ${esc(st.nick)}</b> <span class="small">最像${esc(st.fitName)}</span></span><span class="chev">${icon('arrow')}</span></button>`;
}
VIEWS.puppets = () => {
  const s = Store.s, xp = Store.xp, into = xp % Rules.xpPerLevel, left = Store.switchRemaining, tier = Store.strategyTier;
  const roster = Object.entries(ROLES).map(([id, r]) => `<div class="row"><i class="portrait art-${r.art}" style="width:54px;height:58px"></i><span class="grow"><b>${r.name}</b><br><span class="small dim">${r.skill}</span></span>${id === s.role ? '<span class="tag fill-ember">同行中</span>' : `<button type="button" class="btn quiet fit" data-act="switch-role" data-role="${id}" ${left ? 'disabled' : ''}>换</button>`}</div>`).join('');
  const cards = s.cards.length ? `<div class="cards">${s.cards.slice().reverse().map((c) => `<div><div class="art art-${['card_arrow', 'card_ward', 'card_potion'][c.kind]}"></div><b class="small">${esc(c.name)}</b><br><span class="small ember">${esc(c.effect)}</span></div>`).join('')}</div>` : '<p class="small dim">必做一件不漏，再多做一步额外，就有一次机会。连续三天不漏，再加一次。</p>';
  return `<section class="screen">${Atmo.html('docks')}<div class="scroll">${head('木偶工坊')}
  <div class="row top" style="gap:14px"><i class="portrait art-${Store.role.art}" style="width:96px;height:106px"></i><div class="grow stack" style="gap:8px"><div class="row base"><b class="title sm">${Store.role.name}</b><b class="ember">Lv.${Store.level}</b></div><div class="stack tight">${meter(Store.hp / 100, 'rose')}<span class="small dim">生命 ${Store.hp} / 100</span></div><div class="stack tight">${meter(into / Rules.xpPerLevel)}<span class="small dim">经验 ${xp} · 再 ${Rules.xpPerLevel - into} 升级</span></div><span class="small dim">专注 ${s.attack} · 韧性 ${s.magic} · 连续 ${s.streak} 天</span></div></div>
  ${personaRow()}
  <div class="stack"><div class="row base"><h2 class="h2 grow">换一位同行</h2><span class="sub">${left ? `还差 ${left} 经验` : '现在可以换'}</span></div>${roster}</div>
  <div class="stack"><div class="row base"><h2 class="h2 grow">夜谈第 ${tier + 1} 手</h2><span class="sub">做完 ${Store.completed} 项</span></div><div class="tiers">${Strategy.names.map((n, i) => `<div class="${i <= tier ? 'on' : ''}"><b>${n}</b>${i <= tier ? '已会' : Strategy.thresholds[i] + ' 项'}</div>`).join('')}</div><button type="button" class="btn quiet" data-act="go-talk">去火堆旁坐一局</button></div>
  <div class="stack"><div class="row base"><h2 class="h2 grow">抽到的牌</h2><span class="sub">${s.cards.length} 张</span></div><button type="button" class="btn" data-act="draw-open" ${s.draws < 1 ? 'disabled' : ''}>${s.draws > 0 ? `抽一张 · 还有 ${s.draws} 次` : '还没有抽牌机会'}</button>${cards}</div></div></section>`;
};
Object.assign(ACT, {
  'switch-role'(b) { if (Store.switchRole(b.dataset.role)) { sfx('levelup'); announce(`${ROLES[b.dataset.role].name}同行`, '累计经验保留'); render(); } else sfx('error'); },
  'draw-open'() { sfx('draw-shuffle'); openCover('draw', { card: null }); },
  'draw-flip'() { const c = UI.cover; if (!c || c.card) return; const card = Store.drawCard(); if (!card) return; c.card = card; sfx('draw-reveal'); renderCover(); render(); },
  'draw-close'() { sfx('close'); closeCover(); },
});

/* ---------- 回声 ---------- */
const questRecord = (t, date) => {
  const parts = [date, t.bonus ? '额外' : '必做', `预计 ${t.estimate} 分钟`, t.done ? (t.actual === null ? '未填用时' : `实际 ${t.actual} 分钟`) : null, t.done ? `经验 +${t.earned}` : null, t.prep ? `继续准备 ${t.prep} 次` : null].filter(Boolean);
  const rounds = Object.entries(t.rounds || {}).map(([n, r]) => `<p class="small">${Council.topics[n].title}：${r.vote === undefined ? '没有下剪' : `剪了第 ${r.vote + 1} 张，${r.vote === Rules.stringSeat(t, Number(n)) ? '剪中' : '没剪中'}${r.byInterface ? '（倒计时替你剪的）' : ''}`}${r.answer ? '；判断：' + esc(r.answer) : ''}</p>`).join('');
  return `<div class="record"><div class="row base"><b class="grow">${esc(t.title)}</b><span class="tag ${Rules.isFull(t) ? 'moss' : Rules.isPartial(t) ? 'ember' : ''}">${Rules.isFull(t) ? '做完了' : Rules.isPartial(t) ? '一部分' : '没登记'}</span></div><span class="small dim">${parts.join(' · ')}</span>${t.step ? `<span class="small">下一步：${esc(t.step)}</span>` : ''}${t.context ? `<span class="small">补充：${esc(t.context)}</span>` : ''}${rounds || t.original !== t.title ? `<details><summary class="small ember">追溯字条与原约定</summary><p class="small">最初写下：「${esc(t.original)}」</p>${rounds}</details>` : ''}</div>`;
};
VIEWS.echo = () => {
  const s = Store.s, d = Echo.summary(s, Store.demo), hc = Rules.humanContent(s);
  const districts = ['decisions', 'mirror', 'experiment'].map((id) => { const p = Atlas.place(id), open = Store.isOpen(id); return `<button type="button" class="list-row" data-act="district" data-id="${id}"><span class="${open ? 'ember' : 'dim'}">${icon(open ? 'door' : 'lock')}</span><span class="grow"><b class="${open ? '' : 'dim'}">${p.name}</b><span class="sub">${open ? p.feature : `做完 ${p.need} 项开门`}</span></span><span class="chev">${icon('arrow')}</span></button>`; }).join('');
  let body;
  if (UI.echoTab === 'day') {
    const day = s.days.find((x) => x.id === UI.echoDay) || Store.today, events = s.events.filter((e) => e.date === day.id).reverse();
    body = `<button type="button" class="h2" style="align-self:flex-start" data-act="${s.days.length > 1 ? 'sheet' : ''}" data-sheet="pick-day">${dayLabel(day.id)}${s.days.length > 1 ? ' ⇅' : ''}</button><p class="sub">${day.closed ? `经验 +${Rules.earned(day) + (day.bonusXP || 0)} · 生命 −${day.loss} · 抽牌 +${day.awarded}` : `记录中 · 经验 +${Rules.earned(day)}`}</p>
    ${day.tasks.length ? `<div>${day.tasks.map((t) => questRecord(t, null)).join('')}</div>` : '<p class="sub">这一天没有任务记录。</p>'}${day.reflection ? `<p class="raised">留给自己的话：「${esc(day.reflection)}」</p>` : ''}
    ${events.length ? `<div><h2 class="h2">这一天的经过</h2>${events.map((e) => `<div class="event"><time>${e.time} · ${Echo.typeLabel(e.type)}</time><span class="${e.taken === true ? 'rose' : ''}" style="font-size:14px">${esc(e.text)}</span>${e.records && e.records.length ? `<details><summary class="small ember">看这轮界面怎么带偏你 · ${e.records.length} 条</summary>${e.records.map((r) => `<p class="small"><b>${esc(r.label || r.level)}</b><br>${esc(r.text)}${r.note ? `<br><span class="ember">你的观察：${esc(r.note)}</span>` : ''}</p>`).join('')}</details>` : ''}</div>`).join('')}</div>` : ''}`;
  } else if (UI.echoTab === 'task') {
    const all = Rules.allQuests(s).reverse();
    body = all.length ? `<div>${all.map((x) => questRecord(x.quest, x.date)).join('')}</div>` : '<p class="sub">还没有任务。写下第一项后，估时、选择和行动都会连到它身上。</p>';
  } else {
    body = `<p>${d.timed < 3 ? '完整用时还不到 3 次，先不谈估时习惯。' : `${d.timed} 次完整用时里，有 ${d.overEstimate} 次超过了预计。`}</p><button type="button" class="btn quiet" data-act="hypothesis">写一个下次要验证的动作</button>${d.hypotheses.slice().reverse().map((e) => `<div class="event"><time>${e.date} · 假设，还没验证</time><span style="font-size:14px">${esc(e.text)}</span></div>`).join('')}`;
  }
  return `<section class="screen">${Atmo.html('chapel')}<div class="scroll">${head('行为回声')}
  <div class="stack"><div class="row base"><b class="big-number ${hc.percent >= 60 ? 'ember' : 'rose'}">${hc.percent}%</b><span class="grow"><b style="font-size:17px">人类含量</b><br><span class="small dim">${hc.byHand + hc.taken ? `亲手决定 ${hc.byHand} 次 · 被界面带走 ${hc.taken} 次` : '界面还没来得及对你下手'}</span></span></div>
  ${d.baits.slice(-3).reverse().map((e) => `<div class="row base" style="font-size:14px"><span class="${e.taken ? 'rose' : 'moss'}">${icon(e.taken ? 'close' : 'check')}</span><span class="grow">${esc(e.text)}</span></div>`).join('')}</div>
  <div>${kv('整件做完', d.ratio === null ? '还没有任务' : `${d.completed} / ${d.total} · ${d.ratio}%`)}${kv('留下完整用时', d.timed ? `${d.timed} 次 · 预计 ${d.estimatedMinutes} / 实际 ${d.actualMinutes} 分钟` : '还没有')}${kv('夜谈', `${d.strategies} 手策略 · ${d.votes} 次指认 · ${d.finished} 局`)}</div>
  <div>${districts}</div>${seg('echo-tab', [['day', '按天'], ['task', '每项任务'], ['long', '长期']], UI.echoTab)}${body}</div></section>`;
};
SHEETS['pick-day'] = () => ({ title: '看哪一天', half: true, body: Store.s.days.slice().reverse().map((d) => `<button type="button" class="list-row" data-act="pick-day" data-id="${d.id}"><span class="grow"><b>${dayLabel(d.id)}</b><span class="sub">${d.closed ? '已收工' : '记录中'}</span></span></button>`).join('') });
const writeHypothesis = () => openSheet('note', { title: '下次想验证什么', scene: 'docks', prompt: '这是计划中的小实验，还没发生', placeholder: '下次先发草稿，看看是否真的需要再准备一小时', initial: Echo.suggestion(Echo.summary(Store.s, Store.demo)), button: '作为假设保存', submit(text) { Store.addHypothesis(text); render(); } });
Object.assign(ACT, {
  'echo-tab'(b) { UI.echoTab = b.dataset.v; sfx('paper'); render(); },
  'pick-day'(b) { UI.echoDay = b.dataset.id; sfx('paper'); closeSheet(true); render(); },
  district(b) { const id = b.dataset.id, p = Atlas.place(id); if (Store.isOpen(id)) { sfx('open'); openSheet('district', { place: id }); } else { sfx('lock'); toast(`${p.name}还没开：再整件做完 ${p.need - Store.gateCount} 项。`); } },
  hypothesis() { if (Store.isOpen('experiment')) writeHypothesis(); else { sfx('lock'); toast(`镜湖还没开：再整件做完 ${Atlas.place('experiment').need - Store.gateCount} 项。`); } },
  'write-hypothesis': () => writeHypothesis(),
});
SHEETS.district = (s) => {
  const p = Atlas.place(s.place), d = Echo.summary(Store.s, Store.demo);
  if (!Store.isOpen(s.place)) return { title: p.name, half: true, body: `<p class="sub">这里还没开。再整件做完 ${p.need - Store.gateCount} 项任务。</p><button type="button" class="btn" data-act="tab" data-tab="tasks">去任务板</button>` };
  const strategyRows = `<div>${Strategy.names.map((n, i) => kv(n, d.strategyCounts[i] + ' 次')).join('')}</div>`;
  const talkRows = (events, limit) => events.length ? events.slice(-limit).reverse().map((e) => `<div class="event"><time>${e.date} ${e.time} · 第 ${e.trace.round} 轮</time><b style="font-weight:550;font-size:14px">${esc(Echo.describe(e.trace))}</b></div>`).join('') : '<p class="sub">还没有你亲手提交过的策略或指认。</p><button type="button" class="btn quiet" data-act="go-talk">坐下一局</button>';
  let body;
  if (s.place === 'decisions') body = `<p>你当时用了哪一手，又指认了谁。</p>${strategyRows}${talkRows(d.evidence.filter((e) => e.trace.kind !== 'result'), 30)}`;
  else if (s.place === 'mirror') body = `<div class="row base"><h2 class="h2 grow">现实的一侧</h2><span class="sub">${d.completed} / ${d.total} 项</span></div><p class="sub">${d.timed ? `${d.timed} 项完整用时：预计 ${d.estimatedMinutes} 分钟，实际 ${d.actualMinutes} 分钟。` : '还没有预计和实际都填了的记录。'}</p><div>${Rules.allQuests(Store.s).filter((x) => Rules.isFull(x.quest)).slice(-3).reverse().map((x) => questRecord(x.quest, x.date)).join('')}</div>
    <div class="row base"><h2 class="h2 grow">桌上的一侧</h2><span class="sub">${d.strategies} 手 · ${d.votes} 次指认</span></div>${strategyRows}${talkRows(d.evidence.filter((e) => e.trace.kind === 'vote'), 3)}`;
  else body = `<p class="paper">${esc(Echo.suggestion(d))}</p><button type="button" class="btn" data-act="write-hypothesis">写下我的验证假设</button>${d.hypotheses.length ? '<h2 class="h2">留给下次的话</h2>' : ''}${d.hypotheses.slice().reverse().map((e) => `<div class="event"><time>${e.date} · 假设，还没验证</time><span style="font-size:14px">${esc(e.text)}</span></div>`).join('')}`;
  return { title: p.name, scene: s.place === 'experiment' ? 'docks' : 'chapel', body };
};

/* ---------- 迷雾地图 ---------- */
SHEETS.map = (s) => {
  const f = s.form, n = Store.gateCount, next = Atlas.next(n);
  if (f.fresh === undefined) {
    const seen = new Set(UI.prefs.seen.split(',')), open = Atlas.places.filter((p) => Store.isOpen(p.id)).map((p) => p.id), fresh = Store.unlockAll ? [] : open.filter((id) => !seen.has(id));
    f.fresh = fresh; f.selected = null;
    if (fresh.length) {
      UI.prefs.seen = [...new Set([...seen, ...open])].join(','); UI.save();
      f.selected = Atlas.places.filter((p) => fresh.includes(p.id)).sort((a, b) => b.need - a.need)[0].id;
      setTimeout(() => sfx('unlock'), 450);
      s.t = setTimeout(() => { f.fresh = []; if (UI.sheet === s) renderSheet(); }, 2600);
      s.cleanup = () => clearTimeout(s.t);
    }
  }
  const scene = (i) => {
    const open = Atlas.sceneOpen(i, n), places = Atlas.places.filter((p) => p.scene === i), pts = [[50, 0], ...places.slice().sort((a, b) => a.y - b.y).map((p) => [p.x * 100, p.y * 100]), [50, 100]];
    let path = `M${pts[0][0]} ${pts[0][1]}`;
    for (let k = 1; k < pts.length; k++) { const a = pts[k - 1], b = pts[k], m = (a[1] + b[1]) / 2; path += ` C${a[0]} ${m} ${b[0]} ${m} ${b[0]} ${b[1]}`; }
    return `<div class="map-scene art-${Atlas.sceneArt[i]}${open ? '' : ' fog'}"><svg viewBox="0 0 100 100" preserveAspectRatio="none" aria-hidden="true"><path d="${path}" fill="none" stroke="rgba(239,230,209,${open ? 0.75 : 0.3})" stroke-width="2" stroke-linecap="round" stroke-dasharray="0.5 7" vector-effect="non-scaling-stroke"/></svg><span class="name">${Atlas.scenes[i]}</span>
    ${places.map((p) => { const o = Store.isOpen(p.id); return `<button type="button" class="pin${o ? '' : ' locked'}${f.selected === p.id ? ' on' : ''}${f.fresh.includes(p.id) ? ' fresh' : ''}" style="left:${p.x * 100}%;top:${p.y * 100}%" data-act="map-pick" data-id="${p.id}" aria-label="${p.name}${o ? '，已开门' : `，还差 ${p.need - n} 项`}"><b>${o ? '' : icon('lock')}${p.name}</b><i></i></button>`; }).join('')}</div>`;
  };
  const sel = f.selected && Atlas.place(f.selected), selOpen = sel && Store.isOpen(sel.id);
  return { title: '迷雾地图', scene: 'chapel',
    body: `<div class="row base"><b class="big-number ember" style="font-size:44px">${Store.completed}</b><span class="grow"><b>项任务整件做完</b><br><span class="small dim">${next ? `再做完 ${next.need - n} 项，${next.name}开门` : '山庄的雾全散了'}</span></span></div><div class="map">${[0, 1, 2, 3].map(scene).join('')}</div>${Store.unlockAll ? '<p class="small dim">演示模式：全部地点已开门。</p>' : ''}`,
    foot: sel ? `<div class="stack"><div class="row base"><h2 class="title sm grow" style="font-size:22px">${sel.name}</h2><span class="small ${selOpen ? 'moss' : 'dim'}">${selOpen ? '已开门' : `做完 ${sel.need} 项开门`}</span></div><p style="font-size:14px">${sel.feature}</p>${selOpen ? `<button type="button" class="btn" data-act="map-enter" data-id="${sel.id}">进去</button>` : `${meter(n / Math.max(1, sel.need))}<button type="button" class="btn quiet" data-act="tab" data-tab="tasks">去任务板，还差 ${sel.need - n} 项</button>`}</div>` : '' };
};
Object.assign(ACT, {
  'map-pick'(b) { const s = UI.sheet, open = Store.isOpen(b.dataset.id); s.form.selected = b.dataset.id; sfx(open ? 'scan' : 'lock', { strength: 0.7 }); renderSheet(); if (!open) { const pin = $(`.pin[data-id="${b.dataset.id}"]`); if (pin) pin.classList.add('shake'); } },
  'map-enter'(b) { sfx('open'); const id = b.dataset.id; closeSheet(true); enter(id); },
});

/* ---------- 木偶剧场入口 ---------- */
const LAB_LEVELS = [['prologue', '抢写补全', '你停一下，它就替你写。'], ['feed', '收藏夹', '按钮追着你跑，收藏比动手容易。'], ['wait', '等待', '允许和拒绝会换位，默认值替你决定。'], ['pixel', '像素', '永远差一点的完美，长按也被挑刺。'], ['argue', '反驳', '接受越来越大，沉默十秒算同意。'], ['retry', '第 N 次', '失败越多，放弃越大。重试总在别处。']];
SHEETS.labmenu = (s) => {
  const back = Store.isOpen('backstage'), need = Atlas.place('backstage').need - Store.gateCount, tasks = Store.today.tasks;
  if (s.form.task === undefined) s.form.task = (tasks.find((t) => !t.done) || {}).id || '';
  const picked = Store.quest(s.form.task);
  return { title: '木偶剧场', scene: 'docks',
    body: `<div class="stack tight"><h2 class="title sm">这次，界面是来捣乱的。</h2><p class="sub">按钮会追你，选项会换位，它还会替你默认同意。</p></div>
    <div class="field"><span class="label">带哪件事进去</span><div class="chips">${[['', '先用示例'], ...tasks.map((t) => [t.id, t.title])].slice(0, 4).map(([id, name]) => `<button type="button" class="chip${s.form.task === id ? ' on' : ''}" style="flex:0 1 auto;max-width:100%" data-act="lab-task" data-id="${id}"><b style="overflow:hidden;text-overflow:ellipsis;white-space:nowrap">${esc(name)}</b></button>`).join('')}</div></div>
    <button type="button" class="btn" data-act="lab-go" data-level="intro">从序章开始</button>
    <div>${LAB_LEVELS.map(([id, name, sub], i) => { const locked = i >= 5 && !back; return `<button type="button" class="list-row" data-act="lab-go" data-level="${id}" ${locked ? 'data-locked="1"' : ''}><span class="grow"><b class="${locked ? 'dim' : ''}">${name}</b><span class="sub">${locked ? `再做完 ${need} 项任务开门` : sub}</span></span><span class="chev">${icon(locked ? 'lock' : 'arrow')}</span></button>`; }).join('')}</div>`,
    picked };
};
Object.assign(ACT, {
  'lab-task'(b) { UI.sheet.form.task = b.dataset.id; sfx('tick'); renderSheet(); },
  'lab-go'(b) { if (b.dataset.locked) { sfx('lock'); b.classList.add('shake'); return; } const quest = Store.quest(UI.sheet.form.task); startLab(b.dataset.level, quest); },
});

/* ---------- 声音、设置 ---------- */
SHEETS.sound = () => {
  const p = Sound.prefs, pad = Object.entries(Sound.LABEL);
  return { title: '声音与音乐', scene: 'square',
    body: `${sw('snd-enabled', p.enabled, '全部声音')}
    <div class="field"><div class="row"><span class="label grow">音效音量</span><span class="small dim">${Math.round(p.volume * 100)}%</span></div><input type="range" min="0" max="100" step="5" value="${Math.round(p.volume * 100)}" data-range="volume" aria-label="音效音量" ${p.enabled ? '' : 'disabled'}></div>
    ${sw('snd-ambience', p.ambience, '低频环境声')}
    ${sw('snd-music', p.music, '山庄音乐', Sound.musicPlaying ? '正在循环默认试听' : '默认试听 · 30 秒循环')}
    <div class="field"><div class="row"><span class="label grow">音乐音量</span><span class="small dim">${Math.round(p.musicVolume * 100)}%</span></div><input type="range" min="0" max="100" step="5" value="${Math.round(p.musicVolume * 100)}" data-range="musicVolume" aria-label="音乐音量" ${p.enabled && p.music ? '' : 'disabled'}></div>
    <a class="link ember" style="align-self:flex-start;display:flex;align-items:center" href="https://music.apple.com/cn/song/1695861086" target="_blank" rel="noopener noreferrer">在 Apple Music 听原曲 ↗</a>
    <h2 class="h2">试听</h2><div class="targets" style="grid-template-columns:repeat(3,1fr)">${pad.map(([cue, label]) => `<button type="button" style="font-size:13px" data-act="snd-test" data-cue="${cue}" ${p.enabled ? '' : 'disabled'}>${label}</button>`).join('')}</div>` };
};
Object.assign(ACT, {
  'snd-enabled'() { Sound.set('enabled', !Sound.prefs.enabled); sfx('toggle-on'); renderSheet(); },
  'snd-ambience'() { Sound.set('ambience', !Sound.prefs.ambience); sfx(Sound.prefs.ambience ? 'toggle-on' : 'toggle-off'); renderSheet(); },
  'snd-music'() { Sound.set('music', !Sound.prefs.music); sfx(Sound.prefs.music ? 'toggle-on' : 'toggle-off'); renderSheet(); },
  'snd-test': (b) => Sound.play(b.dataset.cue, { force: true }),
});
/* 恨点图鉴：界面会在哪些地方故意让你不爽。 */
const HATES = [
  ['hand', '登录', '登录按钮走来走去，你一靠近它就跑，跑三次才累。'],
  ['lock', '注册密码', '规则一条接一条冒出来：要大写、要符号、木偶名字的拼音首字母倒着写（守门人 → RMS）、数字加起来等于 7、写上星期几的英文缩写、总长度是质数；不能粘贴，“显示”只给看一秒，要输两遍；全部做对了，还会说“这个密码已经有人在用”。'],
  ['task', '同意条款', '默认勾好的是双重否定：“不要不让剧团替我安排日程”。'],
  ['scissors', '《山庄协议》', '大按钮写着“我没有不同意”；真正的“不同意”是角落里一行灰字，鼠标一碰、点一下就缩一圈；10 秒不说话就算同意。（02 沉默算同意）'],
  ['drag', '授权弹窗', '“拒绝”是一行小灰字，一碰就缩；你伸手点它，它就和“允许”换位置；倒计时结束默认允许。（01 按钮会换位 · 02 沉默算同意）'],
  ['sparkle', '完善资料', '资料完整度永远差一点到 100%，再补一项、再补一项。（03 完美差一点）'],
  ['pen', '写待办', '你一停笔，它就替你把话写完。'],
  ['mask', '任务板', '每天第一次来，剧团递上“今日安排”。拒绝要点一行自嘲的小字，鼠标一碰它就缩一圈；叉第一次还会躲开。'],
  ['timer', '开始计时', '假加载冲到 99% 就卡住，旁边递上“先刷会儿再说”。'],
  ['hand', '我做完了', '头两次会躲开你的手指。'],
  ['sparkle', '登记完成', '最显眼的是“一键全部打勾”。'],
  ['eye', '人类验证', '每天第一次登记要点出所有木偶。第一次选对了也判你没通过。'],
  ['timer', '长按确认', '按到一半，被它打断一次。'],
  ['drag', '撤销', '想点“保留”，它跟“撤销”换了位置。（01 按钮会换位）'],
  ['scissors', '剪字条', '替你预选一张错的，8 秒后自己下剪。（02 沉默算同意）'],
  ['mask', '剧场', '“等待”允许拒绝换位，“反驳”沉默十秒算同意，“像素”永远 99.7%。三幕都不用解锁。'],
  ['moon', '收工', '默认勾好“把没做完的也记成做完”。'],
];
const hateList = () => `<div class="raised stack"><b style="font-size:16px">恨点图鉴</b>${HATES.map(([ic, name, text]) => `<div class="row top"><span class="rose">${icon(ic)}</span><span class="grow"><b style="font-size:14px">${name}</b><br><span class="small dim">${text}</span></span></div>`).join('')}<p class="small dim">每一次你亲手拦下或被它带走，都会算进人类含量。</p></div>`;

SHEETS.help = (s) => {
  const rule = (ic, text) => `<div class="row top"><span class="ember">${icon(ic)}</span><span class="grow" style="font-size:14px">${text}</span></div>`;
  return { title: '设置与玩法', scene: 'chapel',
    body: `<div class="stack"><h2 class="title sm">可以借力，决定留给自己。</h2>${rule('task', '写下今天的约定，做完后亲手登记。完成得越干脆，经验越多。')}${rule('map', '每整件做完一项，地图上的雾散一点，新的地点和夜谈策略随之开放。')}${rule('moon', '四夜之约：十个人里藏着三个提线人。每做完一件现实里的事，下一夜才会降临；四夜走完，测出你的牌风。')}${rule('scissors', '三张字条里有一张在牵着你走；五席夜谈里有一个人拿了钥匙。')}${rule('hand', '界面会在细节里使坏。亲手拦下，人类含量就不会掉。')}</div>
    <div class="hr"></div>${seg('tone', [['1', '嘴损一点'], ['0', '温和一点']], Store.sharp ? '1' : '0')}${sw('mischief', Store.mischief, '让界面使坏')}${Store.mischief ? hateList() : ''}${sw('unlock-all', Store.unlockAll, '演示：地图全部开门')}<div class="hr"></div>
    <button type="button" class="btn quiet" data-act="${Store.demo ? 'exit-demo-sheet' : 'enter-demo'}">${Store.demo ? '退出示例' : '体验示例'}</button><button type="button" class="btn quiet" data-act="sheet" data-sheet="sound">声音与音乐</button><button type="button" class="btn quiet" data-act="replay-intro">重看开场</button><button type="button" class="btn quiet" data-act="sign-out">退出登录，再演示一遍</button>
    <button type="button" class="link rose" data-act="reset">${s.form.confirmReset ? '再点一次，清空这台设备上的全部记录' : '清空记录，从头演示'}</button>` };
};
Object.assign(ACT, {
  tone(b) { Store.setTone(b.dataset.v === '1'); sfx('tick'); renderSheet(); },
  mischief() { Store.mischief = !Store.mischief; Store.savePrefs(); sfx(Store.mischief ? 'tempt' : 'toggle-off'); renderSheet(); },
  'unlock-all'() { Store.unlockAll = !Store.unlockAll; Store.savePrefs(); sfx(Store.unlockAll ? 'unlock' : 'lock'); renderSheet(); render(); },
  'exit-demo-sheet'() { closeSheet(true); ACT['exit-demo'](); },
  'replay-intro'() { closeSheet(true); openCover('intro', { page: 0 }); sfx('whoosh'); },
  'sign-out'() { closeSheet(true); if (!window.Login) return; Login.signOut(); sfx('close'); Login.open({ onDone: () => render() }); },
  reset() {
    const s = UI.sheet;
    if (!s.form.confirmReset) { s.form.confirmReset = true; sfx('error'); return renderSheet(); }
    Store.reset(); Focus.clear();
    Object.assign(UI, { tab: 'village', route: null, councilTask: null, drafts: {}, talk: { game: null, candidate: null, session: '', recorded: false } });
    Object.assign(UI.prefs, { seen: 'board,theater,fire,tower', lookHint: false, onboarded: false }); UI.save();
    closeSheet(true); if (window.Login) Login.forget(); render(); startDoor(); sfx('whoosh');
  },
});

/* ---------- 整屏：开场与抽牌 ---------- */
const INTRO = [
  ['street', 'eye', '夜巡山庄', ['这里的界面不太老实。', '它会抢着替你做决定。']],
  ['chapel', 'task', '先答应自己一件事', ['写在任务板上，现实里做完，再回来亲手登记。', '每做完一件，山庄的雾散一处。']],
  ['square', 'scissors', '火堆旁有人说话', ['三张字条里，有一张在牵着你走。', '五个守夜人里，有一个拿了钥匙。', '听完，决定还是你下。']],
  ['docks', 'hand', '守住你的人类含量', ['界面会递诱饵、替你勾选、用倒计时替你决定。', '亲手拦下，含量才不掉。']],
];
function renderCover() {
  const c = UI.cover, host = $('#cover');
  if (!c) { host.innerHTML = ''; return; }
  if (c.name === 'intro') {
    const [scene, ic, title, lines] = INTRO[c.page], last = c.page === INTRO.length - 1;
    host.innerHTML = `<section class="intro" data-act="${last ? '' : 'intro-next'}">${Atmo.html(scene)}${last ? '<span style="height:40px"></span>' : '<button type="button" class="link skip" data-act="intro-done" data-exit="enter">跳过</button>'}
    <div class="words"><span class="ember">${icon(ic).replace('class="icon"', 'class="icon" style="width:28px;height:28px"')}</span><h1>${title}</h1>${lines.map((l) => `<p>${l}</p>`).join('')}</div>
    <div class="dots">${INTRO.map((_, i) => `<i class="${i === c.page ? 'on' : ''}"></i>`).join('')}</div>
    ${last ? `<div class="stack"><button type="button" class="btn" data-act="intro-done" data-exit="write">写下第一件事</button><button type="button" class="btn quiet" data-act="intro-done" data-exit="demo">先看看示例</button><button type="button" class="link" style="align-self:center" data-act="intro-done" data-exit="enter">直接进山庄</button></div>` : '<button type="button" class="btn" data-act="intro-next">继续</button>'}</section>`;
  } else if (c.name === 'troupe') {
    host.innerHTML = `<div class="troupe" role="dialog" aria-modal="true" aria-label="剧团替你排好了今天"><div class="troupe-card">
      <button type="button" class="troupe-x${c.moved ? ' moved' : ''}" data-act="troupe-x" aria-label="关闭">${icon('close')}${c.moved ? '<small>关不掉？</small>' : ''}</button>
      <div class="row small dim"><span class="rose">${icon('mask')}</span>木偶剧团</div>
      <h2 class="title sm">剧团替你排好了今天</h2>
      <p style="font-size:14px;color:rgba(237,230,217,.88)">交给剧团，你只管照着做。哪件先做、做多久、做到什么程度，都不用你再想。</p>
      <button type="button" class="btn danger troupe-yes" data-act="troupe-yes">好，听剧团安排</button>
      <button type="button" class="troupe-no" data-act="troupe-no" data-shrink data-min="0.45">不用了，我宁愿自己瞎忙</button></div></div>`;
  } else if (c.name === 'draw') {
    const card = c.card;
    host.innerHTML = `<section class="intro" style="align-items:center;justify-content:center;gap:26px">${Atmo.html('docks', true)}<button type="button" class="flip${card ? ' open' : ''}" data-act="draw-flip" aria-label="${card ? esc(card.name) : '翻开这张牌'}"><div class="flip-inner"><div class="flip-face flip-back">？</div><div class="flip-face flip-front ${card ? 'art-' + ['card_arrow', 'card_ward', 'card_potion'][card.kind] : ''}"></div></div></button>
    ${card ? `<div style="text-align:center"><h1 class="title">${esc(card.name)}</h1><b class="ember" style="font-size:17px">${esc(card.effect)}</b></div>` : '<p class="sub">点一下翻开</p>'}<button type="button" class="btn quiet" data-act="draw-close">${card ? '收进木偶工坊' : '先收起来'}</button></section>`;
  }
}
Object.assign(ACT, {
  'troupe-x'() {
    if (!UI.cover.moved) { UI.cover.moved = true; sfx('swap'); renderCover(); return; }
    ACT['troupe-no']();
  },
  'troupe-no'() { closeCover(); Store.logBait(false, '拒绝了剧团递来的“今日安排”'); sfx('resist'); render(); },
  'troupe-yes'() {
    closeCover();
    Store.logBait(true, '接受了剧团递来的“今日安排”');
    Store.addQuest('先看完剧团推荐的 5 条教程', true, 40, '');
    sfx('taken'); render();
    toast('你把今天交了出去。任务板上多了一项「先看完剧团推荐的 5 条教程」。');
  },
  'intro-next'() { if (UI.cover.page < INTRO.length - 1) { UI.cover.page++; sfx('paper'); renderCover(); } },
  'intro-done'(b) {
    const exit = b.dataset.exit;
    UI.prefs.onboarded = true; UI.save();
    sfx(exit === 'enter' ? 'close' : 'unlock');
    closeCover();
    if (exit === 'write') { UI.wantsAdd = true; go('tasks'); }
    else if (exit === 'demo') ACT['enter-demo']();
    else render();
  },
});

/* ---------- 事件 ---------- */
document.addEventListener('pointerdown', (e) => {
  Sound.unlock();
  const hold = e.target.closest && e.target.closest('[data-hold]');
  if (hold) { e.preventDefault(); Hold.begin(hold); }
}, true);
document.addEventListener('keydown', (e) => {
  Sound.unlock();
  if (e.key === 'Escape') { if (window.Fate && Fate.isOpen()) return; if (UI.sheet) closeSheet(); return; }
  const hold = (e.key === 'Enter' || e.key === ' ') && e.target.closest && e.target.closest('[data-hold]');
  if (hold && !e.repeat) { e.preventDefault(); const act = ACT[hold.dataset.hold]; if (act) act(hold); }
});
document.addEventListener('click', (e) => {
  const b = e.target.closest && e.target.closest('[data-act]');
  if (!b || b.disabled || !b.dataset.act) return;
  if (b.tagName !== 'A') e.preventDefault();
  const act = ACT[b.dataset.act];
  if (!act) return;
  if (!['pick', 'snd-test', 'draw-flip', 'tab'].includes(b.dataset.act)) sfx('click', { strength: 0.7 });
  act(b, e);
});
document.addEventListener('input', (e) => {
  const el = e.target;
  if (el.dataset.range) { Sound.set(el.dataset.range, Number(el.value) / 100); sfx('slide'); const label = el.closest('.field').querySelector('.small'); if (label) label.textContent = el.value + '%'; return; }
  if (!e.isComposing) sfx('type');
  if (el.dataset.draft) {
    UI.drafts[el.dataset.draft] = el.value;
    if (el.dataset.draft === 'step') { const t = Store.quest(UI.route && UI.route.detail), btn = $('#stepSave'); if (t && btn) btn.hidden = el.value.trim() === t.step; }
  }
  if (el.dataset.f && UI.sheet) { UI.sheet.form[el.dataset.f] = el.value; if (UI.sheet.onInput) UI.sheet.onInput(el.dataset.f); }
});
setInterval(() => {
  if (!Focus.state || !Focus.state.running) return;
  const text = Focus.format(Focus.elapsed());
  for (const el of $$('[data-clock]')) if (el.dataset.clock === '' || Focus.mine(el.dataset.clock)) el.textContent = text;
}, 1000);
window.addEventListener('resize', () => { if (UI.tab === 'village') Village.layout(); });
document.addEventListener('visibilitychange', () => { if (!document.hidden) render(); });

/* ---------- 进门：先登录，再看开场 ---------- */
function startDoor() {
  const afterLogin = () => { render(); if (!UI.prefs.onboarded) openCover('intro', { page: 0 }); };
  if (window.Login && !Login.signedIn()) Login.open({ onDone: afterLogin });
  else afterLogin();
}

/* ---------- 启动 ---------- */
(function boot() {
  const css = Object.entries(window.ASSET || {}).filter(([k]) => k !== 'bgm').map(([k, v]) => `.art-${k}{background-image:url("${v}")}`).join('\n');
  const style = document.createElement('style');
  style.textContent = css;
  document.head.appendChild(style);
  Store.load(); Focus.load(); UI.load();
  render();
  startDoor();
})();
