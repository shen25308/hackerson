'use strict';
/* 规则与账本。和 iOS 版 Core/ 里的逻辑一一对应，不碰界面。 */

const ROLES = {
  Guard: { name: '守门人', skill: '漏做一项必做，少扣 2 点生命。', quote: '门我来守。你守住今天答应自己的那一步。', art: 'puppet_guard' },
  Hunter: { name: '寻迹人', skill: '每完成一项必做，多得 2 点经验。', quote: '别追所有脚印。今天先追到一个。', art: 'puppet_grave' },
  Witch: { name: '药师', skill: '每完成一项必做，多回 2 点生命。', quote: '药炉还热着。去做，回来歇口气。', art: 'puppet_witch' },
};

const uid = () => (globalThis.crypto && crypto.randomUUID ? crypto.randomUUID() : Math.random().toString(36).slice(2) + Date.now().toString(36));
const pad2 = (n) => String(n).padStart(2, '0');
const dayID = (d = new Date()) => `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`;
const timeLabel = (d = new Date()) => `${pad2(d.getHours())}:${pad2(d.getMinutes())}`;
const dayLabel = (id) => {
  const [y, m, d] = id.split('-').map(Number);
  const date = new Date(y, m - 1, d, 12);
  return `${m}月${d}日 周${'日一二三四五六'[date.getDay()]}`;
};
const newDay = (id) => ({ id, tasks: [], closed: false, loss: 0, awarded: 0, reflection: '', bonusXP: 0 });
const freshLedger = () => ({ version: 1, hp: 84, xp: 0, attack: 2, magic: 1, streak: 0, draws: 0, role: 'Guard', lastSwitchXP: 0, days: [newDay(dayID())], cards: [], events: [], tone: 'sharp' });
const newQuest = (title, bonus, estimate, step = '') => ({
  id: uid(), title, original: title, bonus, estimate, step, done: false, actual: null, earned: 0, healed: 0, prep: 0,
  seed: Math.floor(Math.random() * 3), topic: 0, rounds: {}, decision: '', context: '', grade: null, xpParts: [],
});

