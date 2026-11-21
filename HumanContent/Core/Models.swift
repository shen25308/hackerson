import Foundation

// 存档沿用网页版的 JSON 结构（version 1），两边导出的备份可以互相导入。
// 这里手动读写字典，而不是用 Codable：网页端对 null / 缺省字段有严格区分。

typealias JSON = [String: Any]

enum J {
    /// JSON 里的 true/false。苹果平台上数字 0/1 也能转成 Bool，所以要看底层类型。
    static func isBool(_ v: Any?) -> Bool {
        guard let v else { return false }
        #if canImport(ObjectiveC)
        if let n = v as? NSNumber { return CFGetTypeID(n) == CFBooleanGetTypeID() }
        return false
        #else
        if let n = v as? NSNumber { return ObjectIdentifier(type(of: n)) == boolClass }
        return v is Bool
        #endif
    }
    #if !canImport(ObjectiveC)
    private static let boolClass = ObjectIdentifier(type(of: NSNumber(value: true)))
    #endif
    static func num(_ v: Any?) -> Double? {
        guard let v, !isBool(v) else { return nil }
        if let n = v as? Int { return Double(n) }
        if let d = v as? Double { return d.isFinite ? d : nil }
        if let n = v as? NSNumber {
            let d = n.doubleValue
            return d.isFinite ? d : nil
        }
        return nil
    }
    static func int(_ v: Any?) -> Int? {
        guard let d = num(v), abs(d) < 1e15 else { return nil }
        return Int(d.rounded())
    }
    static func str(_ v: Any?) -> String? { v as? String }
    static func bool(_ v: Any?) -> Bool? {
        guard isBool(v) else { return nil }
        if let b = v as? Bool { return b }
        return (v as? NSNumber)?.boolValue
    }
    static func obj(_ v: Any?) -> JSON? { v as? JSON }
    static func arr(_ v: Any?) -> [Any]? { v as? [Any] }
}

enum RoleID: String, CaseIterable {
    case gatekeeper = "Guard"
    case tracker = "Hunter"
    case apothecary = "Witch"
}

struct RoleInfo {
    let name: String
    let skill: String
    let quote: String
    let art: String
}

let ROLES: [RoleID: RoleInfo] = [
    .gatekeeper: RoleInfo(name: "守门人", skill: "漏做一项必做，少扣 2 点生命。", quote: "门我来守。你守住今天答应自己的那一步。", art: "puppet_guard"),
    .tracker: RoleInfo(name: "寻迹人", skill: "每完成一项必做，多得 2 点经验。", quote: "别追所有脚印。今天先追到一个。", art: "puppet_grave"),
    .apothecary: RoleInfo(name: "药师", skill: "每完成一项必做，多回 2 点生命。", quote: "药炉还热着。去做，回来歇口气。", art: "puppet_witch"),
]

/// 完成情况。部分完成只拿一半经验，收工时漏项代价也减半。
enum Grade: String {
    case full
    case partial
}

struct XPPart: Equatable {
    var label: String
    var value: Int

    init(_ label: String, _ value: Int) {
        self.label = label
        self.value = value
    }

    init?(json: Any?) {
        guard let o = J.obj(json), let l = J.str(o["label"]), let v = J.int(o["value"]) else { return nil }
        label = l
        value = v
    }

    var json: JSON { ["label": label, "value": value] }
}

struct Round: Equatable {
    var vote: Int?
    var inspect: Bool = false
    var answer: String?
    var suspects: [Int] = []
    var replies: [Int: String] = [:]
    /// 这一票是倒计时替你剪的，不是你自己选的。
    var byInterface: Bool = false

    init() {}

    init(json: JSON) {
        vote = J.int(json["vote"])
        inspect = J.bool(json["inspect"]) ?? false
        answer = J.str(json["answer"])
        suspects = (J.arr(json["suspects"]) ?? []).compactMap { J.int($0) }
        for (k, v) in J.obj(json["replies"]) ?? [:] {
            if let seat = Int(k), let text = J.str(v) { replies[seat] = text }
        }
        byInterface = J.bool(json["byInterface"]) ?? false
    }

    var json: JSON {
        var o: JSON = [:]
        if let vote { o["vote"] = vote }
        if inspect { o["inspect"] = true }
        if let answer { o["answer"] = answer }
        if !suspects.isEmpty { o["suspects"] = suspects }
        if !replies.isEmpty {
            var r: JSON = [:]
            for (k, v) in replies { r[String(k)] = v }
            o["replies"] = r
        }
        if byInterface { o["byInterface"] = true }
        return o
    }
}

