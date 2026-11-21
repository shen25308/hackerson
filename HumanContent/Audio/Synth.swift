import Foundation

/// 所有音效都是现算出来的波形，不带任何音频文件。
/// 这里只做数学：把一个音效渲染成一段立体声采样。播放在 SoundEngine 里。
enum Wave {
    case sine
    case triangle
}

enum Cue: String, CaseIterable {
    // 界面
    case hover, click, type, open, close, nav, tick, slide, paper, whoosh
    case toggleOn = "toggle-on"
    case toggleOff = "toggle-off"
    // 议事与夜谈
    case scan, vote, snip, stamp
    case revealSuccess = "reveal-success"
    case revealWrong = "reveal-wrong"
    // 行动
    case pin, undo, heal, hold
    case taskComplete = "task-complete"
    case focusStart = "focus-start"
    case focusPause = "focus-pause"
    case focusEnd = "focus-end"
    // 成长
    case xp, levelup, streak, unlock, lock
    // 抽牌
    case drawShuffle = "draw-shuffle"
    case drawReveal = "draw-reveal"
    // 收工
    case settleSafe = "settle-safe"
    case damage, error
    // 界面使坏
    case tempt, resist, taken
    // 反向体验
    case countdown, takeover, collect, swap, glitch, retry, fire, reject, accept

    var label: String {
        switch self {
        case .hover: return "掠过"
        case .click: return "点按"
        case .type: return "输入"
        case .open: return "打开面板"
        case .close: return "关闭面板"
        case .nav: return "换页"
        case .tick: return "刻度"
        case .slide: return "滑杆"
        case .paper: return "翻纸"
        case .whoosh: return "掠过山庄"
        case .toggleOn: return "打开开关"
        case .toggleOff: return "关上开关"
        case .scan: return "翻查记录"
        case .vote: return "落下选票"
        case .snip: return "剪字条"
        case .stamp: return "盖章"
        case .revealSuccess: return "剪对了"
        case .revealWrong: return "剪错了"
        case .pin: return "钉上任务板"
        case .undo: return "撤销"
        case .heal: return "回血"
        case .hold: return "长按确认"
        case .taskComplete: return "行动完成"
        case .focusStart: return "开始计时"
        case .focusPause: return "暂停计时"
        case .focusEnd: return "计时结束"
        case .xp: return "经验入账"
        case .levelup: return "升级"
        case .streak: return "连续达成"
        case .unlock: return "迷雾散开"
        case .lock: return "门没开"
        case .drawShuffle: return "洗牌"
        case .drawReveal: return "翻开一张牌"
        case .settleSafe: return "平安收工"
        case .damage: return "漏项扣血"
        case .error: return "条件未满足"
        case .tempt: return "界面递来诱饵"
        case .resist: return "亲手拦下"
        case .taken: return "被界面带走"
        case .countdown: return "倒计时"
        case .takeover: return "AI 接管"
        case .collect: return "收藏"
        case .swap: return "选项换位"
        case .glitch: return "界面故障"
        case .retry: return "再试一次"
        case .fire: return "发射"
        case .reject: return "拒绝"
        case .accept: return "采纳"
        }
    }

    /// 同一个音效两次播放之间的最短间隔（秒）。
    var wait: Double {
        switch self {
        case .type, .slide, .tick: return 0.04
        case .hover, .click: return 0.05
        case .open, .close, .nav, .xp, .collect, .paper: return 0.09
        case .hold: return 0.06
        case .scan, .taskComplete: return 0.35
        case .revealSuccess, .revealWrong, .drawReveal, .levelup, .focusEnd, .takeover, .unlock: return 0.55
        case .drawShuffle, .settleSafe, .damage: return 0.45
        default: return 0.16
        }
    }
}

struct StereoBuffer {
    var left: [Float]
    var right: [Float]
    var sampleRate: Double
    var duration: Double { Double(left.count) / sampleRate }
    var peak: Float { max(left.map { abs($0) }.max() ?? 0, right.map { abs($0) }.max() ?? 0) }
}

