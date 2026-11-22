// 四夜之约引擎的自检：50 局随机对局、续玩、门槛。见同目录的 run.sh。
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String, line: Int = #line) {
    if !ok { failures += 1; if failures < 30 { print("FAIL line \(line): \(what)") } }
}

let data = try! FateData.load(from: URL(fileURLWithPath: CommandLine.arguments[1]))
check(data.isUsable, "data usable")
check(data.cases.count == 12, "12 cases")
for k in data.axisOrder { check(data.cases.filter { $0.axis == k }.count == 3, "3 per axis \(k)") }
check(data.types.count == 16 && data.roleFit.count == 16, "16 types")
for c in data.cases where c.kind != "say" { check(c.opts.allSatisfy { $0.fx != nil }, "fx on \(c.id)") }
for c in data.cases where c.kind == "night" { check(c.opts.allSatisfy { data.nightFx[$0.fx ?? ""] != nil }, "nightFx known \(c.id)") }
for (_, f) in data.roleFit { check(data.puppets[f.main] != nil && f.alt.allSatisfy { data.puppets[$0] != nil }, "fit puppets known") }
let allText = String(data: try! Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])), encoding: .utf8)!
for bad in ["狼人", "放逐", "村民", "天黑请闭眼"] { check(!allText.contains(bad), "no \(bad)") }

/// 走完一整局。stopAt：走到某个阶段时停下，返回半局。
func play(seed: UInt64, role: RoleID, completed: Int, answerSeed: UInt64, stopAfterSteps: Int? = nil, from start: FateGame? = nil) -> (FateGame, Int) {
    var g = start ?? FateGame.new(role: role, data: data, seed: seed)
    var pick = FateRNG(seed: answerSeed)
    var steps = 0
    while g.phase != .verdict {
        if let stop = stopAfterSteps, steps >= stop { return (g, steps) }
        steps += 1
        switch g.phase {
        case .intro, .finale:
            g.advance()
        case .nightAsk:
            guard g.canEnter(night: g.night, completed: completed) else { return (g, steps) }
            let c = g.currentCase(data)!
            g.answer(c, option: Int.random(in: 0..<c.opts.count, using: &pick), data: data)
            g.advance()
        case .dawn:
            let before = g.dead.count
            let d = g.playDawn()
            check(g.dead.count == before + (d.victim == nil ? 0 : 1), "one death at most per dawn")
            if let v = d.victim { check(!g.seat(v)!.puller && !g.seat(v)!.me, "victim is a keeper, not me") }
        case .dayAsk:
            let c = g.currentCase(data)!
            g.answer(c, option: Int.random(in: 0..<c.opts.count, using: &pick), data: data)
            g.advance()
        case .vote:
            let c = g.currentCase(data)!
            let before = g.exiled.count
            let e = g.playVote(c, option: Int.random(in: 0..<c.opts.count, using: &pick), data: data)
            check(g.exiled.count == before + 1 && e.seat != nil && e.seat != "me", "one exile per vote")
        case .ties:
            for k in g.ties(data) {
                let t = data.tiebreak[k]!
                g.tiebreaks[k] = t.opts[Int.random(in: 0..<t.opts.count, using: &pick)].v
            }
            check(g.ties(data).isEmpty, "ties resolved")
            _ = g.tally(data)
        case .verdict:
            break
        }
    }
    return (g, steps)
}