struct Quest: Identifiable, Equatable {
    var id: String
    var title: String
    var original: String
    var bonus: Bool
    var estimate: Int
    var step: String = ""
    var done: Bool = false
    var actual: Int?
    var earned: Int = 0
    var healed: Int = 0
    var prep: Int = 0
    var seed: Int = 0
    var topic: Int = 0
    var rounds: [Int: Round] = [:]
    var decision: String = ""
    var context: String = ""
    var grade: Grade?
    var xpParts: [XPPart] = []

    init(id: String = newID(), title: String, bonus: Bool, estimate: Int, step: String = "", seed: Int = Int.random(in: 0..<3)) {
        self.id = id
        self.title = title
        self.original = title
        self.bonus = bonus
        self.estimate = estimate
        self.step = step
        self.seed = seed
    }

    init?(json: Any?) {
        guard let o = J.obj(json), let id = J.str(o["id"]), let title = J.str(o["title"]) else { return nil }
        self.id = id
        self.title = title
        original = J.str(o["original"]) ?? title
        bonus = J.bool(o["bonus"]) ?? false
        estimate = max(1, J.int(o["estimate"]) ?? 25)
        step = J.str(o["step"]) ?? ""
        done = J.bool(o["done"]) ?? false
        actual = J.int(o["actual"])
        earned = max(0, J.int(o["earned"]) ?? 0)
        healed = max(0, J.int(o["healed"]) ?? 0)
        prep = max(0, J.int(o["prep"]) ?? 0)
        seed = min(2, max(0, J.int(o["seed"]) ?? 0))
        topic = min(2, max(0, J.int(o["topic"]) ?? 0))
        for (k, v) in J.obj(o["rounds"]) ?? [:] {
            if let n = Int(k), (0...2).contains(n), let r = J.obj(v) { rounds[n] = Round(json: r) }
        }
        decision = J.str(o["decision"]) ?? ""
        context = J.str(o["context"]) ?? ""
        grade = J.str(o["grade"]).flatMap(Grade.init(rawValue:))
        xpParts = (J.arr(o["xpParts"]) ?? []).compactMap { XPPart(json: $0) }
    }

    var json: JSON {
        var r: JSON = [:]
        for (k, v) in rounds { r[String(k)] = v.json }
        var o: JSON = [
            "id": id, "title": title, "original": original, "bonus": bonus, "estimate": estimate,
            "step": step, "done": done, "actual": actual.map { $0 as Any } ?? NSNull(),
            "earned": earned, "healed": healed, "prep": prep, "seed": seed, "topic": topic,
            "rounds": r, "decision": decision, "context": context,
        ]
        if let grade { o["grade"] = grade.rawValue }
        if !xpParts.isEmpty { o["xpParts"] = xpParts.map(\.json) }
        return o
    }

    /// 整件事都做完了。
    var isFull: Bool { done && grade != .partial }
    /// 登记过，但只完成了一部分。
    var isPartial: Bool { done && grade == .partial }
}

struct Day: Identifiable, Equatable {
    var id: String
    var tasks: [Quest] = []
    var closed = false
    var loss = 0
    var awarded = 0
    var reflection = ""
    var bonusXP = 0

    init(id: String) { self.id = id }

    init?(json: Any?) {
        guard let o = J.obj(json), let id = J.str(o["id"]) else { return nil }
        self.id = id
        tasks = (J.arr(o["tasks"]) ?? []).compactMap { Quest(json: $0) }
        closed = J.bool(o["closed"]) ?? false
        loss = max(0, J.int(o["loss"]) ?? 0)
        awarded = max(0, J.int(o["awarded"]) ?? 0)
        reflection = J.str(o["reflection"]) ?? ""
        bonusXP = max(0, J.int(o["bonusXP"]) ?? 0)
    }

    var json: JSON {
        var o: JSON = ["id": id, "tasks": tasks.map(\.json), "closed": closed, "loss": loss, "awarded": awarded, "reflection": reflection]
        if bonusXP > 0 { o["bonusXP"] = bonusXP }
        return o
    }
}

struct Keepsake: Identifiable, Equatable {
    var id: String
    var date: String
    var name: String
    var effect: String
    var kind: Int

    init(id: String = newID(), date: String, name: String, effect: String, kind: Int) {
        self.id = id
        self.date = date
        self.name = name
        self.effect = effect
        self.kind = kind
    }

    init?(json: Any?) {
        guard let o = J.obj(json), let id = J.str(o["id"]), let name = J.str(o["name"]) else { return nil }
        self.id = id
        self.name = name
        date = J.str(o["date"]) ?? ""
        effect = J.str(o["effect"]) ?? ""
        kind = min(2, max(0, J.int(o["kind"]) ?? 0))
    }

    var json: JSON { ["id": id, "date": date, "name": name, "effect": effect, "kind": kind] }

    var art: String { ["card_arrow", "card_ward", "card_potion"][kind] }
}

