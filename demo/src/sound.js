'use strict';
/* 全部音效都由 WebAudio 现场合成，不带音频文件。和 iOS 版 Audio/Synth.swift 的曲谱一致。 */
const Sound = (() => {
  const AC = window.AudioContext || window.webkitAudioContext;
  const KEY = 'human-content-demo-audio-v1';
  const clamp = (n, lo, hi) => Math.min(hi, Math.max(lo, Number(n) || 0));
  const prefs = { enabled: true, volume: 0.5, ambience: false, music: true, musicVolume: 0.3 };
  try { Object.assign(prefs, JSON.parse(localStorage.getItem(KEY) || '{}')); } catch (e) {}
  let ctx = null, bus = null, out = null, noiseBuf = null, ambient = null, pitch = 1;
  const recent = new Map(), listeners = new Set();

  const WAIT = { type: 40, slide: 40, tick: 40, hover: 50, click: 50, open: 90, close: 90, nav: 90, xp: 90, collect: 90, paper: 90, hold: 60, scan: 350, 'task-complete': 350,
    'reveal-success': 550, 'reveal-wrong': 550, 'draw-reveal': 550, levelup: 550, 'focus-end': 550, takeover: 550, unlock: 550, 'draw-shuffle': 450, 'settle-safe': 450, damage: 450 };
  const LABEL = { pin: '钉上任务板', 'task-complete': '行动完成', xp: '经验入账', levelup: '升级', unlock: '迷雾散开', lock: '门没开', snip: '剪字条', scan: '翻查记录',
    'reveal-success': '剪对了', 'reveal-wrong': '剪错了', tempt: '界面递来诱饵', resist: '亲手拦下', taken: '被界面带走', 'draw-shuffle': '洗牌', 'draw-reveal': '翻开一张牌',
    damage: '漏项扣血', 'settle-safe': '平安收工', streak: '连续达成', takeover: 'AI 接管', collect: '收藏', glitch: '界面故障', countdown: '倒计时', fire: '发射', 'focus-end': '计时结束' };

  function save() { try { localStorage.setItem(KEY, JSON.stringify(prefs)); } catch (e) {} for (const f of listeners) f(prefs); }
  function level() { return prefs.enabled ? clamp(prefs.volume, 0, 1) * 1.1 : 0; }
  function init() {
    if (ctx || !AC) return !!ctx;
    try {
      ctx = new AC({ latencyHint: 'interactive' });
      bus = ctx.createGain(); bus.gain.value = 0.78;
      const lp = ctx.createBiquadFilter(); lp.type = 'lowpass'; lp.frequency.value = 4300; lp.Q.value = 0.3;
      const limiter = ctx.createDynamicsCompressor(); limiter.threshold.value = -19; limiter.knee.value = 19; limiter.ratio.value = 7; limiter.attack.value = 0.004; limiter.release.value = 0.13;
      out = ctx.createGain(); out.gain.value = level();
      bus.connect(lp); lp.connect(limiter); limiter.connect(out); out.connect(ctx.destination);
      noiseBuf = ctx.createBuffer(1, ctx.sampleRate, ctx.sampleRate);
      const data = noiseBuf.getChannelData(0);
      for (let i = 0; i < data.length; i++) data[i] = (Math.random() * 2 - 1) * 0.7;
      return true;
    } catch (e) { ctx = null; return false; }
  }
  /* 浏览器要求先有一次点按才能出声。 */
  function unlock() {
    if (!init()) return;
    if (ctx.state !== 'running') ctx.resume().then(() => { startAmbience(); Music.sync(); }).catch(() => {});
    else { startAmbience(); Music.sync(); }
  }
  function tone(freq, delay = 0, len = 0.1, amp = 0.06, type = 'sine', to = 0, pan = 0, strength = 1) {
    const t = ctx.currentTime + Math.max(0, delay), dur = Math.max(0.018, len), end = t + dur;
    const osc = ctx.createOscillator(), env = ctx.createGain();
    osc.type = type;
    osc.frequency.setValueAtTime(clamp(freq * pitch, 35, 4200), t);
    if (to) osc.frequency.exponentialRampToValueAtTime(clamp(to * pitch, 35, 4200), end);
    env.gain.setValueAtTime(0.0001, t);
    env.gain.exponentialRampToValueAtTime(Math.max(0.0002, amp * strength), t + Math.min(0.012, dur * 0.22));
    env.gain.exponentialRampToValueAtTime(0.0001, end);
    osc.connect(env);
    if (pan && ctx.createStereoPanner) { const p = ctx.createStereoPanner(); p.pan.value = clamp(pan, -0.65, 0.65); env.connect(p); p.connect(bus); } else env.connect(bus);
    osc.start(t); osc.stop(end + 0.02);
  }
  function noise(delay = 0, len = 0.06, amp = 0.025, hz = 1500, type = 'bandpass', strength = 1) {
    const t = ctx.currentTime + Math.max(0, delay), end = t + len;
    const src = ctx.createBufferSource(), f = ctx.createBiquadFilter(), env = ctx.createGain();
    src.buffer = noiseBuf; f.type = type; f.frequency.value = hz; f.Q.value = type === 'bandpass' ? 0.65 : 0.4;
    env.gain.setValueAtTime(0.0001, t);
    env.gain.exponentialRampToValueAtTime(Math.max(0.0002, amp * strength), t + Math.min(0.006, len * 0.2));
    env.gain.exponentialRampToValueAtTime(0.0001, end);
    src.connect(f); f.connect(env); env.connect(bus);
    src.start(t, Math.random() * Math.max(0.01, 1 - len)); src.stop(end + 0.02);
  }
  function play(name, o = {}) {
    if (!prefs.enabled || !ctx || ctx.state !== 'running') return false;
    const now = performance.now();
    if (!o.force && recent.has(name) && now - recent.get(name) < (WAIT[name] || 160)) return false;
    recent.set(name, now);
    const s = clamp(o.strength === undefined ? 1 : o.strength, 0.05, 1.2), d0 = clamp(o.delay || 0, 0, 3);
    pitch = clamp(o.pitch || 1, 0.5, 3);
    const T = (f, d = 0, len = 0.1, amp = 0.06, type = 'sine', to = 0, pan = 0) => tone(f, d0 + d, len, amp, type, to, pan, s);
    const N = (d = 0, len = 0.06, amp = 0.025, hz = 1500, type = 'bandpass') => noise(d0 + d, len, amp, hz, type, s);
    const tri = 'triangle';
    switch (name) {
      case 'hover': T(1120, 0, 0.033, 0.022, 'sine', 980); break;
      case 'type': N(0, 0.018, 0.018, 1800); T(720, 0, 0.023, 0.015, tri); break;
      case 'click': T(360, 0, 0.055, 0.065, tri, 250); T(1010, 0.013, 0.038, 0.022); N(0, 0.025, 0.02, 1700); break;
      case 'open': T(180, 0, 0.16, 0.052, tri, 480); T(720, 0.07, 0.14, 0.035, 'sine', 900); N(0.012, 0.11, 0.024, 2200); break;
      case 'close': T(480, 0, 0.13, 0.045, tri, 180); T(720, 0, 0.065, 0.02); break;
      case 'nav': T(330, 0, 0.08, 0.043, tri, 440, -0.25); T(660, 0.06, 0.11, 0.035, 'sine', 720, 0.25); break;
      case 'tick': T(1400, 0, 0.02, 0.02, tri); N(0, 0.012, 0.012, 3000); break;
      case 'slide': T(900, 0, 0.018, 0.015); break;
      case 'paper': N(0, 0.12, 0.03, 1800); N(0.05, 0.1, 0.02, 3200); break;
      case 'whoosh': N(0, 0.3, 0.035, 800); T(200, 0, 0.3, 0.02, 'sine', 900); break;
      case 'toggle-on': T(520, 0, 0.05, 0.035, tri, 700); T(1040, 0.04, 0.06, 0.02); break;
      case 'toggle-off': T(700, 0, 0.05, 0.035, tri, 480); T(350, 0.04, 0.07, 0.02); break;
      case 'scan': T(230, 0, 0.5, 0.035, 'sine', 1450, -0.15); for (let i = 0; i < 5; i++) { T(600 + i * 150, 0.065 + i * 0.075, 0.038, 0.028, tri, 0, (i - 2) * 0.18); N(0.065 + i * 0.075, 0.022, 0.012, 2200); } T(1175, 0.48, 0.12, 0.038); T(1568, 0.53, 0.11, 0.022); break;
      case 'vote': T(115, 0, 0.13, 0.12, 'sine', 58); N(0, 0.075, 0.07, 1000); T(392, 0.02, 0.14, 0.043, tri); T(784, 0.07, 0.08, 0.026); break;
      case 'snip': N(0, 0.022, 0.05, 3400); N(0.07, 0.03, 0.06, 2600); T(1800, 0.07, 0.04, 0.02, tri, 900); break;
      case 'stamp': N(0, 0.06, 0.08, 500, 'lowpass'); T(90, 0, 0.14, 0.12, 'sine', 50); break;
      case 'reveal-success': T(130.81, 0, 0.21, 0.08, tri); N(0.04, 0.1, 0.032, 1500); [523.25, 659.25, 783.99, 1046.5].forEach((f, i) => T(f, 0.17 + i * 0.085, 0.27, 0.055, tri, 0, (i - 1.5) * 0.16)); T(261.63, 0.2, 0.6, 0.06); break;
      case 'reveal-wrong': T(196, 0, 0.34, 0.067, tri, 146.83); T(233.08, 0.08, 0.3, 0.035); N(0.025, 0.15, 0.035, 820); T(440, 0.31, 0.13, 0.027, 'sine', 329.63); break;
      case 'pin': N(0, 0.03, 0.05, 2400); T(160, 0, 0.07, 0.07, 'sine', 90); T(520, 0.01, 0.05, 0.02, tri); break;
      case 'task-complete': [392, 523.25, 659.25, 783.99].forEach((f, i) => T(f, i * 0.065, 0.27, 0.052, tri, 0, (i - 1.5) * 0.17)); T(130.81, 0, 0.36, 0.072); T(1046.5, 0.27, 0.34, 0.035); N(0.2, 0.1, 0.018, 2600); break;
      case 'undo': [659.25, 493.88, 329.63].forEach((f, i) => T(f, i * 0.065, 0.14, 0.044, tri)); N(0.1, 0.09, 0.019, 1200); break;
      case 'heal': [523.25, 659.25, 880].forEach((f, i) => T(f, i * 0.07, 0.3, 0.035)); break;
      case 'hold': T(330, 0, 0.12, 0.026, 'sine', 395); T(660, 0.025, 0.08, 0.012); break;
      case 'xp': T(880, 0, 0.09, 0.038); T(1318.51, 0.045, 0.14, 0.023); break;
      case 'levelup': T(130.81, 0, 0.82, 0.065); [261.63, 329.63, 392, 523.25, 659.25, 783.99, 1046.5].forEach((f, i) => T(f, i * 0.072, 0.36, 0.043, tri, 0, ((i % 3) - 1) * 0.25)); T(523.25, 0.48, 0.65, 0.036); T(659.25, 0.48, 0.65, 0.028); T(783.99, 0.48, 0.65, 0.028); N(0.38, 0.28, 0.025, 2800); break;
      case 'streak': [392, 523.25, 659.25, 783.99, 1046.5].forEach((f, i) => T(f, i * 0.05, 0.22, 0.04, tri)); T(1318.51, 0.3, 0.4, 0.03); break;
      case 'unlock': T(196, 0, 0.5, 0.06, tri, 392); N(0, 0.45, 0.03, 900); [392, 493.88, 587.33, 783.99].forEach((f, i) => T(f, 0.22 + i * 0.09, 0.5, 0.045, 'sine', 0, (i - 1.5) * 0.2)); T(1567.98, 0.62, 0.5, 0.02); break;
      case 'lock': T(140, 0, 0.08, 0.08, 'sine', 90); N(0, 0.05, 0.05, 700); T(110, 0.09, 0.1, 0.06, 'sine', 70); N(0.09, 0.05, 0.04, 600); break;
      case 'draw-shuffle': [0, 0.065, 0.14, 0.23, 0.32, 0.41].forEach((d, i) => { N(d, 0.045, 0.042, 850 + i * 240); T(160 + i * 31, d, 0.036, 0.027, tri); }); T(110, 0.47, 0.18, 0.07, 'sine', 75); break;
      case 'draw-reveal': T(110, 0, 0.31, 0.067, tri, 440); N(0.05, 0.29, 0.035, 2100); [440, 554.37, 659.25, 880].forEach((f, i) => T(f, 0.18 + i * 0.065, 0.56, 0.044, 'sine', 0, (i - 1.5) * 0.2)); T(1760, 0.43, 0.38, 0.018); break;
      case 'settle-safe': [523.25, 392, 329.63, 261.63].forEach((f, i) => T(f, i * 0.12, 0.38, 0.045)); T(130.81, 0.24, 0.72, 0.065); T(196, 0.36, 0.65, 0.025); break;
      case 'damage': T(110, 0, 0.38, 0.13, 'sine', 42); T(65, 0.03, 0.27, 0.06, tri, 38); N(0, 0.2, 0.09, 550, 'lowpass'); N(0.16, 0.15, 0.025, 920); T(293.66, 0.05, 0.2, 0.025, tri, 146.83); break;
      case 'error': T(220, 0, 0.075, 0.04, tri); T(174.61, 0.11, 0.1, 0.04, tri); break;
      case 'focus-start': T(220, 0, 0.23, 0.055, tri, 440); T(660, 0.16, 0.29, 0.035); N(0.03, 0.025, 0.018, 1200); N(0.13, 0.025, 0.014, 1600); break;
      case 'focus-pause': T(440, 0, 0.13, 0.037, tri, 330); T(220, 0.075, 0.14, 0.025); break;
      case 'focus-end': [523.25, 659.25, 783.99].forEach((f, i) => T(f, i * 0.17, 0.48, 0.042)); T(261.63, 0.12, 0.8, 0.038); T(1046.5, 0.51, 0.52, 0.025); break;
      case 'tempt': T(660, 0, 0.12, 0.03, 'sine', 700); T(830.61, 0.1, 0.16, 0.03, 'sine', 880); T(1244.5, 0.22, 0.2, 0.018); break;
      case 'resist': T(293.66, 0, 0.1, 0.05, tri); T(440, 0.07, 0.12, 0.05, tri); T(587.33, 0.14, 0.22, 0.045); N(0, 0.03, 0.02, 2000); break;
      case 'taken': T(440, 0, 0.16, 0.045, tri, 311.13); T(233.08, 0.12, 0.28, 0.05, 'sine', 185); N(0.02, 0.12, 0.03, 700); break;
      case 'countdown': T(740, 0, 0.058, 0.042, tri); T(370, 0, 0.07, 0.025); break;
      case 'takeover': T(90, 0, 0.52, 0.09, tri, 460); N(0.03, 0.24, 0.052, 1100); [311.13, 415.3, 622.25].forEach((f, i) => T(f, 0.15 + i * 0.1, 0.3, 0.047, tri, f * 1.055, (i - 1) * 0.3)); T(155.56, 0.34, 0.46, 0.045); break;
      case 'collect': N(0, 0.025, 0.024, 1200); T(587.33, 0, 0.105, 0.05, tri); T(880, 0.035, 0.16, 0.025); break;
      case 'swap': T(360, 0, 0.09, 0.038, tri, 640, -0.6); T(640, 0.07, 0.1, 0.038, tri, 360, 0.6); break;
      case 'glitch': [0, 0.042, 0.1, 0.16].forEach((d, i) => { N(d, 0.027, 0.034, 900 + i * 360); T(i % 2 ? 210 : 430, d, 0.024, 0.03, tri, 0, i % 2 ? -0.3 : 0.3); }); break;
      case 'retry': [220, 293.66, 440].forEach((f, i) => T(f, i * 0.055, 0.12, 0.047, tri)); N(0, 0.045, 0.016, 1700); break;
      case 'fire': T(180, 0, 0.15, 0.095, 'sine', 44); T(620, 0, 0.075, 0.035, tri, 160); N(0, 0.095, 0.053, 1600); break;
      case 'reject': T(330, 0, 0.09, 0.04, tri); T(440, 0.09, 0.17, 0.035, tri); N(0, 0.035, 0.016, 1400); break;
      case 'accept': T(440, 0, 0.1, 0.035, tri); T(330, 0.08, 0.17, 0.035); N(0.06, 0.04, 0.018, 850); break;
      default: return false;
    }
    pitch = 1;
    return true;
  }
  function stopAmbience() {
    if (!ambient) return;
    const old = ambient; ambient = null;
    try { old.gain.gain.setTargetAtTime(0.0001, ctx.currentTime, 0.08); old.nodes.forEach((n) => n.stop(ctx.currentTime + 0.4)); } catch (e) {}
  }
  /* 低频环境声：两个低音加一点起伏。 */
  function startAmbience() {
    if (!ctx || ctx.state !== 'running' || !prefs.enabled || !prefs.ambience || ambient) return;
    try {
      const gain = ctx.createGain(), f = ctx.createBiquadFilter(), a = ctx.createOscillator(), b = ctx.createOscillator(), lfo = ctx.createOscillator(), depth = ctx.createGain();
      gain.gain.setValueAtTime(0.0001, ctx.currentTime); gain.gain.setTargetAtTime(0.05, ctx.currentTime, 0.8);
      f.type = 'lowpass'; f.frequency.value = 200; a.frequency.value = 55; b.frequency.value = 82.5; lfo.frequency.value = 0.125; depth.gain.value = 0.01;
      a.connect(f); b.connect(f); f.connect(gain); gain.connect(out); lfo.connect(depth); depth.connect(gain.gain);
      a.start(); b.start(); lfo.start();
      ambient = { gain, nodes: [a, b, lfo] };
    } catch (e) {}
  }
  function apply() { if (out) out.gain.setTargetAtTime(level(), ctx.currentTime, 0.02); }

  /* 背景音乐：自带一段 30 秒试听循环。 */
  const Music = {
    el: null,
    playing: false,
    ensure() {
      if (this.el || !window.ASSET || !ASSET.bgm) return !!this.el;
      this.el = new Audio(ASSET.bgm);
      this.el.loop = true;
      this.el.addEventListener('playing', () => { this.playing = true; save(); });
      this.el.addEventListener('pause', () => { this.playing = false; save(); });
      return true;
    },
    sync() {
      if (!this.ensure()) return;
      this.el.volume = clamp(prefs.musicVolume, 0, 1);
      if (prefs.enabled && prefs.music && !document.hidden) { const p = this.el.play(); if (p && p.catch) p.catch(() => {}); }
      else this.el.pause();
    },
  };
  document.addEventListener('visibilitychange', () => {
    if (document.hidden) { stopAmbience(); if (ctx) ctx.suspend().catch(() => {}); if (Music.el) Music.el.pause(); }
    else if (ctx) ctx.resume().then(() => { startAmbience(); Music.sync(); }).catch(() => {});
  });

  return {
    prefs, LABEL, unlock, play,
    get musicPlaying() { return Music.playing; },
    set(key, value) {
      prefs[key] = value;
      if (key === 'enabled' || key === 'volume') apply();
      if (key === 'enabled' || key === 'ambience') { if (prefs.enabled && prefs.ambience) startAmbience(); else stopAmbience(); }
      if (key === 'enabled' || key === 'music' || key === 'musicVolume') Music.sync();
      save();
    },
    subscribe(f) { listeners.add(f); return () => listeners.delete(f); },
  };
})();

/* 在任何地方播一个音效。 */
function sfx(name, opts) {
  try { return Sound.play(name, opts); } catch (e) { return false; }
}
