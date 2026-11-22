import Foundation
#if canImport(Combine)
import Combine
#endif

// 牌局 · 四夜之约。
// 十个人围桌，三个提线人藏在九位同伴里。你每一夜的抉择同时产生两个结果：
// 这一夜谁出事、谁被请出山庄（真的结算），以及你在 E/I · S/N · T/F · J/P 上往哪边偏。
// 所有文案都在 Resources/fate.json，iOS 与网页演示共用同一份。

// MARK: 数据

struct FateAxis: Codable, Equatable {
    let a: String
    let b: String
    let an: String
    let bn: String
    let q: String
    let ad: String
    let bd: String
}

struct FateNPC: Codable, Equatable {
    let n: String
    let t: String
}

struct FateOption: Codable, Equatable {
    let t: String
    let v: Int
    let r: String
    let fx: String?
}

struct FateCase: Codable, Equatable {
    let id: String
    let night: Int
    let kind: String
    let axis: String
    let text: String
    let ask: String
    let opts: [FateOption]
}

struct FateTie: Codable, Equatable {
    let text: String
    let ask: String
    let opts: [FateOption]
}

struct FateType: Codable, Equatable {
    let nick: String
    let stack: String
    let kin: String
    let drive: String
    let best: String
    let fear: String
}

struct FateFit: Codable, Equatable {
    let main: String
    let alt: [String]
    let why: String
}

struct FateFx: Codable, Equatable {
    let clue: String
    let doubt: Int?
    let noDeath: Bool?
}

struct FateLine: Codable, Equatable {
    let who: String
    let t: String
}

struct FateLines: Codable, Equatable {
    let opening: [String]
    let resume: String
    let night: String
    let dawnDeath: String
    let dawnSafe: String
    let exileHit: [String]
    let exileMiss: [String]
    let count: String
    let gate: String
    let finale: [String]
    let ties: String
}

struct FateData: Codable {
    let axes: [String: FateAxis]
    let axisOrder: [String]
    let roleLead: [String: String]
    let puppets: [String: String]
    let goodPuppets: [String]
    let pullerPuppets: [String]
    let npcs: [FateNPC]
    let cases: [FateCase]
    let tiebreak: [String: FateTie]
    let types: [String: FateType]
    let kinName: [String: String]
    let roleFit: [String: FateFit]
    let nightFx: [String: FateFx]
    let chatter: [String: [FateLine]]
    let lines: FateLines
    let nightNames: [String]
    let letters: [String]
    let note: String

    static func load(from url: URL) throws -> FateData {
        try JSONDecoder().decode(FateData.self, from: Data(contentsOf: url))
    }

    /// App 包里的 fate.json；读不到时给一份空但能用的数据，不崩溃。
    static let shared: FateData = {
        if let url = Bundle.main.url(forResource: "fate", withExtension: "json"), let data = try? load(from: url) {
            return data
        }
        return .empty
    }()

    static let empty = FateData(
        axes: [:], axisOrder: [], roleLead: [:], puppets: [:], goodPuppets: [], pullerPuppets: [], npcs: [],
        cases: [], tiebreak: [:], types: [:], kinName: [:], roleFit: [:], nightFx: [:], chatter: [:],
        lines: FateLines(opening: [], resume: "", night: "", dawnDeath: "", dawnSafe: "", exileHit: [], exileMiss: [],
                         count: "", gate: "", finale: [], ties: ""),
        nightNames: ["", "第一夜", "第二夜", "第三夜", "第四夜"], letters: ["甲", "乙", "丙", "丁"], note: "")

    var isUsable: Bool { cases.count == 12 && npcs.count >= 9 && !axisOrder.isEmpty }

    func caseFor(night: Int, kind: String) -> FateCase? {
        cases.first { $0.night == night && $0.kind == kind }
    }

    func puppetName(_ key: String) -> String { puppets[key] ?? key }

    func nightName(_ n: Int) -> String { nightNames.indices.contains(n) ? nightNames[n] : "第\(n)夜" }

    /// 套用旁白模板里的 {name} {n} {w} {night}。
    func fill(_ template: String, name: String = "", n: Int = 0, w: Int = 0, night: Int = 0) -> String {
        let numerals = ["", "一", "二", "三", "四", "五"]
        return template
            .replacingOccurrences(of: "{name}", with: name)
            .replacingOccurrences(of: "{n}", with: String(n))
            .replacingOccurrences(of: "{w}", with: String(w))
            .replacingOccurrences(of: "{night}", with: numerals.indices.contains(night) ? numerals[night] : String(night))
    }
}

// MARK: 随机数

