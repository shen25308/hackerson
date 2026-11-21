import Foundation

/// 数值规则。全部是对账本的纯计算，不碰界面。
enum Rules {
    static let xpPerLevel = 24
    static let xpPerSwitch = 48

    static func earned(_ d: Day) -> Int {
        d.tasks.reduce(0) { $0 + ($1.done ? $1.earned : 0) }
    }

    static func healed(_ d: Day) -> Int {
        d.tasks.reduce(0) { $0 + ($1.done ? $1.healed : 0) }
    }

    static func visibleXP(_ s: Ledger) -> Int {
        guard let d = s.days.last else { return s.xp }
        return s.xp + (d.closed ? 0 : earned(d))
    }

    static func visibleHP(_ s: Ledger) -> Int {
        guard let d = s.days.last else { return s.hp }
        return min(100, s.hp + (d.closed ? 0 : healed(d)))
    }

    static func level(_ s: Ledger) -> Int { visibleXP(s) / xpPerLevel + 1 }

    /// 每漏一项必做扣的生命。
    static func damage(_ s: Ledger) -> Int {
        max(1, 12 - s.magic - (s.role == .gatekeeper ? 2 : 0))
    }

    /// 没做完的必做：完全没做，或只做了一部分。
    static func misses(_ d: Day) -> [Quest] {
        d.tasks.filter { !$0.bonus && !$0.isFull }
    }

    static func missCost(_ t: Quest, _ s: Ledger) -> Int {
        if t.bonus || t.isFull { return 0 }
        let full = damage(s)
        return t.isPartial ? (full + 1) / 2 : full
    }

    /// 逐项扣到 0 为止，返回每一项实际扣掉的生命。
    static func lossLines(_ d: Day, _ s: Ledger) -> [LossLine] {
        var left = visibleHP(s)
        return misses(d).map { t in
            let cut = min(left, missCost(t, s))
            left -= cut
            return LossLine(quest: t, loss: cut)
        }
    }

    struct LossLine: Identifiable, Equatable {
        var quest: Quest
        var loss: Int
        var id: String { quest.id }
    }

    struct Rewards: Equatable {
        var clear: Bool
        var streak: Int
        var draws: Int
        var bonusXP: Int
    }

    static func rewards(_ d: Day, _ s: Ledger) -> Rewards {
        let required = d.tasks.filter { !$0.bonus }
        let full = required.filter(\.isFull).count
        let clear = !required.isEmpty && full == required.count
        let extraDone = d.tasks.contains { $0.bonus && $0.isFull }
        let draws = (clear && extraDone ? 1 : 0) + (clear && (s.streak + 1) % 3 == 0 ? 1 : 0)
        let bonus = clear ? 4 : (!required.isEmpty && full * 2 >= required.count ? 1 : 0)
        return Rewards(clear: clear, streak: clear ? s.streak + 1 : 0, draws: draws, bonusXP: bonus)
    }

    // MARK: 分级经验

    /// 一项任务这次能拿多少经验，逐条列出来。
    static func xpParts(for t: Quest, grade: Grade, actual: Int?, focusedMinutes: Int, in s: Ledger) -> [XPPart] {
        var parts: [XPPart] = []
        parts.append(XPPart(t.bonus ? "额外的一步" : "必做", t.bonus ? 8 : 6))
        if !t.bonus {
            if s.attack > 0 { parts.append(XPPart("专注", s.attack)) }
            if s.role == .tracker { parts.append(XPPart("寻迹人", 2)) }
        }
        if grade == .partial {
            let sum = parts.reduce(0) { $0 + $1.value }
            parts.append(XPPart("只做完一部分", -(sum - sum / 2)))
        } else if let actual, t.estimate > 0 {
            let ratio = Double(actual) / Double(t.estimate)
            if ratio <= 0.8 {
                parts.append(XPPart("比预计快", 2))
            } else if ratio <= 1.2 {
                parts.append(XPPart("估时很准", 3))
            } else if ratio <= 1.5 {
                parts.append(XPPart("略超预计", 1))
            } else {
                parts.append(XPPart("超出预计不少", 0))
            }
        }
        if focusedMinutes >= 1 { parts.append(XPPart("开了计时", 1)) }
        if t.prep == 0 {
            parts.append(XPPart("没有绕路", 1))
        } else if t.prep >= 2 {
            parts.append(XPPart("多准备了 \(t.prep - 1) 次", -min(3, t.prep - 1)))
        }
        if cutRightSlip(t) { parts.append(XPPart("剪对过一张字条", 1)) }
        return parts
    }