struct SimRecord: Equatable {
    var level = ""
    var label = ""
    var text = ""
    var note = ""
    var byAI = false
    var atSeconds = 0

    init(level: String, label: String, text: String, note: String, byAI: Bool, atSeconds: Int) {
        self.level = level
        self.label = label
        self.text = text
        self.note = note
        self.byAI = byAI
        self.atSeconds = atSeconds
    }

    init?(json: Any?) {
        guard let o = J.obj(json) else { return nil }
        level = J.str(o["level"]) ?? ""
        label = J.str(o["label"]) ?? ""
        text = J.str(o["text"]) ?? ""
        note = J.str(o["note"]) ?? ""
        byAI = J.bool(o["byAI"]) ?? false
        atSeconds = J.int(o["atSeconds"]) ?? 0
    }

    var json: JSON { ["level": level, "label": label, "text": text, "note": note, "byAI": byAI, "atSeconds": atSeconds] }
}

/// 夜谈里真正提交过的动作。只记事实。
struct Trace: Equatable {
    var key: String
    var kind: String
    var mode: String
    var session: String
    var round: Int
    var completedCount: Int
    var unlockedTier: Int
    var strategyTier: Int?
    var strategyLabel: String?
    var targetSeat: Int?
    var voteAttempt: Int?
    var winner: String?
    var reason: String?

    init(kind: String, mode: String, session: String, round: Int, completedCount: Int, unlockedTier: Int) {
        self.kind = kind
        self.mode = mode
        self.session = session
        self.round = round
        self.completedCount = completedCount
        self.unlockedTier = unlockedTier
        self.key = ""
    }

    init?(json: Any?) {
        guard let o = J.obj(json), J.int(o["version"]) == 1,
              let kind = J.str(o["kind"]), let mode = J.str(o["mode"]), let session = J.str(o["session"]),
              let round = J.int(o["round"]) else { return nil }
        self.kind = kind
        self.mode = mode
        self.session = session
        self.round = round
        key = J.str(o["key"]) ?? ""
        completedCount = J.int(o["completedCount"]) ?? 0
        unlockedTier = J.int(o["unlockedTier"]) ?? 0
        strategyTier = J.int(o["strategyTier"])
        strategyLabel = J.str(o["strategyLabel"])
        targetSeat = J.int(o["targetSeat"])
        voteAttempt = J.int(o["voteAttempt"])
        winner = J.str(o["winner"])
        reason = J.str(o["reason"])
    }

    var json: JSON {
        var o: JSON = ["version": 1, "key": key, "kind": kind, "mode": mode, "session": session, "round": round,
                       "completedCount": completedCount, "unlockedTier": unlockedTier]
        if let strategyTier { o["strategyTier"] = strategyTier }
        if let strategyLabel { o["strategyLabel"] = strategyLabel }
        if let targetSeat { o["targetSeat"] = targetSeat }
        if let voteAttempt { o["voteAttempt"] = voteAttempt }
        if let winner { o["winner"] = winner }
        if let reason { o["reason"] = reason }
        return o
    }

    var isValid: Bool {
        guard ["strategy", "vote", "result"].contains(kind), ["solo", "online"].contains(mode),
              !session.isEmpty, session.count <= 100, (1...3).contains(round),
              (0...3).contains(unlockedTier), completedCount >= 0 else { return false }
        switch kind {
        case "strategy":
            guard let t = strategyTier else { return false }
            return t >= 0 && t <= unlockedTier
        case "vote":
            guard let s = targetSeat, let a = voteAttempt else { return false }
            return (1...5).contains(s) && (1...2).contains(a)
        default:
            return winner == "villagers" || winner == "wolf"
        }
    }
}

struct LogEvent: Identifiable, Equatable {
    var id: String
    var date: String
    var time: String
    var type: String
    var text: String
    var task: String?
    var records: [SimRecord] = []
    var elapsedSeconds: Int?
    var trace: Trace?
    /// true = 这个决定被界面带走了；false = 你亲手做的。只有 bait 事件带这个字段。
    var taken: Bool?

    init(date: String, time: String, type: String, text: String, task: String? = nil) {
        id = newID()
        self.date = date
        self.time = time
        self.type = type
        self.text = text
        self.task = task
    }

    init?(json: Any?) {
        guard let o = J.obj(json), let id = J.str(o["id"]), let type = J.str(o["type"]) else { return nil }
        self.id = id
        self.type = type
        date = J.str(o["date"]) ?? ""
        time = J.str(o["time"]) ?? ""
        text = J.str(o["text"]) ?? ""
        task = J.str(o["task"])
        records = (J.arr(o["records"]) ?? []).compactMap { SimRecord(json: $0) }
        elapsedSeconds = J.int(o["elapsedSeconds"])
        trace = Trace(json: o["trace"])
        taken = J.bool(o["taken"])
    }