/// 可复现的随机数（SplitMix64）。状态存在牌局里，读档后接着用同一串数。
struct FateRNG: RandomNumberGenerator {
    var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

// MARK: 牌局

struct FateSeat: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var tag: String
    /// 木偶的键（guard、wolfking…）；你自己的座位是同行角色的立绘键。
    var puppet: String
    /// 立绘图片名。
    var image: String
    var puller: Bool
    var me: Bool
    var alive = true
    var exiled = false
}

enum FatePhase: String, Codable, Equatable {
    case intro, nightAsk, dawn, dayAsk, vote, finale, ties, verdict
}

/// 天亮时发生的事，存下来以便读档后不重复结算。
struct FateDawn: Codable, Equatable {
    var victim: String?
    var clue: String
}

/// 请出山庄的结果。
struct FateExile: Codable, Equatable {
    var seat: String?
    var hit: Bool
}

struct FateResult: Codable, Equatable {
    var type: String
    /// 字母 → 百分比，每对加起来是 100。
    var pct: [String: Int]
    /// 维度 → 分数（−6…6）。
    var score: [String: Int]
    var typeInfo: FateType?
    var fit: FateFit?
    /// "good" = 守夜人胜；"puller" = 提线人胜。
    var win: String
    var rightVotes: Int
    var wrongVotes: Int
    var pullerNames: [String]
    var roleName: String
    var at: Date
}

struct FateGame: Codable, Equatable {
    var seats: [FateSeat] = []
    var role: String
    var night = 1
    var phase: FatePhase = .intro
    var doubt: [String: Int] = [:]
    var dead: [String] = []
    var exiled: [String] = []
    var rightVotes = 0
    var wrongVotes = 0
    var answers: [String: Int] = [:]
    var tiebreaks: [String: Int] = [:]
    var noDeath = false
    var nightClue = ""
    var lastDawn: FateDawn?
    var lastExile: FateExile?
    var finished = false
    var result: FateResult?
    var rngState: UInt64

    // MARK: 建局

    /// 你 + 九位同伴（三个提线人，六个守夜人）。你永远在守夜人这边。
    static func new(role: RoleID, data: FateData, seed: UInt64) -> FateGame {
        var rng = FateRNG(seed: seed)
        let info = ROLES[role] ?? ROLES[.gatekeeper]!
        var g = FateGame(role: role.rawValue, rngState: 0)
        let myKey = info.art.hasPrefix("puppet_") ? String(info.art.dropFirst(7)) : info.art
        g.seats = [FateSeat(id: "me", name: "你", tag: "", puppet: myKey, image: info.art, puller: false, me: true)]
        let npcs = Array(data.npcs.prefix(9)).shuffled(using: &rng)
        var goods = data.goodPuppets.shuffled(using: &rng)
        var pullers = data.pullerPuppets.shuffled(using: &rng)
        let pullerSlots = Set(Array(npcs.indices).shuffled(using: &rng).prefix(3))
        for (i, p) in npcs.enumerated() {
            let isPuller = pullerSlots.contains(i)
            let key: String
            if isPuller {
                key = pullers.isEmpty ? "wolf" : pullers.removeFirst()
            } else {
                key = goods.isEmpty ? "villager" : goods.removeFirst()
            }
            g.seats.append(FateSeat(id: "n\(i)", name: p.n, tag: p.t, puppet: key, image: "puppet_" + key, puller: isPuller, me: false))
        }
        // 可疑度：提线人起步 3，守夜人起步 2（与网页演示一致）。
        for s in g.seats { g.doubt[s.id] = s.puller ? 3 : 2 }
        g.rngState = rng.state
        return g
    }

    // MARK: 查询

    var me: FateSeat? { seats.first { $0.me } }
    func seat(_ id: String?) -> FateSeat? { seats.first { $0.id == id } }
    var aliveSeats: [FateSeat] { seats.filter(\.alive) }
    var pullersAlive: Int { seats.filter { $0.alive && $0.puller }.count }
    var keepersAlive: Int { seats.filter { $0.alive && !$0.puller }.count }
    var answered: Int { answers.count }

    /// 第 n 夜要整件做完多少项现实任务才会降临。
    static func need(forNight n: Int) -> Int { max(0, n - 1) }

    func canEnter(night n: Int, completed: Int) -> Bool { completed >= FateGame.need(forNight: n) }

    /// 下一夜开始前还差几件现实任务；不差或已经没有下一夜时返回 nil。
    func nextNightNeed(completed: Int) -> Int? {
        guard !finished else { return nil }
        let upcoming: Int
        switch phase {
        case .intro: upcoming = 1
        case .nightAsk: upcoming = night
        case .dawn, .dayAsk, .vote: upcoming = night + 1
        case .finale, .ties, .verdict: return nil
        }
        guard upcoming <= 4 else { return nil }
        let left = FateGame.need(forNight: upcoming) - completed
        return left > 0 ? left : nil
    }

