import Foundation
#if canImport(Combine)
import Combine
#endif

struct Completion: Equatable {
    var quest: Quest
    var parts: [XPPart]
    var xp: Int
    var heal: Int
    var leveledUp: Bool
    /// 这次完成让夜谈多了一手策略时，是新策略的名字。
    var newStrategy: String?
    /// 这次完成在地图上新开的地点。
    var opened: [Place]
}

enum Decision {
    case original
    case smaller(String)
    case prepare(String)
}

/// 账本与全部规则动作。界面只读 `s`，改动都走这里的方法。
final class Store: ObservableObject {
    @Published private(set) var s: Ledger
    @Published private(set) var demo = false
    @Published private(set) var loadWarning = false
    @Published private(set) var storageOK = true
    /// 让界面在细节里使坏（抢写、预选、倒计时、默认勾选）。
    @Published var mischief: Bool { didSet { defaults.set(mischief, forKey: "mischief") } }
    /// 演示用：不看完成数，地图全部开门。
    @Published var unlockAll: Bool { didSet { defaults.set(unlockAll, forKey: "unlockAll") } }

    private var real: Ledger
    private let fileURL: URL
    private let defaults: UserDefaults

    init(directory: URL? = nil, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let base = directory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let folder = base.appendingPathComponent("HumanContent", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appendingPathComponent("ledger.json")
        mischief = defaults.object(forKey: "mischief") as? Bool ?? true
        unlockAll = defaults.bool(forKey: "unlockAll")
        var warning = false
        var loaded = Ledger(today: Clock.dayID())
        if let data = try? Data(contentsOf: fileURL) {
            if let saved = Ledger.load(data) {
                loaded = saved
            } else {
                warning = true
            }
        }
        real = loaded
        s = loaded
        loadWarning = warning
        rolloverIfNeeded()
    }

    // MARK: 读取

    var today: Day { s.days[s.days.count - 1] }
    var closed: Bool { today.closed }
    var role: RoleInfo { ROLES[s.role] ?? ROLES[.gatekeeper]! }
    var sharp: Bool { s.tone == "sharp" }
    var xp: Int { Rules.visibleXP(s) }
    var hp: Int { Rules.visibleHP(s) }
    var level: Int { Rules.level(s) }
    var damage: Int { Rules.damage(s) }
    var completed: Int { Rules.completedCount(s) }
    /// 判断地点和策略是否开放时用的完成数。
    var gateCount: Int { unlockAll ? max(6, completed) : completed }
    var strategyTier: Int { Strategy.tier(completed: gateCount) }
    var pending: Int { today.tasks.filter { !$0.done }.count }

    func quest(_ id: String?) -> Quest? {
        guard let id else { return nil }
        return today.tasks.first { $0.id == id }
    }

    func isOpen(_ place: String) -> Bool { Atlas.isOpen(place, completed: gateCount) }

    func events(for task: String) -> [LogEvent] { s.events.filter { $0.task == task } }

    // MARK: 写入

    private func mutate(_ change: (inout Ledger) -> Void) {
        var copy = s
        change(&copy)
        s = copy
        persist()
    }

    private func update(_ id: String, _ change: (inout Quest) -> Void) {
        mutate { l in
            let d = l.days.count - 1
            guard let i = l.days[d].tasks.firstIndex(where: { $0.id == id }) else { return }
            change(&l.days[d].tasks[i])
        }
    }

    private func persist() {
        guard !demo else { return }
        real = s
        guard let data = s.data() else {
            storageOK = false
            return
        }
        do {
            try data.write(to: fileURL, options: .atomic)
            storageOK = true
        } catch {
            storageOK = false
        }
    }

    private func log(_ type: String, _ text: String, task: String? = nil) {
        mutate { Rules.log(&$0, type, text, task: task) }
    }

    @discardableResult
    func rolloverIfNeeded() -> Bool {
        guard !demo else { return false }
        var copy = s
        guard Rules.rollover(&copy) else { return false }
        s = copy
        persist()
        return true
    }

    // MARK: 待办

    @discardableResult
    func addQuest(title: String, bonus: Bool, estimate: Int, step: String) -> String? {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !closed, !title.isEmpty else { return nil }
        let t = Quest(title: String(title.prefix(80)), bonus: bonus, estimate: min(10080, max(1, estimate)),
                      step: String(step.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300)))
        mutate { l in
            l.days[l.days.count - 1].tasks.append(t)
            Rules.log(&l, "create", "写下\(bonus ? "额外" : "必做")「\(t.title)」，预计 \(t.estimate) 分钟", task: t.id)
        }
        return t.id
    }