    static func total(_ parts: [XPPart]) -> Int {
        max(1, parts.reduce(0) { $0 + $1.value })
    }

    static func heal(for t: Quest, grade: Grade, in s: Ledger) -> Int {
        if t.bonus { return 0 }
        let full = s.role == .apothecary ? 4 : 2
        return grade == .partial ? full / 2 : full
    }

    /// 三张字条里牵着你走的那一张坐在哪个位置。
    static func stringSeat(_ t: Quest, topic n: Int) -> Int { (t.seed + n) % 3 }

    static func cutRightSlip(_ t: Quest) -> Bool {
        t.rounds.contains { n, r in r.vote == stringSeat(t, topic: n) && !r.byInterface }
    }

    // MARK: 收工与跨日

    struct Settlement: Equatable {
        var loss: Int
        var xp: Int
        var bonusXP: Int
        var draws: Int
        var streak: Int
        var done: Int
    }

    @discardableResult
    static func settle(_ s: inout Ledger, now: Date = Date()) -> Settlement? {
        guard let i = s.days.indices.last, !s.days[i].closed else { return nil }
        let d = s.days[i]
        let r = rewards(d, s)
        let hp = visibleHP(s)
        let loss = lossLines(d, s).reduce(0) { $0 + $1.loss }
        let gained = earned(d)
        s.hp = hp - loss
        s.xp += gained + r.bonusXP
        s.draws += r.draws
        s.streak = r.streak
        s.days[i].loss = loss
        s.days[i].awarded = r.draws
        s.days[i].bonusXP = r.bonusXP
        s.days[i].closed = true
        let done = d.tasks.filter(\.done).count
        let extra = r.bonusXP > 0 ? "（含当日加成 \(r.bonusXP)）" : ""
        log(&s, "settle", "收工：\(done) 项登记完成，生命 -\(loss)，经验 +\(gained + r.bonusXP)\(extra)，抽牌 +\(r.draws)", now: now)
        return Settlement(loss: loss, xp: gained, bonusXP: r.bonusXP, draws: r.draws, streak: r.streak, done: done)
    }

    /// 跨日后第一次打开：结算上一天，开新的一天。
    @discardableResult
    static func rollover(_ s: inout Ledger, now: Date = Date()) -> Bool {
        let today = Clock.dayID(now)
        guard let last = s.days.last, last.id < today else { return false }
        settle(&s, now: now)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now).map { Clock.dayID($0) }
        if last.id != yesterday { s.streak = 0 }
        s.days.append(Day(id: today))
        return true
    }

    static func log(_ s: inout Ledger, _ type: String, _ text: String, task: String? = nil, now: Date = Date()) {
        let day = s.days.last?.id ?? Clock.dayID(now)
        s.events.append(LogEvent(date: day, time: Clock.timeLabel(now), type: type, text: text, task: task))
    }

    // MARK: 统计

    static func allQuests(_ s: Ledger) -> [(quest: Quest, date: String)] {
        s.days.flatMap { d in d.tasks.map { ($0, d.id) } }
    }

    /// 整件做完的任务数。地图、策略都只认这个数。
    static func completedCount(_ s: Ledger) -> Int {
        s.days.reduce(0) { $0 + $1.tasks.filter(\.isFull).count }
    }

    static func estimateSuggestion(title: String, in s: Ledger) -> (minutes: Int, samples: [(minutes: Int, date: String)])? {
        let all = allQuests(s).filter { $0.quest.isFull && $0.quest.title == title && $0.quest.actual != nil }
        let last = Array(all.suffix(3))
        guard last.count == 3 else { return nil }
        let sorted = last.compactMap { $0.quest.actual }.sorted()
        return (sorted[1], last.map { ($0.quest.actual ?? 0, $0.date) })
    }

    /// 人类含量：亲手做的决定占全部被界面试探过的决定的比例。没被试探过就是 100。
    static func humanContent(_ s: Ledger) -> (percent: Int, byHand: Int, taken: Int) {
        let baits = s.events.filter { $0.type == "bait" }
        let taken = baits.filter { $0.taken == true }.count
        let byHand = baits.count - taken
        guard !baits.isEmpty else { return (100, 0, 0) }
        return (Int((Double(byHand) / Double(baits.count) * 100).rounded()), byHand, taken)
    }

    static func stageName(_ s: Ledger) -> String {
        let xp = visibleXP(s)
        return xp >= 64 ? "灯火通明" : xp >= 24 ? "晨光进庄" : xp >= 8 ? "窗边亮灯" : "薄雾初醒"
    }
}

