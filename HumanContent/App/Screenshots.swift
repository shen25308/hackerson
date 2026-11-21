#if DEBUG
import SwiftUI

/// 只在调试版里生效：用启动参数 `-shot <场景>` 直接摆好一个画面，方便在模拟器里截图检查。
/// 例如：xcrun simctl launch booted com.hackerson.humancontent -shot tasks
enum Screenshots {
    static var scene: String? { UserDefaults.standard.string(forKey: "shot") }

    static func apply(store: Store, stage: Stage) {
        guard let scene else { return }
        SoundEngine.shared.enabled = false
        if scene != "empty" { store.debugLoad(sample()) }
        let first = store.today.tasks.first { !$0.done }
        switch scene {
        case "map", "sound", "music", "help":
            stage.sheet = scene == "map" ? .map : scene == "sound" ? .sound : scene == "music" ? .music : .help
        case "labmenu": stage.sheet = .labMenu
        case "district-decisions", "district-mirror", "district-experiment":
            stage.sheet = .district(String(scene.dropFirst(9)))
        case "tasks", "add", "empty": stage.tab = .tasks
        case "detail", "complete":
            if let first { stage.openTask(first.id) }
        case "settle": stage.openSettle()
        case "council", "cut":
            stage.openCouncil(task: first?.id)
        case "council-cut":
            if let first {
                _ = store.cut(first.id, seat: Rules.stringSeat(first, topic: first.topic))
                store.inspect(first.id)
                stage.openCouncil(task: first.id)
            }
        case "talk": stage.openTalk(online: false)
        case "talk-game", "talk-vote", "talk-end":
            var game = KeyCase(seed: 7)
            if scene != "talk-game" { game.statement(optionId: "strategy-1", completed: store.gateCount) }
            if scene == "talk-end" { game.vote(targetId: game.keeperId) }
            TalkTable.shared.demoSeen = store.demo
            TalkTable.shared.game = game
            TalkTable.shared.session = "shot"
            TalkTable.shared.recorded = true
            stage.openTalk(online: false)
        case "talk-online": stage.openTalk(online: true)
        case "puppets": stage.tab = .puppets
        case "echo": stage.tab = .echo
        default:
            if scene.hasPrefix("lab-") { stage.startLab(level: String(scene.dropFirst(4)), task: first) }
        }
    }

    /// 一份有几天历史的示例账本。
    static func sample() -> Ledger {
        let cal = Calendar.current
        let now = Date()
        func dayID(_ back: Int) -> String { Clock.dayID(cal.date(byAdding: .day, value: -back, to: now) ?? now) }
        var l = Ledger(today: dayID(2))
        l.xp = 41
        l.hp = 78
        l.attack = 3
        l.streak = 2
        l.draws = 1
        l.cards = [
            Keepsake(date: dayID(2), name: "一支旧箭", effect: "专注 +1", kind: 0),
            Keepsake(date: dayID(1), name: "荆棘里的灯", effect: "韧性 +1", kind: 1),
            Keepsake(date: dayID(1), name: "琥珀药瓶", effect: "生命 +8", kind: 2),
        ]
        func done(_ title: String, _ estimate: Int, _ actual: Int, bonus: Bool = false) -> Quest {
            var q = Quest(title: title, bonus: bonus, estimate: estimate, seed: 1)
            q.done = true
            q.grade = .full
            q.actual = actual
            q.xpParts = Rules.xpParts(for: q, grade: .full, actual: actual, focusedMinutes: 3, in: l)
            q.earned = Rules.total(q.xpParts)
            q.healed = bonus ? 0 : 2
            return q
        }
        var d0 = Day(id: dayID(2))
        d0.tasks = [done("把第一版方案发给小林", 25, 22), done("读完一篇参考文章", 15, 30, bonus: true)]
        d0.closed = true
        d0.awarded = 1
        d0.bonusXP = 4
        d0.reflection = "先给人看一版，再决定改什么"
        var d1 = Day(id: dayID(1))
        var missed = Quest(title: "整理实验数据", bonus: false, estimate: 40, seed: 0)
        missed.prep = 2
        d1.tasks = [done("回复审稿意见第一条", 30, 28), missed]
        d1.closed = true
        d1.loss = 9
        var d2 = Day(id: dayID(0))
        var open = Quest(title: "把摘要改到 200 字以内", bonus: false, estimate: 25, step: "先删掉第二段的背景介绍", seed: 2)
        open.prep = 1
        open.decision = "继续准备"
        var partial = Quest(title: "画出第三张示意图", bonus: false, estimate: 45, seed: 1)
        partial.done = true
        partial.grade = .partial
        partial.xpParts = Rules.xpParts(for: partial, grade: .partial, actual: nil, focusedMinutes: 0, in: l)
        partial.earned = Rules.total(partial.xpParts)
        partial.healed = 1
        let extra = Quest(title: "给实验室群发一条进度", bonus: true, estimate: 5, seed: 0)
        d2.tasks = [done("给导师发会议时间", 10, 9), partial, open, extra]
        l.days = [d0, d1, d2]
        func event(_ day: Int, _ time: String, _ type: String, _ text: String, taken: Bool? = nil, trace: Trace? = nil) {
            var e = LogEvent(date: dayID(day), time: time, type: type, text: text)
            e.taken = taken
            e.trace = trace
            l.events.append(e)
        }
        event(2, "09:12", "create", "写下必做「把第一版方案发给小林」，预计 25 分钟")
        event(2, "09:40", "done", "确认完成「把第一版方案发给小林」，预计 25 / 实际 22 分钟，经验 +13")
        event(2, "09:41", "bait", "登记完成时，没有点“一键全部打勾”", taken: false)
        event(1, "14:03", "bait", "议事时没出手，倒计时替你剪了一张字条", taken: true)
        event(1, "21:30", "settle", "收工：1 项登记完成，生命 -9，经验 +13，抽牌 +0")
        event(0, "08:55", "bait", "写待办时，没让界面替你把话说完", taken: false)
        event(0, "09:20", "hypothesis", "下次先发草稿，看看是否真的需要再准备一小时")
        for (i, tier) in [0, 1, 1].enumerated() {
            var t = Trace(kind: "strategy", mode: "solo", session: "sample-\(i)", round: 1, completedCount: 3, unlockedTier: 2)
            t.strategyTier = tier
            t.key = "solo:sample-\(i):strategy:1:0"
            event(1, "20:0\(i)", "game-strategy", "第 1 轮，采用「\(Strategy.names[tier])」", trace: t)
            var v = Trace(kind: "vote", mode: "solo", session: "sample-\(i)", round: 1, completedCount: 3, unlockedTier: 2)
            v.targetSeat = 2 + i
            v.voteAttempt = 1
            v.key = "solo:sample-\(i):vote:1:1"
            event(1, "20:1\(i)", "game-vote", "第 1 轮，指认 \(2 + i) 号席位", trace: v)
        }
        var stats = TalkStats()
        stats.played = 3
        stats.wins = 2
        l.game = stats
        return l
    }
}
#endif
