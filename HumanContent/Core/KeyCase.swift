import Foundation

/// 五席夜谈：北门钥匙不见了。你和四位守夜人对质，最多三轮，每轮一次发言、一次指认。
/// 随机数与判定和网页版逐位一致，同一个种子会得到同一局。
struct Mulberry {
    var a: UInt32

    init(seed: UInt32) { a = seed }

    mutating func next() -> Double {
        a = a &+ 0x6d2b_79f5
        var t = a
        t = (t ^ (t >> 15)) &* (t | 1)
        t ^= t &+ ((t ^ (t >> 7)) &* (t | 61))
        return Double(t ^ (t >> 14)) / 4_294_967_296.0
    }
}

struct Seat: Identifiable, Equatable {
    var id: String
    var seat: Int
    var nickname: String
    var alive = true
    var bot = true
    var hasStatement = false
    var hasVoted = false
}

struct Statement: Equatable, Identifiable {
    var playerId: String
    var seat: Int
    var round: Int
    var text: String
    var tier: Int
    var id: String { "\(round)-\(playerId)" }
}

struct Ballot: Equatable, Identifiable {
    var voterId: String
    var targetId: String?
    var id: String { voterId }
}

struct Reveal: Equatable {
    var eliminatedId: String?
    var tie: Bool
    var text: String
}

struct RoundRecord: Equatable, Identifiable {
    var round: Int
    var statements: [Statement]
    var votes: [Ballot]
    var reveal: Reveal?
    var id: Int { round }
}

struct TalkResult: Equatable {
    /// "villagers" = 守夜人找回钥匙；"wolf" = 钥匙还在那个人手里。沿用网页版的取值。
    var winner: String
    var reason: String
    var keeperId: String?
    var roles: [String: String] = [:]
}

struct StrategyOption: Identifiable, Equatable {
    var id: String
    var tier: Int
    var label: String
    var detail: String
    var at: Int
    var unlocked: Bool
}

struct KeyCase: Equatable {
    enum Stage: String { case statement, vote, reveal, finished }

    var seed: UInt32
    var round = 1
    let maxRounds = 3
    var stage: Stage = .statement
    /// 藏钥匙的人。
    var keeperId: String
    var candidateIds: [String]
    var excludedId: String
    var witnessId: String
    var players: [Seat]
    var statements: [Statement] = []
    var votes: [Ballot] = []
    var hints: [String] = []
    var reveal: Reveal?
    var history: [RoundRecord] = []
    var result: TalkResult?
    var publicClue = ""

    private var handoverId = ""
    private var rest: [String] = []

    init(seed: UInt32 = UInt32.random(in: 0..<UInt32.max)) {
        self.seed = seed
        var random = Mulberry(seed: seed)
        var order = ["b2", "b3", "b4", "b5"]
        var i = order.count - 1
        while i > 0 {
            let j = Int((random.next() * Double(i + 1)).rounded(.down))
            order.swapAt(i, j)
            i -= 1
        }
        keeperId = order[0]
        candidateIds = Array(order.prefix(3))
        excludedId = order[2]
        witnessId = order[3]
        players = [Seat(id: "me", seat: 1, nickname: "你", alive: true, bot: false)]
        for (n, name) in ["灰耳", "灯芯", "守夜", "纸鸦"].enumerated() {
            players.append(Seat(id: "b\(n + 2)", seat: n + 2, nickname: name))
        }
        prepare()
    }

    func seat(_ id: String?) -> Seat? { players.first { $0.id == id } }

    func num(_ id: String?) -> String { seat(id).map { "\($0.seat)号" } ?? "?号" }

    private var pair: (String, String) {
        (keeperId, candidateIds.first { $0 != keeperId && $0 != excludedId } ?? "")
    }

    private mutating func prepare() {
        let (w, d) = pair
        let others = players.filter { $0.alive && $0.id != "me" && $0.id != w && $0.id != d }
        let r = round
        stage = .statement
        hints = []
        statements = []
        votes = []
        reveal = nil
        handoverId = d
        rest = others.map(\.id)
        for p in players where p.alive && p.id != "me" {
            let text: String
            if p.id == w {
                text = r == 1
                    ? "我没拿过北门钥匙。警报前，我和\(num(d))一起经过北门。"
                    : "我前面说的“没拿过”，是说没用它开门。我和\(num(d))只是路过。"
            } else if p.id == d {
                text = "我把北门钥匙交给了\(num(w))，之后去了粮仓。钥匙后来在哪，我没看见。"
            } else if p.id == others.first?.id {
                text = r == 1
                    ? "我一直在井边。警报到底几点响，我没看钟。"
                    : "刚才说“一直”太绝对，我还去钟楼送过东西，但没碰北门钥匙。"
            } else {
                text = "我在钟楼，见过\(others.first.map { num($0.id) } ?? num(d))从井边走过。只看见人，没看见钥匙。"
            }
            statements.append(Statement(playerId: p.id, seat: p.seat, round: r, text: text, tier: 0))
        }
        publicClue = "北门钥匙在警报前失踪。四名守夜人都经过值班区；先核对交接与旁证，单凭口气和签名判不了谁拿了钥匙。"
        refreshFlags()
    }

    private mutating func refreshFlags() {
        for i in players.indices {
            players[i].hasStatement = statements.contains { $0.playerId == players[i].id }
            players[i].hasVoted = votes.contains { $0.voterId == players[i].id }
        }
    }