var types = Set<String>(), wins = [String: Int]()
let roles: [RoleID] = [.gatekeeper, .tracker, .apothecary]
for i in 0..<50 {
    let role = roles[i % 3]
    let fresh = FateGame.new(role: role, data: data, seed: UInt64(1000 + i))
    check(fresh.seats.count == 10, "10 seats")
    check(fresh.seats.filter(\.puller).count == 3, "3 pullers")
    check(fresh.seats.filter(\.me).count == 1 && fresh.me?.image == ROLES[role]!.art, "me seat")
    check(Set(fresh.seats.map(\.name)).count == 10, "unique names")
    check(fresh.seats.filter(\.puller).allSatisfy { data.pullerPuppets.contains($0.puppet) }, "puller arts")
    check(fresh.seats.filter { !$0.puller && !$0.me }.allSatisfy { data.goodPuppets.contains($0.puppet) }, "keeper arts")
    let (g, _) = play(seed: UInt64(1000 + i), role: role, completed: 3, answerSeed: UInt64(77 + i))
    check(g.phase == .verdict && g.finished, "verdict reached \(i)")
    check(g.me!.alive, "me alive")
    check(g.answers.count == 12, "12 answers (\(g.answers.count))")
    let r = g.result!
    check(r.type.range(of: "^[EI][SN][TF][JP]$", options: .regularExpression) != nil, "type \(r.type)")
    for k in data.axisOrder { let a = data.axes[k]!; check(r.pct[a.a]! + r.pct[a.b]! == 100, "pct pair") }
    check(r.typeInfo != nil && r.fit != nil, "type info + fit")
    check(r.pullerNames.count == 3, "puller names")
    check(r.rightVotes + r.wrongVotes == 4, "4 votes")
    check(g.dead.count + g.exiled.count + g.aliveSeats.count == 10, "seat accounting")
    // 决定性：同一个种子再打一遍，结果一样
    let (g2, _) = play(seed: UInt64(1000 + i), role: role, completed: 3, answerSeed: UInt64(77 + i))
    check(g2.result!.type == r.type && g2.dead == g.dead && g2.exiled == g.exiled, "deterministic")
    types.insert(r.type)
    wins[r.win, default: 0] += 1
}

// 读档：在每一个可能的位置存档→解码→接着走，结果与一口气走完相同，不会重复死人
var resumeChecks = 0
for i in 0..<10 {
    let seed = UInt64(500 + i), ans = UInt64(900 + i)
    let (full, total) = play(seed: seed, role: .gatekeeper, completed: 3, answerSeed: ans)
    for stop in 1..<total {
        let (half, _) = play(seed: seed, role: .gatekeeper, completed: 3, answerSeed: ans, stopAfterSteps: stop)
        let blob = try! JSONEncoder().encode(half)
        let loaded = try! JSONDecoder().decode(FateGame.self, from: blob)
        check(loaded == half, "codable round trip")
        // 用同一串回答接着走：先把答题随机数推进到同一位置
        var g = loaded
        var pick = FateRNG(seed: ans)
        // 重放：把已经用掉的回答随机数消耗掉
        var replay = FateGame.new(role: .gatekeeper, data: data, seed: seed)
        var s = 0
        while s < stop {
            s += 1
            switch replay.phase {
            case .intro, .finale: replay.advance()
            case .nightAsk, .dayAsk:
                let c = replay.currentCase(data)!; replay.answer(c, option: Int.random(in: 0..<c.opts.count, using: &pick), data: data); replay.advance()
            case .dawn: _ = replay.playDawn()
            case .vote:
                let c = replay.currentCase(data)!; _ = replay.playVote(c, option: Int.random(in: 0..<c.opts.count, using: &pick), data: data)
            case .ties:
                for k in replay.ties(data) { let t = data.tiebreak[k]!; replay.tiebreaks[k] = t.opts[Int.random(in: 0..<t.opts.count, using: &pick)].v }
                _ = replay.tally(data)
            case .verdict: break
            }
        }
        check(replay == loaded, "replay matches saved")
        while g.phase != .verdict {
            switch g.phase {
            case .intro, .finale: g.advance()
            case .nightAsk, .dayAsk:
                let c = g.currentCase(data)!; g.answer(c, option: Int.random(in: 0..<c.opts.count, using: &pick), data: data); g.advance()
            case .dawn: _ = g.playDawn()
            case .vote:
                let c = g.currentCase(data)!; _ = g.playVote(c, option: Int.random(in: 0..<c.opts.count, using: &pick), data: data)
            case .ties:
                for k in g.ties(data) { let t = data.tiebreak[k]!; g.tiebreaks[k] = t.opts[Int.random(in: 0..<t.opts.count, using: &pick)].v }
                _ = g.tally(data)
            case .verdict: break
            }
        }
        check(g.dead == full.dead && g.exiled == full.exiled && g.result?.type == full.result?.type, "resume same outcome at step \(stop)")
        check(Set(g.dead).count == g.dead.count, "no double deaths")
        resumeChecks += 1
    }
}