    /// 接下来要开始的是第几夜（四夜都开始过了就是 nil）。
    var upcomingNight: Int? {
        guard !finished else { return nil }
        switch phase {
        case .intro: return 1
        case .nightAsk: return night
        case .dawn, .dayAsk, .vote: return night < 4 ? night + 1 : nil
        case .finale, .ties, .verdict: return nil
        }
    }

    /// 当前该问的题。
    func currentCase(_ data: FateData) -> FateCase? {
        switch phase {
        case .nightAsk: return data.caseFor(night: night, kind: "night")
        case .dayAsk: return data.caseFor(night: night, kind: "say")
        case .vote: return data.caseFor(night: night, kind: "vote")
        default: return nil
        }
    }

    // MARK: 动作

    private mutating func random(_ upper: Int) -> Int {
        guard upper > 1 else { return 0 }
        var rng = FateRNG(seed: rngState)
        let v = Int.random(in: 0..<upper, using: &rng)
        rngState = rng.state
        return v
    }

    /// 记下一道题的回答。夜里的题当场生效（护住谁、改变谁的可疑度）。
    @discardableResult
    mutating func answer(_ c: FateCase, option index: Int, data: FateData) -> FateOption? {
        guard c.opts.indices.contains(index) else { return nil }
        let o = c.opts[index]
        answers[c.id] = o.v
        if c.kind == "night" { applyNight(o.fx, data: data) }
        return o
    }

    mutating func applyNight(_ code: String?, data: FateData) {
        noDeath = false
        nightClue = ""
        guard let code, let fx = data.nightFx[code] else { return }
        nightClue = fx.clue
        if fx.noDeath == true { noDeath = true }
        // 夜里查到的线索只会让还活着的提线人更可疑（或更不可疑）。
        if let d = fx.doubt, d != 0 {
            for s in seats where s.alive && s.puller {
                doubt[s.id] = max(0, min(9, (doubt[s.id] ?? 0) + d))
            }
        }
    }

    /// 天亮：提线人对最不被怀疑的三个守夜人之一下手（永远不会是你）。
    @discardableResult
    mutating func resolveNight() -> FateSeat? {
        let cands = seats.enumerated().filter { $0.element.alive && !$0.element.puller && !$0.element.me }
        guard !cands.isEmpty, !noDeath else { return nil }
        let sorted = cands.sorted { a, b in
            let da = doubt[a.element.id] ?? 0, db = doubt[b.element.id] ?? 0
            return da != db ? da < db : a.offset < b.offset
        }
        let pick = sorted[random(min(3, sorted.count))]
        seats[pick.offset].alive = false
        dead.append(pick.element.id)
        return seats[pick.offset]
    }

    /// 请一个人出山庄。每人一个带抖动的分数 = 可疑度 + 随机数×1.2，从高到低排：
    /// evidence 选最高的；heart 选最低的；instinct 随便选；其余（majority）选第二高的。
    @discardableResult
    mutating func resolveExile(strategy: String?) -> FateSeat? {
        let cands = seats.enumerated().filter { $0.element.alive && !$0.element.me }
        guard !cands.isEmpty else { return nil }
        var rng = FateRNG(seed: rngState)
        let scored = cands.map { c in
            (offset: c.offset, score: Double(doubt[c.element.id] ?? 0) + Double.random(in: 0..<1, using: &rng) * 1.2)
        }
        rngState = rng.state
        let byDoubt = scored.sorted { a, b in a.score != b.score ? a.score > b.score : a.offset < b.offset }
        let target: Int
        switch strategy {
        case "evidence":
            target = byDoubt[0].offset
        case "heart":
            target = byDoubt[byDoubt.count - 1].offset
        case "instinct":
            target = cands[random(cands.count)].offset
        default:
            target = byDoubt.count > 1 ? byDoubt[1].offset : byDoubt[0].offset
        }
        seats[target].alive = false
        seats[target].exiled = true
        exiled.append(seats[target].id)
        if seats[target].puller { rightVotes += 1 } else { wrongVotes += 1 }
        return seats[target]
    }

    // MARK: 计分

    func score(_ data: FateData) -> [String: Int] {
        var s: [String: Int] = [:]
        for k in data.axisOrder { s[k] = 0 }
        for c in data.cases { if let v = answers[c.id] { s[c.axis, default: 0] += v } }
        for (k, v) in tiebreaks { s[k, default: 0] += v }
        return s
    }

    /// 正好打平、需要追问的维度。
    func ties(_ data: FateData) -> [String] {
        let s = score(data)
        return data.axisOrder.filter { (s[$0] ?? 0) == 0 }
    }