    func options(completed: Int) -> [StrategyOption] {
        let t = Strategy.tier(completed: completed)
        return Strategy.names.indices.map { i in
            StrategyOption(id: "strategy-\(i)", tier: i, label: Strategy.names[i], detail: Strategy.details[i],
                           at: Strategy.thresholds[i], unlocked: i <= t)
        }
    }

    private func bySeat(_ ids: [String]) -> String {
        ids.sorted { (seat($0)?.seat ?? 0) < (seat($1)?.seat ?? 0) }.map { num($0) }.joined(separator: "、")
    }

    func clues(tier: Int) -> [String] {
        var out = [publicClue]
        if tier >= 1 {
            out.append("对照完整交接台账，三个待核实席位固定为 \(bySeat(candidateIds))。另一席的离场记录有独立旁证；候选整局不变。")
        }
        if tier >= 2 {
            if let prev = history.last {
                let summary = prev.votes.map { "\(num($0.voterId))→\($0.targetId.map { num($0) } ?? "弃权")" }.joined(separator: "，")
                out.append("上一轮票型：\(summary)。把选票和当时的口供放在一起：谁在跟票，谁把票投给了没人提过的席位？跟票本身还证明不了什么。")
            } else {
                out.append("首轮还没有上一轮票型。先记下各席的发言，下一轮会给出真实的选票与发言对照。")
            }
        }
        if tier >= 3 {
            out.append("交叉核对钟楼记录与井边收条，可以排除候选中的 \(num(excludedId))：失窃时该席在另一处交接。其余两席 \(bySeat([keeperId, handoverId])) 还得结合发言与选票判断。")
        }
        return out
    }

    @discardableResult
    mutating func statement(optionId: String, completed: Int) -> Bool {
        guard stage == .statement, let o = options(completed: completed).first(where: { $0.id == optionId && $0.unlocked }) else { return false }
        hints = clues(tier: o.tier)
        let lines = [
            "先把记录摆出来。嘴硬不是证据，签名也不是免死金牌。",
            "我想对照两份口供：钥匙到底拿没拿过？别用换个说法糊弄过去。",
            "请解释投票依据。跟着嗓门最大的人走，脑子是用来凑座位的吗？",
            "先排除不成立的推断。记不清时间不等于拿了钥匙，真正的冲突还得继续核对。",
        ]
        statements.append(Statement(playerId: "me", seat: 1, round: round, text: lines[o.tier], tier: o.tier))
        stage = .vote
        refreshFlags()
        return true
    }

    @discardableResult
    mutating func vote(targetId: String?) -> Bool {
        guard stage == .vote, let targetId, targetId != "me", seat(targetId)?.alive == true else { return false }
        var random = Mulberry(seed: UInt32(truncatingIfNeeded: Int(seed) + round * 917))
        let w = keeperId
        var ballots = [Ballot(voterId: "me", targetId: targetId)]
        for p in players where p.alive && p.bot {
            var target: String
            if p.id == w {
                target = players.first { $0.alive && $0.id != w && $0.id != "me" }?.id ?? "me"
            } else {
                let pool = players.filter { $0.alive && $0.id != p.id && $0.id != "me" }
                if random.next() < 0.63 {
                    target = w
                } else {
                    let k = Int((random.next() * Double(pool.count)).rounded(.down))
                    target = pool.indices.contains(k) ? pool[k].id : "me"
                }
            }
            ballots.append(Ballot(voterId: p.id, targetId: target))
        }
        // 计票顺序与网页版一致：按第一次出现的顺序，票数相同时保持先后。
        var order: [String] = []
        var counts: [String: Int] = [:]
        for b in ballots {
            guard let t = b.targetId else { continue }
            if counts[t] == nil { order.append(t) }
            counts[t, default: 0] += 1
        }
        let ranked = order.enumerated().sorted { a, b in
            let ca = counts[a.element] ?? 0, cb = counts[b.element] ?? 0
            return ca != cb ? ca > cb : a.offset < b.offset
        }.map(\.element)
        let tie = ranked.count > 1 && counts[ranked[0]] == counts[ranked[1]]
        let eliminated: String? = tie ? nil : ranked.first
        votes = ballots
        if let eliminated, let i = players.firstIndex(where: { $0.id == eliminated }) { players[i].alive = false }
        reveal = Reveal(eliminatedId: eliminated, tie: tie,
                        text: tie ? "最高票相同，这一轮没有人离席。" : "\(num(eliminated))被请离席。谁拿了钥匙，整局结束时一起揭晓。")
        history.append(RoundRecord(round: round, statements: statements, votes: ballots, reveal: reveal))
        if eliminated == w {
            finish("villagers", "第 \(round) 轮就指认出了拿钥匙的人。")
        } else if round >= maxRounds {
            finish("wolf", "三轮结束，钥匙还在那个人手里。")
        } else {
            stage = .reveal
        }
        refreshFlags()
        return true
    }

    private mutating func finish(_ winner: String, _ reason: String) {
        stage = .finished
        result = TalkResult(winner: winner, reason: reason, keeperId: keeperId)
    }

    @discardableResult
    mutating func next() -> Bool {
        guard stage == .reveal else { return false }
        round += 1
        prepare()
        return true
    }
}