// 门槛：没做任务时只能打第一夜
var gated = FateGame.new(role: .tracker, data: data, seed: 42)
check(gated.nextNightNeed(completed: 0) == nil, "night 1 free")
let (stuck, _) = play(seed: 42, role: .tracker, completed: 0, answerSeed: 1, from: gated)
check(stuck.phase == .nightAsk && stuck.night == 2, "stops at night 2 with 0 tasks (\(stuck.phase) \(stuck.night))")
check(stuck.nextNightNeed(completed: 0) == 1 && stuck.nextNightNeed(completed: 1) == nil, "need 1 for night 2")
gated = stuck
gated.phase = .dawn
check(gated.nextNightNeed(completed: 1) == 1, "night 3 needs 2 → 1 more")
check(FateGame.need(forNight: 4) == 3, "night 4 needs 3")

// 打平追问：全部选中间项时四个维度都打平
var tie = FateGame.new(role: .gatekeeper, data: data, seed: 9)
for c in data.cases { tie.answers[c.id] = 0 }
check(tie.ties(data).count == 4, "all four tie")
for k in data.axisOrder { tie.tiebreaks[k] = 2 }
let tr = tie.tally(data)
check(tr.type == "ESTJ" && tr.pct["E"] == 67 && tr.pct["I"] == 33, "tiebreak tally \(tr.type) \(tr.pct)")

// 存档
let suite = "fate-test-\(UUID().uuidString)"
let ud = UserDefaults(suiteName: suite)!
let store = FateStore(defaults: ud)
check(store.game == nil && store.last == nil, "empty store")
var sg = store.newGame(role: .apothecary, data: data, seed: 3)
sg.advance(); store.update(sg)
let store2 = FateStore(defaults: ud)
check(store2.game == sg && store2.inProgress && store2.progress == 0, "store persisted")
let (done, _) = play(seed: 3, role: .apothecary, completed: 6, answerSeed: 5)
store2.update(done)
let store3 = FateStore(defaults: ud)
check(store3.last == done.result && store3.progress == 12 && !store3.inProgress, "result persisted")
store3.reset()
check(FateStore(defaults: ud).game == nil && FateStore(defaults: ud).last == nil, "reset")

// 文本模板
check(data.fill(data.lines.gate, night: 2).contains("第二夜"), "gate fill")
check(data.fill(data.lines.count, n: 7, w: 2) == "桌边还剩 7 个人，其中 2 个提线人。", "count fill")
var cg = FateGame.new(role: .gatekeeper, data: data, seed: 11)
let lines = cg.chatter("day", count: 2, data: data)
check(lines.count == 2, "chatter 2")
check(FateLine(who: "白鹿", t: "（她没说话。）").spoken == "白鹿（她没说话。）" && FateLine(who: "铁牛", t: "抓！").spoken == "铁牛：「抓！」", "spoken format")

// 下一夜编号
var up = FateGame.new(role: .gatekeeper, data: data, seed: 5)
check(up.upcomingNight == 1, "upcoming intro 1")
up.advance(); check(up.upcomingNight == 1, "upcoming nightAsk 1")
up.phase = .vote; up.night = 4; check(up.upcomingNight == nil, "no night after 4")
up.phase = .dawn; up.night = 2; check(up.upcomingNight == 3, "upcoming 3")
// 方向：起步可疑度提线人 3、守夜人 2；夜里的线索只动提线人；按证据投票多半请对人
var dir = FateGame.new(role: .gatekeeper, data: data, seed: 21)
check(dir.seats.allSatisfy { dir.doubt[$0.id] == ($0.puller ? 3 : 2) }, "start doubt 3/2")
dir.applyNight("watch", data: data)
check(dir.seats.allSatisfy { dir.doubt[$0.id] == ($0.puller ? 4 : 2) }, "watch nudges pullers only")
var evidenceHits = 0, heartHits = 0
for i in 0..<400 {
    var e = FateGame.new(role: .gatekeeper, data: data, seed: UInt64(3000 + i))
    if e.resolveExile(strategy: "evidence")?.puller == true { evidenceHits += 1 }
    var h = FateGame.new(role: .gatekeeper, data: data, seed: UInt64(3000 + i))
    if h.resolveExile(strategy: "heart")?.puller == true { heartHits += 1 }
}
check(evidenceHits > 300 && heartHits < 100, "evidence finds pullers (\(evidenceHits)/400), heart misses (\(heartHits)/400)")
print("evidence hit \(evidenceHits)/400 · heart hit \(heartHits)/400")
print("types seen: \(types.count) · wins \(wins) · resume checks \(resumeChecks)")
print(failures == 0 ? "FATE ALL PASS" : "\(failures) FAILURES")
exit(failures == 0 ? 0 : 1)