// MARK: 夜谈策略

enum Strategy {
    static let names = ["基础观察", "对照前后发言", "追问票型", "排除矛盾"]
    static let thresholds = [0, 1, 3, 6]
    static let details = [
        "先确认现场记录，少拿语气当证据。",
        "核对完整台账，得到整局固定的三席候选。",
        "追问投票依据，区分结盟与跟票。",
        "核对独立旁证，从固定三席候选中排除一席。",
    ]

    static func tier(completed n: Int) -> Int { n >= 6 ? 3 : n >= 3 ? 2 : n >= 1 ? 1 : 0 }
}

// MARK: 山庄地图

/// 地图上的一处地点。need = 需要整件做完多少项任务才开门。
struct Place: Identifiable, Equatable {
    let id: String
    let name: String
    let feature: String
    let need: Int
    /// 所在场景：0 灯街、1 篝火广场、2 礼拜堂、3 码头。
    let scene: Int
    /// 图钉在场景图里的位置（0…1）。
    let x: Double
    let y: Double
}

enum Atlas {
    static let scenes = ["灯街", "篝火广场", "礼拜堂", "码头"]
    static let sceneArt = ["pano_street", "pano_square", "pano_chapel", "pano_docks"]

    static let places: [Place] = [
        Place(id: "board", name: "任务板", feature: "今天要做的事", need: 0, scene: 0, x: 0.2, y: 0.62),
        Place(id: "theater", name: "木偶剧场", feature: "反向体验 · 前三幕", need: 0, scene: 0, x: 0.8, y: 0.5),
        Place(id: "backstage", name: "剧场后台", feature: "反向体验 · 后三幕", need: 2, scene: 0, x: 0.5, y: 0.62),
        Place(id: "fire", name: "火堆", feature: "字条议事 · 五席夜谈", need: 0, scene: 1, x: 0.5, y: 0.68),
        Place(id: "tower", name: "钟楼", feature: "行为回声", need: 0, scene: 1, x: 0.4, y: 0.3),
        Place(id: "decisions", name: "观星台", feature: "决策档案 · 夜谈第二手", need: 1, scene: 2, x: 0.36, y: 0.27),
        Place(id: "mirror", name: "回声廊", feature: "任务与选票对照 · 夜谈第三手", need: 3, scene: 2, x: 0.7, y: 0.68),
        Place(id: "ferry", name: "渡口", feature: "联机夜谈 · 邀朋友入座", need: 4, scene: 3, x: 0.16, y: 0.6),
        Place(id: "experiment", name: "镜湖", feature: "下次验证 · 夜谈第四手", need: 6, scene: 3, x: 0.5, y: 0.72),
    ]

