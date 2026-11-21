import Foundation

/// 行为回声的统计。只数留下来的记录，不给人下结论。
struct EchoSummary {
    var total = 0
    var completed = 0
    var timed = 0
    var estimatedMinutes = 0
    var actualMinutes = 0
    var overEstimate = 0
    var strategies = 0
    var votes = 0
    var finished = 0
    var strategyCounts = [0, 0, 0, 0]
    var evidence: [LogEvent] = []
    var hypotheses: [LogEvent] = []
    var baits: [LogEvent] = []

    var ratio: Int? { total > 0 ? Int((Double(completed) / Double(total) * 100).rounded()) : nil }
}

enum Echo {
    /// 夜谈里真正提交过、且结构完整的动作，去掉重复的。
    static func talkEvidence(_ s: Ledger, demo: Bool) -> [LogEvent] {
        guard !demo else { return [] }
        var seen = Set<String>()
        return s.events.filter { e in
            guard let t = e.trace, t.isValid, e.type == "game-" + t.kind else { return false }
            let key = [t.mode, t.session, t.kind, String(t.round), String(t.kind == "vote" ? (t.voteAttempt ?? 1) : 0)].joined(separator: ":")
            return seen.insert(key).inserted
        }
    }

    static func summary(_ s: Ledger, demo: Bool) -> EchoSummary {
        var out = EchoSummary()
        let quests = Rules.allQuests(s).map(\.quest)
        let done = quests.filter(\.isFull)
        let timed = done.filter { $0.estimate > 0 && $0.actual != nil }
        out.total = quests.count
        out.completed = done.count
        out.timed = timed.count
        out.estimatedMinutes = timed.reduce(0) { $0 + $1.estimate }
        out.actualMinutes = timed.reduce(0) { $0 + ($1.actual ?? 0) }
        out.overEstimate = timed.filter { ($0.actual ?? 0) > $0.estimate }.count
        out.evidence = talkEvidence(s, demo: demo)
        for e in out.evidence {
            guard let t = e.trace else { continue }
            switch t.kind {
            case "strategy":
                out.strategies += 1
                if let tier = t.strategyTier, (0...3).contains(tier) { out.strategyCounts[tier] += 1 }
            case "vote": out.votes += 1
            default: out.finished += 1
            }
        }
        out.hypotheses = demo ? [] : s.events.filter { $0.type == "hypothesis" }
        out.baits = s.events.filter { $0.type == "bait" }
        return out
    }

    /// 根据现有记录，给下一次提一个可以验证的小动作。
    static func suggestion(_ d: EchoSummary) -> String {
        if d.timed == 0 { return "下次选一项小任务，先记预计分钟数，做完后补上实际用时；看看原先的估计差在哪里。" }
        if d.timed < 3 { return "下次再为一项相近的任务留下预计和实际用时，凑够三次，再决定要不要调整估计。" }
        if d.strategies == 0 { return "下次坐下一局夜谈，先选一手策略，指认前写下自己依据的是哪条公开事实；结束后再核对。" }
        if d.strategyCounts.contains(0) { return "下次选一手已经开放、还没用过的策略。指认前看它给了什么新依据，结束后核对它有没有改变你的选择。" }
        return "下次指认前，先写一条最可能推翻自己判断的公开证据；结局后再看它有没有出现。一次只验证这一件事。"
    }

    static func describe(_ t: Trace) -> String {
        switch t.kind {
        case "strategy": return "采用「\(t.strategyLabel ?? Strategy.names[min(3, max(0, t.strategyTier ?? 0))])」"
        case "vote": return "指认 \(t.targetSeat ?? 0) 号席位" + (t.voteAttempt == 2 ? " · 平票重投" : "")
        default: return t.winner == "villagers" ? "钥匙找回来了" : "钥匙没找回来"
        }
    }

    static func typeLabel(_ type: String) -> String {
        switch type {
        case "vote": return "字条"
        case "done": return "现实行动"
        case "undo": return "撤销"
        case "bait": return "界面使坏"
        case "simulation": return "反向体验"
        case "hypothesis": return "假设"
        case "settle": return "收工"
        case "card": return "抽牌"
        default: return type.hasPrefix("game-") ? "夜谈" : "记录"
        }
    }
}