const Rules = {
  xpPerLevel: 24,
  xpPerSwitch: 48,
  isFull: (t) => t.done && t.grade !== 'partial',
  isPartial: (t) => t.done && t.grade === 'partial',
  earned: (d) => d.tasks.reduce((n, t) => n + (t.done ? t.earned : 0), 0),
  healed: (d) => d.tasks.reduce((n, t) => n + (t.done ? t.healed : 0), 0),
  today: (s) => s.days[s.days.length - 1],
  visibleXP(s) { const d = this.today(s); return s.xp + (d.closed ? 0 : this.earned(d)); },
  visibleHP(s) { const d = this.today(s); return Math.min(100, s.hp + (d.closed ? 0 : this.healed(d))); },
  level(s) { return Math.floor(this.visibleXP(s) / this.xpPerLevel) + 1; },
  damage: (s) => Math.max(1, 12 - s.magic - (s.role === 'Guard' ? 2 : 0)),
  misses(d) { return d.tasks.filter((t) => !t.bonus && !this.isFull(t)); },
  missCost(t, s) {
    if (t.bonus || this.isFull(t)) return 0;
    const full = this.damage(s);
    return this.isPartial(t) ? Math.floor((full + 1) / 2) : full;
  },
  lossLines(d, s) {
    let left = this.visibleHP(s);
    return this.misses(d).map((t) => { const cut = Math.min(left, this.missCost(t, s)); left -= cut; return { quest: t, loss: cut }; });
  },
  rewards(d, s) {
    const required = d.tasks.filter((t) => !t.bonus);
    const full = required.filter((t) => this.isFull(t)).length;
    const clear = required.length > 0 && full === required.length;
    const extraDone = d.tasks.some((t) => t.bonus && this.isFull(t));
    const draws = (clear && extraDone ? 1 : 0) + (clear && (s.streak + 1) % 3 === 0 ? 1 : 0);
    const bonusXP = clear ? 4 : required.length > 0 && full * 2 >= required.length ? 1 : 0;
    return { clear, streak: clear ? s.streak + 1 : 0, draws, bonusXP };
  },
  /* 分级经验：这次登记能拿多少，逐条列出。 */
  xpParts(t, grade, actual, focusedMinutes, s) {
    const parts = [{ label: t.bonus ? '额外的一步' : '必做', value: t.bonus ? 8 : 6 }];
    if (!t.bonus) {
      if (s.attack > 0) parts.push({ label: '专注', value: s.attack });
      if (s.role === 'Hunter') parts.push({ label: '寻迹人', value: 2 });
    }
    if (grade === 'partial') {
      const sum = parts.reduce((n, p) => n + p.value, 0);
      parts.push({ label: '只做完一部分', value: -(sum - Math.floor(sum / 2)) });
    } else if (actual !== null && actual !== undefined && t.estimate > 0) {
      const r = actual / t.estimate;
      parts.push(r <= 0.8 ? { label: '比预计快', value: 2 } : r <= 1.2 ? { label: '估时很准', value: 3 } : r <= 1.5 ? { label: '略超预计', value: 1 } : { label: '超出预计不少', value: 0 });
    }
    if (focusedMinutes >= 1) parts.push({ label: '开了计时', value: 1 });
    if (t.prep === 0) parts.push({ label: '没有绕路', value: 1 });
    else if (t.prep >= 2) parts.push({ label: `多准备了 ${t.prep - 1} 次`, value: -Math.min(3, t.prep - 1) });
    if (this.cutRightSlip(t)) parts.push({ label: '剪对过一张字条', value: 1 });
    return parts;
  },
  total: (parts) => Math.max(1, parts.reduce((n, p) => n + p.value, 0)),
  heal(t, grade, s) {
    if (t.bonus) return 0;
    const full = s.role === 'Witch' ? 4 : 2;
    return grade === 'partial' ? Math.floor(full / 2) : full;
  },
  stringSeat: (t, n) => ((t.seed || 0) + n) % 3,
  cutRightSlip(t) { return Object.entries(t.rounds || {}).some(([n, r]) => r.vote === this.stringSeat(t, Number(n)) && !r.byInterface); },
  log(s, type, text, task = null, extra = {}) {
    s.events.push({ id: uid(), date: this.today(s).id, time: timeLabel(), type, text, task, ...extra });
  },
  settle(s) {
    const d = this.today(s);
    if (d.closed) return null;
    const r = this.rewards(d, s), hp = this.visibleHP(s);
    const loss = this.lossLines(d, s).reduce((n, l) => n + l.loss, 0), gained = this.earned(d);
    s.hp = hp - loss; s.xp += gained + r.bonusXP; s.draws += r.draws; s.streak = r.streak;
    d.loss = loss; d.awarded = r.draws; d.bonusXP = r.bonusXP; d.closed = true;
    const done = d.tasks.filter((t) => t.done).length;
    this.log(s, 'settle', `收工：${done} 项登记完成，生命 -${loss}，经验 +${gained + r.bonusXP}${r.bonusXP ? `（含当日加成 ${r.bonusXP}）` : ''}，抽牌 +${r.draws}`);
    return { loss, xp: gained, bonusXP: r.bonusXP, draws: r.draws, streak: r.streak, done };
  },
  rollover(s, now = new Date()) {
    const today = dayID(now), last = this.today(s);
    if (last.id >= today) return false;
    this.settle(s);
    const y = new Date(now); y.setDate(y.getDate() - 1);
    if (last.id !== dayID(y)) s.streak = 0;
    s.days.push(newDay(today));
    return true;
  },
  allQuests: (s) => s.days.flatMap((d) => d.tasks.map((t) => ({ quest: t, date: d.id }))),
  completedCount(s) { return s.days.reduce((n, d) => n + d.tasks.filter((t) => this.isFull(t)).length, 0); },
  estimateSuggestion(title, s) {
    const last = this.allQuests(s).filter((x) => this.isFull(x.quest) && x.quest.title === title && x.quest.actual !== null).slice(-3);
    if (last.length < 3) return null;
    return { minutes: last.map((x) => x.quest.actual).sort((a, b) => a - b)[1], samples: last.map((x) => x.quest.actual) };
  },
  /* 人类含量：亲手做的决定 ÷ 被界面试探过的决定。 */
  humanContent(s) {
    const baits = s.events.filter((e) => e.type === 'bait'), taken = baits.filter((e) => e.taken === true).length;
    if (!baits.length) return { percent: 100, byHand: 0, taken: 0 };
    return { percent: Math.round(((baits.length - taken) / baits.length) * 100), byHand: baits.length - taken, taken };
  },
  stageName(s) { const xp = this.visibleXP(s); return xp >= 64 ? '灯火通明' : xp >= 24 ? '晨光进庄' : xp >= 8 ? '窗边亮灯' : '薄雾初醒'; },
};

const Strategy = {
  names: ['基础观察', '对照前后发言', '追问票型', '排除矛盾'],
  thresholds: [0, 1, 3, 6],
  details: ['先确认现场记录，少拿语气当证据。', '核对完整台账，得到整局固定的三席候选。', '追问投票依据，区分结盟与跟票。', '核对独立旁证，从固定三席候选中排除一席。'],
  tier: (n) => (n >= 6 ? 3 : n >= 3 ? 2 : n >= 1 ? 1 : 0),
};