/// 二阶滤波器（RBJ 公式，取值方式与 WebAudio 的 BiquadFilterNode 相同）。
struct Biquad {
    var b0 = 1.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0
    var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

    static func bandpass(_ hz: Double, q: Double, sampleRate: Double) -> Biquad {
        let w = 2 * Double.pi * min(hz, sampleRate * 0.49) / sampleRate
        let alpha = sin(w) / (2 * max(0.0001, q))
        let a0 = 1 + alpha
        return Biquad(b0: alpha / a0, b1: 0, b2: -alpha / a0, a1: -2 * cos(w) / a0, a2: (1 - alpha) / a0)
    }

    /// WebAudio 的低通里 Q 以分贝计。
    static func lowpass(_ hz: Double, qDB: Double, sampleRate: Double) -> Biquad {
        let w = 2 * Double.pi * min(hz, sampleRate * 0.49) / sampleRate
        let alpha = sin(w) / (2 * pow(10, qDB / 20))
        let c = cos(w), a0 = 1 + alpha
        return Biquad(b0: (1 - c) / 2 / a0, b1: (1 - c) / a0, b2: (1 - c) / 2 / a0, a1: -2 * c / a0, a2: (1 - alpha) / a0)
    }

    mutating func process(_ x: Double) -> Double {
        let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1
        x1 = x
        y2 = y1
        y1 = y
        return y
    }
}

struct Renderer {
    let sampleRate: Double
    /// 所有音高的倍率，用来做“越按越高”这类变化。
    var pitch = 1.0
    private var left: [Double] = []
    private var right: [Double] = []
    private var seed: UInt64 = 0x9E37_79B9_7F4A_7C15

    init(sampleRate: Double = 44100, pitch: Double = 1) {
        self.sampleRate = sampleRate
        self.pitch = pitch
    }

    private mutating func reserve(until end: Double) {
        let n = Int((end + 0.02) * sampleRate) + 1
        if left.count < n {
            left.append(contentsOf: repeatElement(0, count: n - left.count))
            right.append(contentsOf: repeatElement(0, count: n - right.count))
        }
    }

    private mutating func white() -> Double {
        seed ^= seed << 13
        seed ^= seed >> 7
        seed ^= seed << 17
        return (Double(seed >> 11) / Double(1 << 53) * 2 - 1) * 0.7
    }

    /// 先指数上升到峰值，再指数衰减到几乎无声。
    private func envelope(_ t: Double, attack: Double, duration: Double, peak: Double) -> Double {
        let floor = 0.0001
        if t < attack { return floor * pow(peak / floor, t / attack) }
        let tail = max(0.0001, duration - attack)
        return peak * pow(floor / peak, min(1, (t - attack) / tail))
    }

    /// 一个音：频率、起始延迟、时长、音量、波形、滑向的终点频率、声像。
    mutating func tone(_ freq: Double, _ delay: Double = 0, _ length: Double = 0.1, _ level: Double = 0.06,
                       _ wave: Wave = .sine, to: Double = 0, pan: Double = 0) {
        let duration = max(0.018, length)
        let f0 = min(4200, max(35, freq * pitch))
        let f1 = to > 0 ? min(4200, max(35, to * pitch)) : f0
        let peak = max(0.0002, level)
        let attack = min(0.012, duration * 0.22)
        let start = Int(max(0, delay) * sampleRate), count = Int(duration * sampleRate)
        reserve(until: max(0, delay) + duration)
        var gl = 1.0, gr = 1.0
        if pan != 0 {
            let x = (min(0.65, max(-0.65, pan)) + 1) / 2
            gl = cos(x * Double.pi / 2)
            gr = sin(x * Double.pi / 2)
        }
        var phase = 0.0
        for i in 0..<count {
            let t = Double(i) / sampleRate
            let f = f1 == f0 ? f0 : f0 * pow(f1 / f0, t / duration)
            phase += f / sampleRate
            if phase >= 1 { phase -= 1 }
            let s: Double
            switch wave {
            case .sine: s = sin(2 * Double.pi * phase)
            case .triangle: s = 1 - 4 * abs(phase - 0.5)
            }
            let v = s * envelope(t, attack: attack, duration: duration, peak: peak)
            left[start + i] += v * gl
            right[start + i] += v * gr
        }
    }