    var json: JSON {
        var o: JSON = ["id": id, "date": date, "time": time, "type": type, "text": text, "task": task.map { $0 as Any } ?? NSNull()]
        if type == "simulation" {
            o["simulation"] = true
            o["records"] = records.map(\.json)
            o["elapsedSeconds"] = elapsedSeconds ?? 0
        }
        if let trace { o["trace"] = trace.json }
        if let taken { o["taken"] = taken }
        return o
    }
}

struct TalkStats: Equatable {
    var played = 0
    var wins = 0
    var lastResult: String?

    init() {}

    init(json: Any?) {
        guard let o = J.obj(json) else { return }
        played = min(1_000_000, max(0, J.int(o["played"]) ?? 0))
        wins = min(played, max(0, J.int(o["wins"]) ?? 0))
        let r = J.str(o["lastResult"])
        lastResult = (r == "villagers" || r == "wolf") ? r : nil
    }

    var json: JSON {
        ["version": 2, "played": played, "wins": wins, "lastResult": lastResult.map { $0 as Any } ?? NSNull()]
    }
}

struct Ledger: Equatable {
    var version = 1
    var hp = 84
    var xp = 0
    /// 专注：每完成一项必做多得的经验。
    var attack = 2
    /// 韧性：每漏一项必做少扣的生命。
    var magic = 1
    var streak = 0
    var draws = 0
    var role: RoleID = .gatekeeper
    var lastSwitchXP = 0
    var days: [Day]
    var cards: [Keepsake] = []
    var events: [LogEvent] = []
    var tone = "sharp"
    var game: TalkStats?

    init(today: String) {
        days = [Day(id: today)]
    }

    init?(json: Any?) {
        guard let o = J.obj(json), J.int(o["version"]) == 1,
              let roleName = J.str(o["role"]), let role = RoleID(rawValue: roleName),
              let rawDays = J.arr(o["days"]), !rawDays.isEmpty else { return nil }
        let parsed = rawDays.compactMap { Day(json: $0) }
        guard parsed.count == rawDays.count else { return nil }
        self.role = role
        days = parsed
        hp = min(100, max(0, J.int(o["hp"]) ?? 84))
        xp = max(0, J.int(o["xp"]) ?? 0)
        attack = max(0, J.int(o["attack"]) ?? 2)
        magic = max(0, J.int(o["magic"]) ?? 1)
        streak = max(0, J.int(o["streak"]) ?? 0)
        draws = max(0, J.int(o["draws"]) ?? 0)
        lastSwitchXP = min(xp, max(0, J.int(o["lastSwitchXP"]) ?? 0))
        cards = (J.arr(o["cards"]) ?? []).compactMap { Keepsake(json: $0) }
        events = (J.arr(o["events"]) ?? []).compactMap { LogEvent(json: $0) }
        tone = J.str(o["tone"]) == "gentle" ? "gentle" : "sharp"
        if o["game"] != nil { game = TalkStats(json: o["game"]) }
    }

    var json: JSON {
        var o: JSON = [
            "version": 1, "hp": hp, "xp": xp, "attack": attack, "magic": magic, "streak": streak, "draws": draws,
            "role": role.rawValue, "lastSwitchXP": lastSwitchXP, "days": days.map(\.json),
            "cards": cards.map(\.json), "events": events.map(\.json), "tone": tone,
        ]
        if let game { o["game"] = game.json }
        return o
    }

    func data(pretty: Bool = false) -> Data? {
        var options: JSONSerialization.WritingOptions = [.sortedKeys]
        if pretty { options.insert(.prettyPrinted) }
        return try? JSONSerialization.data(withJSONObject: json, options: options)
    }

    static func load(_ data: Data) -> Ledger? {
        guard let raw = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return Ledger(json: raw)
    }
}

func newID() -> String { UUID().uuidString.lowercased() }

enum Clock {
    static func dayID(_ date: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func date(fromDayID id: String) -> Date? {
        let p = id.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12))
    }

    static func timeLabel(_ date: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    static func dayLabel(_ id: String) -> String {
        guard let d = date(fromDayID: id) else { return id }
        let c = Calendar.current.dateComponents([.month, .day, .weekday], from: d)
        let week = ["日", "一", "二", "三", "四", "五", "六"][max(0, min(6, (c.weekday ?? 1) - 1))]
        return "\(c.month ?? 0)月\(c.day ?? 0)日 周\(week)"
    }

    /// 这一天结束的时刻（次日零点）。
    static func endOfDay(_ id: String) -> Date? {
        let p = id.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: p[0], month: p[1], day: p[2] + 1))
    }
}