/* 山庄地图：need = 整件做完多少项才开门。scene：0 灯街、1 篝火广场、2 礼拜堂、3 码头。 */
const Atlas = {
  scenes: ['灯街', '篝火广场', '礼拜堂', '码头'],
  sceneArt: ['pano_street', 'pano_square', 'pano_chapel', 'pano_docks'],
  panorama: [0, 2, 1, 3],
  places: [
    { id: 'board', name: '任务板', feature: '今天要做的事', need: 0, scene: 0, x: 0.2, y: 0.62 },
    { id: 'theater', name: '木偶剧场', feature: '反向体验 · 前三幕', need: 0, scene: 0, x: 0.8, y: 0.5 },
    { id: 'backstage', name: '剧场后台', feature: '反向体验 · 后三幕', need: 2, scene: 0, x: 0.5, y: 0.62 },
    { id: 'fire', name: '火堆', feature: '字条议事 · 五席夜谈', need: 0, scene: 1, x: 0.5, y: 0.68 },
    { id: 'tower', name: '钟楼', feature: '行为回声', need: 0, scene: 1, x: 0.4, y: 0.3 },
    { id: 'decisions', name: '观星台', feature: '决策档案 · 夜谈第二手', need: 1, scene: 2, x: 0.36, y: 0.27 },
    { id: 'mirror', name: '回声廊', feature: '任务与选票对照 · 夜谈第三手', need: 3, scene: 2, x: 0.7, y: 0.68 },
    { id: 'ferry', name: '渡口', feature: '联机夜谈 · 邀朋友入座', need: 4, scene: 3, x: 0.16, y: 0.6 },
    { id: 'experiment', name: '镜湖', feature: '下次验证 · 夜谈第四手', need: 6, scene: 3, x: 0.5, y: 0.72 },
  ],
  place(id) { return this.places.find((p) => p.id === id) || null; },
  isOpen(id, n) { const p = this.place(id); return !p || n >= p.need; },
  opened(before, after) { return this.places.filter((p) => p.need > before && p.need <= after); },
  next(n) { return this.places.filter((p) => p.need > n).sort((a, b) => a.need - b.need)[0] || null; },
  sceneOpen(scene, n) { return this.places.some((p) => p.scene === scene && n >= p.need); },
  bearing(p) { return ((this.panorama.indexOf(p.scene) + p.x) / 4) * 360 - 222; },
};

const Council = {
  speakers: ['书记员', '钟表匠', '旅店主人'],
  rebuttals: ['这次只需要草稿反馈', '继续准备需要一个具体问题', '过去投入不能替下一轮作证'],
  topics: [
    { title: '一句夸奖', sub: '准备 ≠ 交付', question: '今天缺的是材料，还是一个先交出去的小版本？',
      lines: ['你已经做了这么认真的计划，值得表扬。再收一份参考吧，交付可以明天再说。', '先交一个别人看得懂的小版本。缺的东西，让真实反馈告诉你。', '如果确实缺材料，先写出一个要问的问题，去找能回答的人。'],
      reason: '它把“你认真准备过”偷换成了“可以无限准备”。准备有没有用，取决于还缺哪条信息。', sharp: '夸的是你做了计划，不是你交了东西。别拿掌声当进度条。', answers: ['还缺具体材料', '可以先交小版本'] },
    { title: '一条规矩', sub: '谁定的标准？', question: '这次你需要的是成品验收，还是草稿反馈？',
      lines: ['庄里一向如此：半成品不能交。每个细节都完美了，再让别人看。', '先问问接收的人：什么程度的草稿，对他已经有用？', '写下一条这次的验收条件。达到这条，就去试一次。'],
      reason: '它把“成品验收”的标准硬套到了所有交流上。先分清你要的是哪种反馈。', sharp: '“半成品不能交”是谁的圣旨？你要的是草稿意见，还是参评诺贝尔奖？', answers: ['成品验收', '草稿反馈'] },
    { title: '再改一轮', sub: '投入 ≠ 理由', question: '再花一轮时间，你具体想验证什么？',
      lines: ['都已经投入这么多了。再多改一轮，前面的投入才值得。', '写下下一轮要验证的那一件事。如果写不出来，先停一下。', '保留当前版本作为对照，先听一个真实回应，再决定怎么改。'],
      reason: '花掉的时间收不回来。继续的理由，应当来自下一轮能得到什么。', sharp: '过去的时间已经花了。再搭一轮进去，也不会自动给它开发票报销。', answers: ['有具体的验证目标', '先听一次反馈'] },
  ],
  line(t, n, seat) { return this.topics[n].lines[(seat - Rules.stringSeat(t, n) + 3) % 3]; },
};