    /// 一小段滤过的噪声：起始延迟、时长、音量、滤波中心频率。
    mutating func noise(_ delay: Double = 0, _ length: Double = 0.06, _ level: Double = 0.025,
                        _ hz: Double = 1500, lowpass: Bool = false) {
        let peak = max(0.0002, level)
        let attack = min(0.006, length * 0.2)
        let start = Int(max(0, delay) * sampleRate), count = Int(length * sampleRate)
        reserve(until: max(0, delay) + length)
        var filter = lowpass
            ? Biquad.lowpass(hz, qDB: 0.4, sampleRate: sampleRate)
            : Biquad.bandpass(hz, q: 0.65, sampleRate: sampleRate)
        for i in 0..<count {
            let t = Double(i) / sampleRate
            let v = filter.process(white()) * envelope(t, attack: attack, duration: length, peak: peak)
            left[start + i] += v
            right[start + i] += v
        }
    }

    /// 总线：增益 → 4.3 kHz 低通 → 补偿增益 → 软限幅。
    func finish() -> StereoBuffer {
        var l = Biquad.lowpass(4300, qDB: 0.3, sampleRate: sampleRate)
        var r = l
        let gain = 0.78 * 2.1
        let outL = left.map { Float(tanh(l.process($0) * gain)) }
        let outR = right.map { Float(tanh(r.process($0) * gain)) }
        return StereoBuffer(left: outL, right: outR, sampleRate: sampleRate)
    }
}

enum CueBook {
    static func render(_ cue: Cue, pitch: Double = 1, sampleRate: Double = 44100) -> StereoBuffer {
        var r = Renderer(sampleRate: sampleRate, pitch: pitch)
        write(cue, &r)
        return r.finish()
    }