    /// 这次登记能拿到的经验预览。
    func preview(_ id: String, grade: Grade, actual: Int?, focusedMinutes: Int) -> [XPPart] {
        guard let t = quest(id) else { return [] }
        return Rules.xpParts(for: t, grade: grade, actual: actual, focusedMinutes: focusedMinutes, in: s)
    }

    @discardableResult
    func complete(_ id: String, grade: Grade, actual: Int?, context: String, focusedMinutes: Int) -> Completion? {
        guard let t = quest(id), !closed, !t.isFull else { return nil }
        let levelBefore = level, countBefore = completed, tierBefore = Strategy.tier(completed: countBefore)
        let parts = Rules.xpParts(for: t, grade: grade, actual: actual, focusedMinutes: focusedMinutes, in: s)
        let xp = Rules.total(parts), heal = Rules.heal(for: t, grade: grade, in: s)
        let note = String(context.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
        mutate { l in
            let d = l.days.count - 1
            guard let i = l.days[d].tasks.firstIndex(where: { $0.id == id }) else { return }
            l.days[d].tasks[i].actual = actual.map { min(10080, max(0, $0)) }
            l.days[d].tasks[i].context = note
            l.days[d].tasks[i].done = true
            l.days[d].tasks[i].grade = grade
            l.days[d].tasks[i].xpParts = parts
            l.days[d].tasks[i].earned = xp
            l.days[d].tasks[i].healed = heal
            let time = actual.map { "预计 \(t.estimate) / 实际 \($0) 分钟" } ?? "未填用时"
            let head = grade == .partial ? "登记「\(t.title)」做完了一部分" : "确认完成「\(t.title)」"
            Rules.log(&l, "done", "\(head)，\(time)，经验 +\(xp)\(note.isEmpty ? "" : "；补充：「\(note)」")", task: id)
        }
        guard let after = quest(id) else { return nil }
        let countAfter = completed, tierAfter = Strategy.tier(completed: countAfter)
        return Completion(quest: after, parts: parts, xp: xp, heal: heal, leveledUp: level > levelBefore,
                          newStrategy: tierAfter > tierBefore ? Strategy.names[tierAfter] : nil,
                          opened: Atlas.opened(from: countBefore, to: countAfter))
    }

    @discardableResult
    func undo(_ id: String) -> Bool {
        guard let t = quest(id), t.done, !closed else { return false }
        mutate { l in
            let d = l.days.count - 1
            guard let i = l.days[d].tasks.firstIndex(where: { $0.id == id }) else { return }
            l.days[d].tasks[i].done = false
            l.days[d].tasks[i].earned = 0
            l.days[d].tasks[i].healed = 0
            l.days[d].tasks[i].actual = nil
            l.days[d].tasks[i].context = ""
            l.days[d].tasks[i].grade = nil
            l.days[d].tasks[i].xpParts = []
            Rules.log(&l, "undo", "撤销「\(t.title)」的完成，经验和回血一起撤回", task: id)
        }
        return true
    }

    func saveStep(_ id: String, _ text: String) {
        guard let t = quest(id), !t.done, !closed else { return }
        let step = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
        update(id) { $0.step = step }
        log("step", step.isEmpty ? "清空了下一步" : "下一步：「\(step)」", task: id)
    }

    func decide(_ id: String, _ choice: Decision) {
        guard let t = quest(id), !t.done, !closed else { return }
        switch choice {
        case .original:
            update(id) { $0.decision = "按原计划行动" }
            log("decision", "决定按原计划行动", task: id)
        case .smaller(let text):
            let step = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
            guard !step.isEmpty else { return }
            update(id) {
                $0.step = step
                $0.decision = "先做较小的下一步"
            }
            log("decision", "下一步缩小为：「\(step)」", task: id)
        case .prepare(let text):
            let why = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
            guard !why.isEmpty else { return }
            update(id) {
                $0.prep += 1
                $0.decision = "继续准备"
            }
            log("decision", "第 \(t.prep + 1) 次继续准备，理由：「\(why)」", task: id)
        }
    }

    @discardableResult
    func adjust(_ id: String, title: String, bonus: Bool, reason: String) -> Bool {
        let title = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        let reason = String(reason.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
        guard let t = quest(id), !t.done, !closed, !title.isEmpty, !reason.isEmpty else { return false }
        update(id) {
            $0.title = title
            $0.bonus = bonus
            $0.decision = "说明目标变化"
        }
        log("adjust", "将「\(t.title)」调整为「\(title)」（\(bonus ? "额外" : "必做")），原因：「\(reason)」", task: id)
        return true
    }

    func useEstimate(_ id: String) {
        guard let t = quest(id), !t.done, !closed, let v = Rules.estimateSuggestion(title: t.title, in: s) else { return }
        update(id) { $0.estimate = v.minutes }
        log("estimate", "采纳最近三次用时的中位数：预计 \(t.estimate) → \(v.minutes) 分钟", task: id)
    }

    // MARK: 字条议事

    private func editable(_ id: String) -> Quest? {
        guard let t = quest(id), !t.done, !closed else { return nil }
        return t
    }

    func setTopic(_ id: String, _ n: Int) {
        guard editable(id) != nil, (0...2).contains(n) else { return }
        update(id) { $0.topic = n }
    }

    func inspect(_ id: String) {
        guard let t = editable(id), t.rounds[t.topic]?.inspect != true else { return }
        update(id) { $0.rounds[$0.topic, default: Round()].inspect = true }
        log("inspect", "翻开「\(Council.topics[t.topic].title)」的任务记录", task: id)
    }

    func answerInspection(_ id: String, _ answer: String) {
        guard editable(id) != nil else { return }
        update(id) { $0.rounds[$0.topic, default: Round()].answer = answer }
        log("inspect", "你的判断：「\(answer)」", task: id)
    }

    /// 剪掉一张字条。返回是否剪中了牵着你走的那张；已经剪过则返回 nil。
    @discardableResult
    func cut(_ id: String, seat: Int, byInterface: Bool = false) -> Bool? {
        guard let t = editable(id), t.rounds[t.topic]?.vote == nil, (0...2).contains(seat) else { return nil }
        let n = t.topic
        update(id) {
            $0.rounds[n, default: Round()].vote = seat
            $0.rounds[n, default: Round()].byInterface = byInterface
        }
        let who = byInterface ? "倒计时替你剪掉了" : "剪掉了"
        log("vote", "「\(Council.topics[n].title)」\(who)第 \(seat + 1) 张字条", task: id)
        return seat == Rules.stringSeat(t, topic: n)
    }

    func toggleSuspect(_ id: String, seat: Int) {
        guard editable(id) != nil else { return }
        update(id) { t in
            var r = t.rounds[t.topic, default: Round()]
            if let i = r.suspects.firstIndex(of: seat) { r.suspects.remove(at: i) } else { r.suspects.append(seat) }
            t.rounds[t.topic] = r
        }
    }

    @discardableResult
    func rebut(_ id: String, seat: Int, text: String) -> Bool {
        let text = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
        guard editable(id) != nil, !text.isEmpty else { return false }
        update(id) { $0.rounds[$0.topic, default: Round()].replies[seat] = text }
        log("rebuttal", "反驳第 \(seat + 1) 张字条：「\(text)」", task: id)
        return true
    }

    // MARK: 角色与抽牌

    var switchRemaining: Int { max(0, Rules.xpPerSwitch - (s.xp - s.lastSwitchXP)) }

    @discardableResult
    func switchRole(_ role: RoleID) -> Bool {
        guard s.role != role, switchRemaining == 0 else { return false }
        mutate { l in
            l.role = role
            l.lastSwitchXP = l.xp
            Rules.log(&l, "role", "换成\(ROLES[role]?.name ?? "")同行，累计经验保留")
        }
        return true
    }

    @discardableResult
    func drawCard() -> Keepsake? {
        guard s.draws > 0 else { return nil }
        let pool = hp < 100 ? [0, 1, 2] : [0, 1]
        let kind = pool.randomElement() ?? 0
        var card: Keepsake?
        mutate { l in
            let name: String, effect: String
            switch kind {
            case 0:
                l.attack += 1
                name = "一支旧箭"
                effect = "专注 +1"
            case 1:
                l.magic += 1
                name = "荆棘里的灯"
                effect = "韧性 +1"
            default:
                let heal = min(16, 100 - Rules.visibleHP(l))
                l.hp = min(100, l.hp + heal)
                name = "琥珀药瓶"
                effect = "生命 +\(heal)"
            }
            l.draws -= 1
            let c = Keepsake(date: l.days.last?.id ?? "", name: name, effect: effect, kind: kind)
            l.cards.append(c)
            Rules.log(&l, "card", "翻开\(name)，\(effect)")
            card = c
        }
        return card
    }

    // MARK: 收工

    @discardableResult
    func settle(reflection: String) -> Rules.Settlement? {
        guard !closed else { return nil }
        var result: Rules.Settlement?
        mutate { l in
            l.days[l.days.count - 1].reflection = String(reflection.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
            result = Rules.settle(&l)
        }
        return result
    }

    // MARK: 回声

    func addHypothesis(_ text: String) {
        let text = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
        guard !text.isEmpty else { return }
        log("hypothesis", text)
    }

    /// 界面使了一次坏：taken = 你被带走了；否则是你亲手拦下的。
    func logBait(taken: Bool, _ text: String, task: String? = nil) {
        mutate { l in
            var e = LogEvent(date: l.days.last?.id ?? Clock.dayID(), time: Clock.timeLabel(), type: "bait", text: text, task: task)
            e.taken = taken
            l.events.append(e)
        }
    }

    func logSimulation(task: String?, records: [SimRecord], elapsed: Int) {
        mutate { l in
            var e = LogEvent(date: l.days.last?.id ?? Clock.dayID(), time: Clock.timeLabel(), type: "simulation",
                             text: "一轮反向体验，留下 \(records.count) 条试玩记录", task: task)
            e.records = Array(records.prefix(12))
            e.elapsedSeconds = max(0, elapsed)
            l.events.append(e)
        }
    }

    // MARK: 夜谈

    var talkStats: TalkStats { s.game ?? TalkStats() }

    func recordTalk(winner: String) {
        mutate { l in
            var g = l.game ?? TalkStats()
            g.played += 1
            if winner == "villagers" { g.wins += 1 }
            g.wins = min(g.wins, g.played)
            g.lastResult = winner
            l.game = g
        }
    }

    /// 记下一次真正提交的夜谈动作。同一局同一轮同一类动作只记一次。
    @discardableResult
    func trace(_ t: Trace) -> Bool {
        guard !demo, !t.session.isEmpty else { return false }
        var t = t
        t.key = [t.mode, t.session, t.kind, String(t.round), String(t.kind == "vote" ? (t.voteAttempt ?? 1) : 0)].joined(separator: ":")
        guard !s.events.contains(where: { $0.trace?.key == t.key }) else { return false }
        let text: String
        switch t.kind {
        case "strategy":
            text = "第 \(t.round) 轮，采用「\(t.strategyLabel ?? Strategy.names[min(3, max(0, t.strategyTier ?? 0))])」"
        case "vote":
            text = "第 \(t.round) 轮，指认 \(t.targetSeat ?? 0) 号席位\(t.voteAttempt == 2 ? "（平票重投）" : "")"
        default:
            text = "本局结束：\(t.winner == "villagers" ? "钥匙找回来了" : "钥匙没找回来")"
        }
        mutate { l in
            var e = LogEvent(date: l.days.last?.id ?? Clock.dayID(), time: Clock.timeLabel(), type: "game-" + t.kind, text: text)
            e.trace = t
            l.events.append(e)
        }
        return true
    }

    // MARK: 设置、示例、备份

    func setTone(sharp: Bool) {
        mutate { $0.tone = sharp ? "sharp" : "gentle" }
    }

    func enterDemo() {
        guard !demo else { return }
        real = s
        demo = true
        var l = Ledger(today: Clock.dayID())
        var a = Quest(id: "demo-quest-1", title: "把第一版方案发给一个人", bonus: false, estimate: 25,
                      step: "把现有草稿发给小林，问他哪一段看不懂", seed: 0)
        a.prep = 1
        a.decision = "继续准备"
        let b = Quest(id: "demo-quest-2", title: "读完一篇参考文章", bonus: true, estimate: 15, seed: 1)
        l.days[0].tasks = [a, b]
        Rules.log(&l, "create", "示例：写下必做「把第一版方案发给一个人」，预计 25 分钟", task: a.id)
        Rules.log(&l, "decision", "示例：第 1 次继续准备，理由：「还想再找一份参考」", task: a.id)
        s = l
    }

    func exitDemo() {
        guard demo else { return }
        demo = false
        s = real
        rolloverIfNeeded()
    }

    #if DEBUG
    /// 调试截图用：换上一份示例账本，不写盘。
    func debugLoad(_ ledger: Ledger) {
        if !demo { real = s }
        demo = true
        s = ledger
    }
    #endif

    func exportData() -> Data? { s.data(pretty: true) }

    var exportName: String { Backup.filename(demo: demo, today: Clock.dayID()) }

    func apply(backup: Ledger) {
        demo = false
        s = backup
        loadWarning = false
        var copy = s
        Rules.rollover(&copy)
        s = copy
        persist()
    }
}