    /// 四夜走完，算出结果。
    mutating func tally(_ data: FateData, now: Date = Date()) -> FateResult {
        let s = score(data)
        var pct: [String: Int] = [:]
        var letters = ""
        for k in data.axisOrder {
            guard let axis = data.axes[k] else { continue }
            let v = s[k] ?? 0
            let p = max(0, min(100, Int((Double(v + 6) / 12 * 100).rounded())))
            pct[axis.a] = p
            pct[axis.b] = 100 - p
            letters += v >= 0 ? axis.a : axis.b
        }
        let w = pullersAlive, g = keepersAlive
        let win = w == 0 ? "good" : (w >= g ? "puller" : "good")
        let roleName = (RoleID(rawValue: role).flatMap { ROLES[$0] } ?? ROLES[.gatekeeper]!).name
        let r = FateResult(type: letters, pct: pct, score: s, typeInfo: data.types[letters], fit: data.roleFit[letters], win: win,
                           rightVotes: rightVotes, wrongVotes: wrongVotes,
                           pullerNames: seats.filter(\.puller).map(\.name), roleName: roleName, at: now)
        result = r
        finished = true
        phase = .verdict
        return r
    }

    // MARK: 推进

    /// 这一步做完了，走到下一步。
    mutating func advance() {
        switch phase {
        case .intro:
            night = 1
            phase = .nightAsk
        case .nightAsk:
            phase = .dawn
        case .dawn:
            phase = .dayAsk
        case .dayAsk:
            phase = .vote
        case .vote:
            if night < 4 {
                night += 1
                phase = .nightAsk
            } else {
                phase = .finale
            }
        case .finale:
            phase = .ties
        case .ties, .verdict:
            break
        }
    }

    /// 天亮结算（结算与推进一起做完，读档后不会重复死人）。
    mutating func playDawn() -> FateDawn {
        let victim = resolveNight()
        let dawn = FateDawn(victim: victim?.id, clue: nightClue)
        lastDawn = dawn
        advance()
        return dawn
    }

    /// 投票：记下回答、请人出山庄、推进到下一步。
    mutating func playVote(_ c: FateCase, option index: Int, data: FateData) -> FateExile {
        let strategy = c.opts.indices.contains(index) ? c.opts[index].fx : nil
        answer(c, option: index, data: data)
        let out = resolveExile(strategy: strategy)
        let exile = FateExile(seat: out?.id, hit: out?.puller ?? false)
        lastExile = exile
        advance()
        return exile
    }

    /// 从同一池子里挑几句在场的人会说的话。
    mutating func chatter(_ pool: String, count: Int, data: FateData) -> [FateLine] {
        let alive = Set(seats.filter(\.alive).map(\.name))
        var bag = data.chatter[pool] ?? []
        var out: [FateLine] = []
        while !bag.isEmpty && out.count < count {
            let line = bag.remove(at: random(bag.count))
            if !line.who.isEmpty && !alive.contains(line.who) { continue }
            out.append(line)
        }
        return out
    }
}

extension FateLine {
    /// 舞台动作（括号开头）不加引号，说话加 名字：「…」。
    var spoken: String {
        if who.isEmpty { return t }
        if t.hasPrefix("（") { return who + t }
        return "\(who)：「\(t)」"
    }
}

// MARK: 存档

final class FateStore: ObservableObject {
    static let shared = FateStore()

    @Published var game: FateGame?
    @Published var last: FateResult?
    /// 下次打开牌桌时直接看结果，不开新局。
    @Published var wantsVerdict = false

    private let defaults: UserDefaults
    private let gameKey = "fate-v1"
    private let lastKey = "fate-last-v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let decoder = JSONDecoder()
        if let d = defaults.data(forKey: gameKey) { game = try? decoder.decode(FateGame.self, from: d) }
        if let d = defaults.data(forKey: lastKey) { last = try? decoder.decode(FateResult.self, from: d) }
    }

    /// 已经记下的抉择数（这一局）。
    var progress: Int { game.map { $0.finished ? 12 : $0.answered } ?? 0 }

    var inProgress: Bool { game.map { !$0.finished } ?? false }

    @discardableResult
    func newGame(role: RoleID, data: FateData = .shared, seed: UInt64 = UInt64.random(in: 1...UInt64.max)) -> FateGame {
        let g = FateGame.new(role: role, data: data, seed: seed)
        game = g
        save()
        return g
    }

    func update(_ g: FateGame) {
        game = g
        if g.finished, let r = g.result { last = r }
        save()
    }

    func save() {
        let encoder = JSONEncoder()
        if let game, let d = try? encoder.encode(game) { defaults.set(d, forKey: gameKey) } else { defaults.removeObject(forKey: gameKey) }
        if let last, let d = try? encoder.encode(last) { defaults.set(d, forKey: lastKey) } else { defaults.removeObject(forKey: lastKey) }
    }

    /// 清空这一局和上次的结果。
    func reset() {
        game = nil
        last = nil
        wantsVerdict = false
        save()
    }
}