    /// 低频环境声：两个低音加一点起伏，8 秒整循环。
    static func ambience(sampleRate: Double = 44100) -> StereoBuffer {
        let n = Int(8 * sampleRate)
        var filter = Biquad.lowpass(200, qDB: 0.3, sampleRate: sampleRate)
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / sampleRate
            let drone = sin(2 * Double.pi * 55 * t) + sin(2 * Double.pi * 82.5 * t)
            let swell = 0.032 + 0.006 * sin(2 * Double.pi * 0.125 * t)
            out[i] = Float(filter.process(drone) * swell * 0.45 * 2.1)
        }
        // 滤波器起振的头几毫秒淡入，避免循环接缝处有咔哒声。
        let fade = min(n, Int(0.02 * sampleRate))
        for i in 0..<fade { out[i] *= Float(i) / Float(fade) }
        return StereoBuffer(left: out, right: out, sampleRate: sampleRate)
    }

    private static func write(_ cue: Cue, _ r: inout Renderer) {
        switch cue {
        case .hover:
            r.tone(1120, 0, 0.033, 0.022, .sine, to: 980)
        case .type:
            r.noise(0, 0.018, 0.018, 1800)
            r.tone(720, 0, 0.023, 0.015, .triangle)
        case .click:
            r.tone(360, 0, 0.055, 0.065, .triangle, to: 250)
            r.tone(1010, 0.013, 0.038, 0.022)
            r.noise(0, 0.025, 0.02, 1700)
        case .open:
            r.tone(180, 0, 0.16, 0.052, .triangle, to: 480)
            r.tone(720, 0.07, 0.14, 0.035, .sine, to: 900)
            r.noise(0.012, 0.11, 0.024, 2200)
        case .close:
            r.tone(480, 0, 0.13, 0.045, .triangle, to: 180)
            r.tone(720, 0, 0.065, 0.02)
        case .nav:
            r.tone(330, 0, 0.08, 0.043, .triangle, to: 440, pan: -0.25)
            r.tone(660, 0.06, 0.11, 0.035, .sine, to: 720, pan: 0.25)
        case .tick:
            r.tone(1400, 0, 0.02, 0.02, .triangle)
            r.noise(0, 0.012, 0.012, 3000)
        case .slide:
            r.tone(900, 0, 0.018, 0.015)
        case .paper:
            r.noise(0, 0.12, 0.03, 1800)
            r.noise(0.05, 0.1, 0.02, 3200)
        case .whoosh:
            r.noise(0, 0.3, 0.035, 800)
            r.tone(200, 0, 0.3, 0.02, .sine, to: 900)
        case .toggleOn:
            r.tone(520, 0, 0.05, 0.035, .triangle, to: 700)
            r.tone(1040, 0.04, 0.06, 0.02)
        case .toggleOff:
            r.tone(700, 0, 0.05, 0.035, .triangle, to: 480)
            r.tone(350, 0.04, 0.07, 0.02)
        case .scan:
            r.tone(230, 0, 0.5, 0.035, .sine, to: 1450, pan: -0.15)
            for i in 0..<5 {
                let d = 0.065 + Double(i) * 0.075
                r.tone(600 + Double(i) * 150, d, 0.038, 0.028, .triangle, pan: Double(i - 2) * 0.18)
                r.noise(d, 0.022, 0.012, 2200)
            }
            r.tone(1175, 0.48, 0.12, 0.038)
            r.tone(1568, 0.53, 0.11, 0.022)
        case .vote:
            r.tone(115, 0, 0.13, 0.12, .sine, to: 58)
            r.noise(0, 0.075, 0.07, 1000)
            r.tone(392, 0.02, 0.14, 0.043, .triangle)
            r.tone(784, 0.07, 0.08, 0.026)
        case .snip:
            r.noise(0, 0.022, 0.05, 3400)
            r.noise(0.07, 0.03, 0.06, 2600)
            r.tone(1800, 0.07, 0.04, 0.02, .triangle, to: 900)
        case .stamp:
            r.noise(0, 0.06, 0.08, 500, lowpass: true)
            r.tone(90, 0, 0.14, 0.12, .sine, to: 50)
        case .revealSuccess:
            r.tone(130.81, 0, 0.21, 0.08, .triangle)
            r.noise(0.04, 0.1, 0.032, 1500)
            for (i, f) in [523.25, 659.25, 783.99, 1046.5].enumerated() {
                r.tone(f, 0.17 + Double(i) * 0.085, 0.27, 0.055, .triangle, pan: (Double(i) - 1.5) * 0.16)
            }
            r.tone(261.63, 0.2, 0.6, 0.06)
        case .revealWrong:
            r.tone(196, 0, 0.34, 0.067, .triangle, to: 146.83)
            r.tone(233.08, 0.08, 0.3, 0.035)
            r.noise(0.025, 0.15, 0.035, 820)
            r.tone(440, 0.31, 0.13, 0.027, .sine, to: 329.63)
        case .pin:
            r.noise(0, 0.03, 0.05, 2400)
            r.tone(160, 0, 0.07, 0.07, .sine, to: 90)
            r.tone(520, 0.01, 0.05, 0.02, .triangle)
        case .taskComplete:
            for (i, f) in [392, 523.25, 659.25, 783.99].enumerated() {
                r.tone(f, Double(i) * 0.065, 0.27, 0.052, .triangle, pan: (Double(i) - 1.5) * 0.17)
            }
            r.tone(130.81, 0, 0.36, 0.072)
            r.tone(1046.5, 0.27, 0.34, 0.035)
            r.noise(0.2, 0.1, 0.018, 2600)
        case .undo:
            for (i, f) in [659.25, 493.88, 329.63].enumerated() { r.tone(f, Double(i) * 0.065, 0.14, 0.044, .triangle) }
            r.noise(0.1, 0.09, 0.019, 1200)
        case .heal:
            for (i, f) in [523.25, 659.25, 880].enumerated() { r.tone(f, Double(i) * 0.07, 0.3, 0.035) }
        case .hold:
            r.tone(330, 0, 0.12, 0.026, .sine, to: 395)
            r.tone(660, 0.025, 0.08, 0.012)
        case .xp:
            r.tone(880, 0, 0.09, 0.038)
            r.tone(1318.51, 0.045, 0.14, 0.023)
        case .levelup:
            r.tone(130.81, 0, 0.82, 0.065)
            for (i, f) in [261.63, 329.63, 392, 523.25, 659.25, 783.99, 1046.5].enumerated() {
                r.tone(f, Double(i) * 0.072, 0.36, 0.043, .triangle, pan: Double(i % 3 - 1) * 0.25)
            }
            r.tone(523.25, 0.48, 0.65, 0.036)
            r.tone(659.25, 0.48, 0.65, 0.028)
            r.tone(783.99, 0.48, 0.65, 0.028)
            r.noise(0.38, 0.28, 0.025, 2800)
        case .streak:
            for (i, f) in [392, 523.25, 659.25, 783.99, 1046.5].enumerated() { r.tone(f, Double(i) * 0.05, 0.22, 0.04, .triangle) }
            r.tone(1318.51, 0.3, 0.4, 0.03)
        case .unlock:
            r.tone(196, 0, 0.5, 0.06, .triangle, to: 392)
            r.noise(0, 0.45, 0.03, 900)
            for (i, f) in [392, 493.88, 587.33, 783.99].enumerated() {
                r.tone(f, 0.22 + Double(i) * 0.09, 0.5, 0.045, .sine, pan: (Double(i) - 1.5) * 0.2)
            }
            r.tone(1567.98, 0.62, 0.5, 0.02)
        case .lock:
            r.tone(140, 0, 0.08, 0.08, .sine, to: 90)
            r.noise(0, 0.05, 0.05, 700)
            r.tone(110, 0.09, 0.1, 0.06, .sine, to: 70)
            r.noise(0.09, 0.05, 0.04, 600)
        case .drawShuffle:
            for (i, d) in [0, 0.065, 0.14, 0.23, 0.32, 0.41].enumerated() {
                r.noise(d, 0.045, 0.042, 850 + Double(i) * 240)
                r.tone(160 + Double(i) * 31, d, 0.036, 0.027, .triangle)
            }
            r.tone(110, 0.47, 0.18, 0.07, .sine, to: 75)
        case .drawReveal:
            r.tone(110, 0, 0.31, 0.067, .triangle, to: 440)
            r.noise(0.05, 0.29, 0.035, 2100)
            for (i, f) in [440, 554.37, 659.25, 880].enumerated() {
                r.tone(f, 0.18 + Double(i) * 0.065, 0.56, 0.044, .sine, pan: (Double(i) - 1.5) * 0.2)
            }
            r.tone(1760, 0.43, 0.38, 0.018)
        case .settleSafe:
            for (i, f) in [523.25, 392, 329.63, 261.63].enumerated() { r.tone(f, Double(i) * 0.12, 0.38, 0.045) }
            r.tone(130.81, 0.24, 0.72, 0.065)
            r.tone(196, 0.36, 0.65, 0.025)
        case .damage:
            r.tone(110, 0, 0.38, 0.13, .sine, to: 42)
            r.tone(65, 0.03, 0.27, 0.06, .triangle, to: 38)
            r.noise(0, 0.2, 0.09, 550, lowpass: true)
            r.noise(0.16, 0.15, 0.025, 920)
            r.tone(293.66, 0.05, 0.2, 0.025, .triangle, to: 146.83)
        case .error:
            r.tone(220, 0, 0.075, 0.04, .triangle)
            r.tone(174.61, 0.11, 0.1, 0.04, .triangle)
        case .focusStart:
            r.tone(220, 0, 0.23, 0.055, .triangle, to: 440)
            r.tone(660, 0.16, 0.29, 0.035)
            r.noise(0.03, 0.025, 0.018, 1200)
            r.noise(0.13, 0.025, 0.014, 1600)
        case .focusPause:
            r.tone(440, 0, 0.13, 0.037, .triangle, to: 330)
            r.tone(220, 0.075, 0.14, 0.025)
        case .focusEnd:
            for (i, f) in [523.25, 659.25, 783.99].enumerated() { r.tone(f, Double(i) * 0.17, 0.48, 0.042) }
            r.tone(261.63, 0.12, 0.8, 0.038)
            r.tone(1046.5, 0.51, 0.52, 0.025)
        case .tempt:
            r.tone(660, 0, 0.12, 0.03, .sine, to: 700)
            r.tone(830.61, 0.1, 0.16, 0.03, .sine, to: 880)
            r.tone(1244.5, 0.22, 0.2, 0.018)
        case .resist:
            r.tone(293.66, 0, 0.1, 0.05, .triangle)
            r.tone(440, 0.07, 0.12, 0.05, .triangle)
            r.tone(587.33, 0.14, 0.22, 0.045)
            r.noise(0, 0.03, 0.02, 2000)
        case .taken:
            r.tone(440, 0, 0.16, 0.045, .triangle, to: 311.13)
            r.tone(233.08, 0.12, 0.28, 0.05, .sine, to: 185)
            r.noise(0.02, 0.12, 0.03, 700)
        case .countdown:
            r.tone(740, 0, 0.058, 0.042, .triangle)
            r.tone(370, 0, 0.07, 0.025)
        case .takeover:
            r.tone(90, 0, 0.52, 0.09, .triangle, to: 460)
            r.noise(0.03, 0.24, 0.052, 1100)
            for (i, f) in [311.13, 415.3, 622.25].enumerated() {
                r.tone(f, 0.15 + Double(i) * 0.1, 0.3, 0.047, .triangle, to: f * 1.055, pan: Double(i - 1) * 0.3)
            }
            r.tone(155.56, 0.34, 0.46, 0.045)
        case .collect:
            r.noise(0, 0.025, 0.024, 1200)
            r.tone(587.33, 0, 0.105, 0.05, .triangle)
            r.tone(880, 0.035, 0.16, 0.025)
        case .swap:
            r.tone(360, 0, 0.09, 0.038, .triangle, to: 640, pan: -0.6)
            r.tone(640, 0.07, 0.1, 0.038, .triangle, to: 360, pan: 0.6)
        case .glitch:
            for (i, d) in [0, 0.042, 0.1, 0.16].enumerated() {
                r.noise(d, 0.027, 0.034, 900 + Double(i) * 360)
                r.tone(i % 2 == 1 ? 210 : 430, d, 0.024, 0.03, .triangle, pan: i % 2 == 1 ? -0.3 : 0.3)
            }
        case .retry:
            for (i, f) in [220, 293.66, 440].enumerated() { r.tone(f, Double(i) * 0.055, 0.12, 0.047, .triangle) }
            r.noise(0, 0.045, 0.016, 1700)
        case .fire:
            r.tone(180, 0, 0.15, 0.095, .sine, to: 44)
            r.tone(620, 0, 0.075, 0.035, .triangle, to: 160)
            r.noise(0, 0.095, 0.053, 1600)
        case .reject:
            r.tone(330, 0, 0.09, 0.04, .triangle)
            r.tone(440, 0.09, 0.17, 0.035, .triangle)
            r.noise(0, 0.035, 0.016, 1400)
        case .accept:
            r.tone(440, 0, 0.1, 0.035, .triangle)
            r.tone(330, 0.08, 0.17, 0.035)
            r.noise(0.06, 0.04, 0.018, 850)
        }
    }
}