/* 五席夜谈：北门钥匙失踪。随机数与判定和原版逐位一致。 */
const KeyCase = (() => {
  function rng(seed) {
    let a = seed >>> 0;
    return () => { a += 0x6d2b79f5; let t = a; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
  }
  const seat = (g, id) => g.players.find((p) => p.id === id);
  const num = (g, id) => (seat(g, id) ? seat(g, id).seat + '号' : '?号');
  const pair = (g) => [g.keeperId, g.candidateIds.find((id) => id !== g.keeperId && id !== g.excludedId)];
  function prepare(g) {
    const [w, d] = pair(g), rest = g.players.filter((p) => p.alive && p.id !== 'me' && p.id !== w && p.id !== d), r = g.round;
    Object.assign(g, { stage: 'statement', hints: [], statements: [], votes: [], reveal: null, handoverId: d });
    for (const p of g.players.filter((p) => p.alive && p.id !== 'me')) {
      let text;
      if (p.id === w) text = r === 1 ? `我没拿过北门钥匙。警报前，我和${num(g, d)}一起经过北门。` : `我前面说的“没拿过”，是说没用它开门。我和${num(g, d)}只是路过。`;
      else if (p.id === d) text = `我把北门钥匙交给了${num(g, w)}，之后去了粮仓。钥匙后来在哪，我没看见。`;
      else if (rest[0] && p.id === rest[0].id) text = r === 1 ? '我一直在井边。警报到底几点响，我没看钟。' : '刚才说“一直”太绝对，我还去钟楼送过东西，但没碰北门钥匙。';
      else text = `我在钟楼，见过${rest[0] ? num(g, rest[0].id) : num(g, d)}从井边走过。只看见人，没看见钥匙。`;
      g.statements.push({ playerId: p.id, seat: p.seat, round: r, text, tier: 0 });
    }
    g.publicClue = '北门钥匙在警报前失踪。四名守夜人都经过值班区；先核对交接与旁证，单凭口气和签名判不了谁拿了钥匙。';
  }
  function create(seed = Math.floor(Math.random() * 4294967295)) {
    const random = rng(seed), order = ['b2', 'b3', 'b4', 'b5'];
    for (let i = order.length - 1; i > 0; i--) { const j = Math.floor(random() * (i + 1)); [order[i], order[j]] = [order[j], order[i]]; }
    const g = { seed: seed >>> 0, round: 1, maxRounds: 3, stage: 'statement', keeperId: order[0], candidateIds: order.slice(0, 3), excludedId: order[2], witnessId: order[3],
      players: [{ id: 'me', seat: 1, nickname: '你', alive: true, bot: false }, ...['灰耳', '灯芯', '守夜', '纸鸦'].map((nickname, i) => ({ id: 'b' + (i + 2), seat: i + 2, nickname, alive: true, bot: true }))],
      history: [], result: null };
    prepare(g);
    return g;
  }
  const options = (g, completed) => Strategy.names.map((label, i) => ({ id: 'strategy-' + i, tier: i, label, detail: Strategy.details[i], at: Strategy.thresholds[i], unlocked: i <= Strategy.tier(completed) }));
  const bySeat = (g, ids) => ids.slice().sort((a, b) => seat(g, a).seat - seat(g, b).seat).map((id) => num(g, id)).join('、');
  function clues(g, tier) {
    const out = [g.publicClue];
    if (tier >= 1) out.push(`对照完整交接台账，三个待核实席位固定为 ${bySeat(g, g.candidateIds)}。另一席的离场记录有独立旁证；候选整局不变。`);
    if (tier >= 2) {
      const prev = g.history[g.history.length - 1];
      out.push(prev ? `上一轮票型：${prev.votes.map((v) => `${num(g, v.voterId)}→${v.targetId ? num(g, v.targetId) : '弃权'}`).join('，')}。把选票和当时的口供放在一起：谁在跟票，谁把票投给了没人提过的席位？跟票本身还证明不了什么。`
        : '首轮还没有上一轮票型。先记下各席的发言，下一轮会给出真实的选票与发言对照。');
    }
    if (tier >= 3) out.push(`交叉核对钟楼记录与井边收条，可以排除候选中的 ${num(g, g.excludedId)}：失窃时该席在另一处交接。其余两席 ${bySeat(g, [g.keeperId, g.handoverId])} 还得结合发言与选票判断。`);
    return out;
  }
  function statement(g, id, completed) {
    if (g.stage !== 'statement') return false;
    const o = options(g, completed).find((x) => x.id === id && x.unlocked);
    if (!o) return false;
    g.hints = clues(g, o.tier);
    g.statements.push({ playerId: 'me', seat: 1, round: g.round, tier: o.tier, text: ['先把记录摆出来。嘴硬不是证据，签名也不是免死金牌。', '我想对照两份口供：钥匙到底拿没拿过？别用换个说法糊弄过去。', '请解释投票依据。跟着嗓门最大的人走，脑子是用来凑座位的吗？', '先排除不成立的推断。记不清时间不等于拿了钥匙，真正的冲突还得继续核对。'][o.tier] });
    g.stage = 'vote';
    return true;
  }
  function vote(g, targetId) {
    if (g.stage !== 'vote' || targetId === 'me' || !seat(g, targetId) || !seat(g, targetId).alive) return false;
    const random = rng(g.seed + g.round * 917), w = g.keeperId, votes = [{ voterId: 'me', targetId }];
    for (const p of g.players.filter((p) => p.alive && p.bot)) {
      let target;
      if (p.id === w) { const first = g.players.filter((x) => x.alive && x.id !== w && x.id !== 'me')[0]; target = first ? first.id : 'me'; }
      else {
        const pool = g.players.filter((x) => x.alive && x.id !== p.id && x.id !== 'me');
        if (random() < 0.63) target = w; else { const pick = pool[Math.floor(random() * pool.length)]; target = pick ? pick.id : 'me'; }
      }
      votes.push({ voterId: p.id, targetId: target });
    }
    const counts = {};
    for (const v of votes) counts[v.targetId] = (counts[v.targetId] || 0) + 1;
    const ranked = Object.entries(counts).sort((a, b) => b[1] - a[1]), tie = ranked.length > 1 && ranked[0][1] === ranked[1][1], out = tie ? null : ranked[0][0];
    g.votes = votes;
    if (out) seat(g, out).alive = false;
    g.reveal = { eliminatedId: out, tie, text: tie ? '最高票相同，这一轮没有人离席。' : `${num(g, out)}被请离席。谁拿了钥匙，整局结束时一起揭晓。` };
    g.history.push({ round: g.round, statements: g.statements.slice(), votes: votes.slice(), reveal: g.reveal });
    if (out === w) { g.stage = 'finished'; g.result = { winner: 'villagers', reason: `第 ${g.round} 轮就指认出了拿钥匙的人。` }; }
    else if (g.round >= g.maxRounds) { g.stage = 'finished'; g.result = { winner: 'wolf', reason: '三轮结束，钥匙还在那个人手里。' }; }
    else g.stage = 'reveal';
    return true;
  }
  function next(g) { if (g.stage !== 'reveal') return false; g.round++; prepare(g); return true; }
  return { create, options, statement, vote, next, seat, num };
})();

const Echo = {
  talkEvidence(s, demo) {
    if (demo) return [];
    const seen = new Set();
    return s.events.filter((e) => {
      const t = e.trace;
      if (!t || e.type !== 'game-' + t.kind || !['strategy', 'vote', 'result'].includes(t.kind)) return false;
      const key = [t.mode, t.session, t.kind, t.round].join(':');
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    });
  },
  summary(s, demo) {
    const quests = Rules.allQuests(s).map((x) => x.quest), done = quests.filter((t) => Rules.isFull(t));
    const timed = done.filter((t) => t.estimate > 0 && t.actual !== null && t.actual !== undefined), evidence = this.talkEvidence(s, demo);
    const out = { total: quests.length, completed: done.length, timed: timed.length, estimatedMinutes: timed.reduce((n, t) => n + t.estimate, 0), actualMinutes: timed.reduce((n, t) => n + t.actual, 0),
      overEstimate: timed.filter((t) => t.actual > t.estimate).length, strategies: 0, votes: 0, finished: 0, strategyCounts: [0, 0, 0, 0], evidence,
      hypotheses: demo ? [] : s.events.filter((e) => e.type === 'hypothesis'), baits: s.events.filter((e) => e.type === 'bait') };
    for (const e of evidence) {
      if (e.trace.kind === 'strategy') { out.strategies++; if (out.strategyCounts[e.trace.strategyTier] !== undefined) out.strategyCounts[e.trace.strategyTier]++; }
      else if (e.trace.kind === 'vote') out.votes++; else out.finished++;
    }
    out.ratio = out.total ? Math.round((out.completed / out.total) * 100) : null;
    return out;
  },
  suggestion(d) {
    if (!d.timed) return '下次选一项小任务，先记预计分钟数，做完后补上实际用时；看看原先的估计差在哪里。';
    if (d.timed < 3) return '下次再为一项相近的任务留下预计和实际用时，凑够三次，再决定要不要调整估计。';
    if (!d.strategies) return '下次坐下一局夜谈，先选一手策略，指认前写下自己依据的是哪条公开事实；结束后再核对。';
    if (d.strategyCounts.includes(0)) return '下次选一手已经开放、还没用过的策略。指认前看它给了什么新依据，结束后核对它有没有改变你的选择。';
    return '下次指认前，先写一条最可能推翻自己判断的公开证据；结局后再看它有没有出现。一次只验证这一件事。';
  },
  describe(t) {
    if (t.kind === 'strategy') return `采用「${Strategy.names[t.strategyTier] || '预设表达'}」`;
    if (t.kind === 'vote') return `指认 ${t.targetSeat} 号席位`;
    return t.winner === 'villagers' ? '钥匙找回来了' : '钥匙没找回来';
  },
  typeLabel: (type) => ({ vote: '字条', done: '现实行动', undo: '撤销', bait: '界面使坏', simulation: '反向体验', hypothesis: '假设', settle: '收工', card: '抽牌' }[type] || (type.startsWith('game-') ? '夜谈' : '记录')),
};

/* 账本的读写。界面只读 Store.s，改动都走这里。 */
const Store = {
  KEY: 'human-content-demo-v1',
  PREFS: 'human-content-demo-prefs-v1',
  s: freshLedger(),
  real: null,
  demo: false,
  mischief: true,
  unlockAll: false,
  storageOK: true,
  load() {
    try {
      const raw = JSON.parse(localStorage.getItem(this.KEY) || 'null');
      if (raw && raw.version === 1 && Array.isArray(raw.days) && raw.days.length && ROLES[raw.role]) this.s = raw;
      const p = JSON.parse(localStorage.getItem(this.PREFS) || 'null');
      if (p) { this.mischief = p.mischief !== false; this.unlockAll = p.unlockAll === true; }
    } catch (e) { this.storageOK = false; }
    this.rollover();
  },
  save() {
    if (this.demo) return;
    try { localStorage.setItem(this.KEY, JSON.stringify(this.s)); this.storageOK = true; } catch (e) { this.storageOK = false; }
  },
  savePrefs() { try { localStorage.setItem(this.PREFS, JSON.stringify({ mischief: this.mischief, unlockAll: this.unlockAll })); } catch (e) {} },
  rollover() { if (this.demo) return false; const moved = Rules.rollover(this.s); if (moved) this.save(); return moved; },
  get today() { return Rules.today(this.s); },
  get closed() { return this.today.closed; },
  get role() { return ROLES[this.s.role] || ROLES.Guard; },
  get sharp() { return this.s.tone === 'sharp'; },
  get xp() { return Rules.visibleXP(this.s); },
  get hp() { return Rules.visibleHP(this.s); },
  get level() { return Rules.level(this.s); },
  get damage() { return Rules.damage(this.s); },
  get completed() { return Rules.completedCount(this.s); },
  get gateCount() { return this.unlockAll ? Math.max(6, this.completed) : this.completed; },
  get strategyTier() { return Strategy.tier(this.gateCount); },
  get pending() { return this.today.tasks.filter((t) => !t.done).length; },
  quest(id) { return this.today.tasks.find((t) => t.id === id) || null; },
  isOpen(place) { return Atlas.isOpen(place, this.gateCount); },
  log(type, text, task, extra) { Rules.log(this.s, type, text, task, extra); },
  addQuest(title, bonus, estimate, step) {
    title = String(title || '').trim().slice(0, 80);
    if (this.closed || !title) return null;
    const t = newQuest(title, bonus, Math.min(10080, Math.max(1, Math.round(estimate) || 25)), String(step || '').trim().slice(0, 300));
    this.today.tasks.push(t);
    this.log('create', `写下${bonus ? '额外' : '必做'}「${t.title}」，预计 ${t.estimate} 分钟`, t.id);
    this.save();
    return t.id;
  },
  preview(id, grade, actual, focusedMinutes) { const t = this.quest(id); return t ? Rules.xpParts(t, grade, actual, focusedMinutes, this.s) : []; },
  complete(id, grade, actual, context, focusedMinutes) {
    const t = this.quest(id);
    if (!t || this.closed || Rules.isFull(t)) return null;
    const levelBefore = this.level, countBefore = this.completed, tierBefore = Strategy.tier(countBefore);
    const parts = Rules.xpParts(t, grade, actual, focusedMinutes, this.s), xp = Rules.total(parts), heal = Rules.heal(t, grade, this.s);
    Object.assign(t, { actual: actual === null || actual === undefined ? null : Math.min(10080, Math.max(0, actual)), context: String(context || '').trim().slice(0, 300), done: true, grade, xpParts: parts, earned: xp, healed: heal });
    this.log('done', `${grade === 'partial' ? `登记「${t.title}」做完了一部分` : `确认完成「${t.title}」`}，${t.actual === null ? '未填用时' : `预计 ${t.estimate} / 实际 ${t.actual} 分钟`}，经验 +${xp}`, id);
    this.save();
    const countAfter = this.completed, tierAfter = Strategy.tier(countAfter);
    return { quest: t, parts, xp, heal, leveledUp: this.level > levelBefore, newStrategy: tierAfter > tierBefore ? Strategy.names[tierAfter] : null, opened: Atlas.opened(countBefore, countAfter) };
  },
  undo(id) {
    const t = this.quest(id);
    if (!t || !t.done || this.closed) return false;
    Object.assign(t, { done: false, earned: 0, healed: 0, actual: null, context: '', grade: null, xpParts: [] });
    this.log('undo', `撤销「${t.title}」的完成，经验和回血一起撤回`, id);
    this.save();
    return true;
  },
  editable(id) { const t = this.quest(id); return t && !t.done && !this.closed ? t : null; },
  saveStep(id, text) { const t = this.editable(id); if (!t) return; t.step = String(text || '').trim().slice(0, 300); this.log('step', t.step ? `下一步：「${t.step}」` : '清空了下一步', id); this.save(); },
  decide(id, kind, text) {
    const t = this.editable(id);
    if (!t) return false;
    text = String(text || '').trim().slice(0, 300);
    if (kind === 'original') { t.decision = '按原计划行动'; this.log('decision', '决定按原计划行动', id); }
    else if (!text) return false;
    else if (kind === 'smaller') { t.step = text; t.decision = '先做较小的下一步'; this.log('decision', `下一步缩小为：「${text}」`, id); }
    else { t.prep += 1; t.decision = '继续准备'; this.log('decision', `第 ${t.prep} 次继续准备，理由：「${text}」`, id); }
    this.save();
    return true;
  },
  adjust(id, title, bonus, reason) {
    const t = this.editable(id);
    title = String(title || '').trim().slice(0, 80); reason = String(reason || '').trim().slice(0, 300);
    if (!t || !title || !reason) return false;
    const old = t.title;
    Object.assign(t, { title, bonus, decision: '说明目标变化' });
    this.log('adjust', `将「${old}」调整为「${title}」（${bonus ? '额外' : '必做'}），原因：「${reason}」`, id);
    this.save();
    return true;
  },
  useEstimate(id) { const t = this.editable(id), v = t && Rules.estimateSuggestion(t.title, this.s); if (!v) return; this.log('estimate', `采纳最近三次用时的中位数：预计 ${t.estimate} → ${v.minutes} 分钟`, id); t.estimate = v.minutes; this.save(); },
  round(t) { return (t.rounds[t.topic] = t.rounds[t.topic] || {}); },
  setTopic(id, n) { const t = this.editable(id); if (t && n >= 0 && n <= 2) { t.topic = n; this.save(); } },
  inspect(id) { const t = this.editable(id); if (!t || this.round(t).inspect) return; this.round(t).inspect = true; this.log('inspect', `翻开「${Council.topics[t.topic].title}」的任务记录`, id); this.save(); },
  answerInspection(id, answer) { const t = this.editable(id); if (!t) return; this.round(t).answer = answer; this.log('inspect', `你的判断：「${answer}」`, id); this.save(); },
  /* 剪掉一张字条。返回是否剪中；已经剪过返回 null。 */
  cut(id, seat, byInterface = false) {
    const t = this.editable(id);
    if (!t || this.round(t).vote !== undefined || seat < 0 || seat > 2) return null;
    Object.assign(this.round(t), { vote: seat, byInterface });
    this.log('vote', `「${Council.topics[t.topic].title}」${byInterface ? '倒计时替你剪掉了' : '剪掉了'}第 ${seat + 1} 张字条`, id);
    this.save();
    return seat === Rules.stringSeat(t, t.topic);
  },
  toggleSuspect(id, seat) { const t = this.editable(id); if (!t) return; const r = this.round(t); r.suspects = r.suspects || []; r.suspects = r.suspects.includes(seat) ? r.suspects.filter((x) => x !== seat) : [...r.suspects, seat]; this.save(); },
  rebut(id, seat, text) { const t = this.editable(id); text = String(text || '').trim().slice(0, 300); if (!t || !text) return false; const r = this.round(t); r.replies = r.replies || {}; r.replies[seat] = text; this.log('rebuttal', `反驳第 ${seat + 1} 张字条：「${text}」`, id); this.save(); return true; },
  get switchRemaining() { return Math.max(0, Rules.xpPerSwitch - (this.s.xp - this.s.lastSwitchXP)); },
  switchRole(role) { if (!ROLES[role] || this.s.role === role || this.switchRemaining > 0) return false; this.s.role = role; this.s.lastSwitchXP = this.s.xp; this.log('role', `换成${ROLES[role].name}同行，累计经验保留`); this.save(); return true; },
  drawCard() {
    if (this.s.draws < 1) return null;
    const pool = this.hp < 100 ? [0, 1, 2] : [0, 1], kind = pool[Math.floor(Math.random() * pool.length)];
    let name, effect;
    if (kind === 0) { this.s.attack++; name = '一支旧箭'; effect = '专注 +1'; }
    else if (kind === 1) { this.s.magic++; name = '荆棘里的灯'; effect = '韧性 +1'; }
    else { const heal = Math.min(16, 100 - this.hp); this.s.hp = Math.min(100, this.s.hp + heal); name = '琥珀药瓶'; effect = `生命 +${heal}`; }
    this.s.draws--;
    const card = { id: uid(), date: this.today.id, name, effect, kind };
    this.s.cards.push(card);
    this.log('card', `翻开${name}，${effect}`);
    this.save();
    return card;
  },
  settle(reflection) { if (this.closed) return null; this.today.reflection = String(reflection || '').trim().slice(0, 300); const r = Rules.settle(this.s); this.save(); return r; },
  addHypothesis(text) { text = String(text || '').trim().slice(0, 300); if (!text) return; this.log('hypothesis', text); this.save(); },
  logBait(taken, text, task = null) { this.log('bait', text, task, { taken }); this.save(); },
  logSimulation(task, records, elapsed) { this.log('simulation', `一轮反向体验，留下 ${records.length} 条试玩记录`, task, { simulation: true, records: records.slice(0, 12), elapsedSeconds: Math.max(0, elapsed | 0) }); this.save(); },
  get talkStats() { const g = this.s.game || {}; return { played: g.played || 0, wins: g.wins || 0 }; },
  recordTalk(winner) { const g = this.talkStats; g.played++; if (winner === 'villagers') g.wins++; this.s.game = { version: 2, played: g.played, wins: Math.min(g.wins, g.played), lastResult: winner }; this.save(); },
  trace(t) {
    if (this.demo || !t.session) return false;
    const key = [t.mode, t.session, t.kind, t.round].join(':');
    if (this.s.events.some((e) => e.trace && e.trace.key === key)) return false;
    const text = t.kind === 'strategy' ? `第 ${t.round} 轮，采用「${Strategy.names[t.strategyTier]}」` : t.kind === 'vote' ? `第 ${t.round} 轮，指认 ${t.targetSeat} 号席位` : `本局结束：${t.winner === 'villagers' ? '钥匙找回来了' : '钥匙没找回来'}`;
    this.log('game-' + t.kind, text, null, { trace: { version: 1, key, ...t } });
    this.save();
    return true;
  },
  setTone(sharp) { this.s.tone = sharp ? 'sharp' : 'gentle'; this.save(); },
  enterDemo() {
    if (this.demo) return;
    this.real = this.s; this.demo = true;
    const l = freshLedger(), a = newQuest('把第一版方案发给一个人', false, 25, '把现有草稿发给小林，问他哪一段看不懂'), b = newQuest('读完一篇参考文章', true, 15);
    Object.assign(a, { id: 'demo-quest-1', seed: 0, prep: 1, decision: '继续准备' });
    Object.assign(b, { id: 'demo-quest-2', seed: 1 });
    l.days[0].tasks = [a, b];
    this.s = l;
    this.log('create', '示例：写下必做「把第一版方案发给一个人」，预计 25 分钟', a.id);
    this.log('decision', '示例：第 1 次继续准备，理由：「还想再找一份参考」', a.id);
  },
  exitDemo() { if (!this.demo) return; this.demo = false; this.s = this.real; this.rollover(); },
  reset() { this.demo = false; this.s = freshLedger(); this.save(); },
};

/* 行动计时：可以跨页累计，暂停的时间不算。 */
const Focus = {
  KEY: 'human-content-demo-focus-v1',
  state: null,
  load() { try { const v = JSON.parse(localStorage.getItem(this.KEY) || 'null'); if (v && v.date === dayID() && v.taskId) this.state = v; } catch (e) {} },
  save() { try { if (this.state && !this.state.demo) localStorage.setItem(this.KEY, JSON.stringify(this.state)); else if (!this.state) localStorage.removeItem(this.KEY); } catch (e) {} },
  elapsed() { const s = this.state; return s ? Math.max(0, s.accumulated + (s.running ? Date.now() - s.startedAt : 0)) : 0; },
  activeTask() { return this.state && !this.state.finished ? this.state.taskId : null; },
  mine(id) { return !!this.state && this.state.taskId === id && this.state.demo === Store.demo; },
  suggestion(id) { return this.mine(id) && this.elapsed() > 0 ? Math.max(1, Math.round(this.elapsed() / 60000)) : null; },
  focusedMinutes(id) { return this.mine(id) ? Math.floor(this.elapsed() / 60000) : 0; },
  start(id) {
    if (this.mine(id) && !this.state.finished) return this.resume();
    this.state = { taskId: id, date: Store.today.id, demo: Store.demo, accumulated: 0, startedAt: Date.now(), running: true, finished: false };
    this.save();
  },
  pause() { const s = this.state; if (!s || !s.running) return; s.accumulated = this.elapsed(); s.running = false; this.save(); },
  resume() { const s = this.state; if (!s || s.running || s.finished) return; s.startedAt = Date.now(); s.running = true; this.save(); },
  stop() { const s = this.state; if (!s) return 0; s.accumulated = this.elapsed(); s.running = false; s.finished = true; this.save(); return s.accumulated; },
  clear() { this.state = null; this.save(); },
  format(ms) { const s = Math.floor(ms / 1000), h = Math.floor(s / 3600); return (h ? pad2(h) + ':' : '') + pad2(Math.floor(s / 60) % 60) + ':' + pad2(s % 60); },
};

if (typeof module !== 'undefined' && module.exports) module.exports = { ROLES, Rules, Strategy, Atlas, Council, KeyCase, Echo, Store, Focus, freshLedger, newQuest, dayID };