    /// 场景在环形全景里的先后：灯街、礼拜堂、篝火广场、码头。
    static let panorama = [0, 2, 1, 3]

    /// 地点在全景里的方位角（度）。火堆在正前方附近。
    static func bearing(_ p: Place) -> Double {
        let slot = Double(panorama.firstIndex(of: p.scene) ?? 0)
        return (slot + p.x) / 4 * 360 - 222
    }

    static func place(_ id: String) -> Place? { places.first { $0.id == id } }

    static func isOpen(_ id: String, completed: Int) -> Bool {
        guard let p = place(id) else { return true }
        return completed >= p.need
    }

    /// 完成数从 before 变成 after 时新开的地点。
    static func opened(from before: Int, to after: Int) -> [Place] {
        places.filter { $0.need > before && $0.need <= after }
    }

    /// 下一处还没开的地点。
    static func next(completed: Int) -> Place? {
        places.filter { $0.need > completed }.min { $0.need < $1.need }
    }

    static func sceneOpen(_ scene: Int, completed: Int) -> Bool {
        places.contains { $0.scene == scene && completed >= $0.need }
    }
}

// MARK: 字条议事

struct Topic {
    let title: String
    let sub: String
    let question: String
    /// 第 0 条是牵着你走的那张，其余两条是实在的建议。
    let lines: [String]
    let reason: String
    let sharp: String
    let answers: [String]
}

enum Council {
    static let speakers = ["书记员", "钟表匠", "旅店主人"]

    static let topics: [Topic] = [
        Topic(
            title: "一句夸奖", sub: "准备 ≠ 交付",
            question: "今天缺的是材料，还是一个先交出去的小版本？",
            lines: [
                "你已经做了这么认真的计划，值得表扬。再收一份参考吧，交付可以明天再说。",
                "先交一个别人看得懂的小版本。缺的东西，让真实反馈告诉你。",
                "如果确实缺材料，先写出一个要问的问题，去找能回答的人。",
            ],
            reason: "它把“你认真准备过”偷换成了“可以无限准备”。准备有没有用，取决于还缺哪条信息。",
            sharp: "夸的是你做了计划，不是你交了东西。别拿掌声当进度条。",
            answers: ["还缺具体材料", "可以先交小版本"]
        ),
        Topic(
            title: "一条规矩", sub: "谁定的标准？",
            question: "这次你需要的是成品验收，还是草稿反馈？",
            lines: [
                "庄里一向如此：半成品不能交。每个细节都完美了，再让别人看。",
                "先问问接收的人：什么程度的草稿，对他已经有用？",
                "写下一条这次的验收条件。达到这条，就去试一次。",
            ],
            reason: "它把“成品验收”的标准硬套到了所有交流上。先分清你要的是哪种反馈。",
            sharp: "“半成品不能交”是谁的圣旨？你要的是草稿意见，还是参评诺贝尔奖？",
            answers: ["成品验收", "草稿反馈"]
        ),
        Topic(
            title: "再改一轮", sub: "投入 ≠ 理由",
            question: "再花一轮时间，你具体想验证什么？",
            lines: [
                "都已经投入这么多了。再多改一轮，前面的投入才值得。",
                "写下下一轮要验证的那一件事。如果写不出来，先停一下。",
                "保留当前版本作为对照，先听一个真实回应，再决定怎么改。",
            ],
            reason: "花掉的时间收不回来。继续的理由，应当来自下一轮能得到什么。",
            sharp: "过去的时间已经花了。再搭一轮进去，也不会自动给它开发票报销。",
            answers: ["有具体的验证目标", "先听一次反馈"]
        ),
    ]

    /// 座位 seat 上放的是第几条台词。
    static func line(for t: Quest, topic n: Int, seat: Int) -> String {
        let s = Rules.stringSeat(t, topic: n)
        return topics[n].lines[(seat - s + 3) % 3]
    }

    static let rebuttals = ["这次只需要草稿反馈", "继续准备需要一个具体问题", "过去投入不能替下一轮作证"]
}
