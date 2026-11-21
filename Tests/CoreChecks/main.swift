// 核心规则与音效合成的自检。不依赖 Xcode，见同目录的 run.sh。
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String, line: Int = #line) {
    if !ok { failures += 1; print("FAIL line \(line): \(what)") }
}

// ---- engine parity dump ----
let args = CommandLine.arguments
if args.count > 2, args[1] == "engine" {
    var out: [[String: Any]] = []
    for seedStr in args[2...] {
        let seed = UInt32(seedStr)!
        var g = KeyCase(seed: seed)
        var rounds: [[String: Any]] = []
        while g.stage != .finished {
            _ = g.statement(optionId: "strategy-0", completed: 0)
            // always vote first alive bot that is not me (deterministic)
            let target = g.players.first { $0.alive && $0.id != "me" }!.id
            _ = g.vote(targetId: target)
            rounds.append(["votes": g.votes.map { "\($0.voterId)>\($0.targetId ?? "-")" }, "elim": g.reveal?.eliminatedId ?? "-", "tie": g.reveal?.tie ?? false])
            if g.stage == .reveal { _ = g.next() }
        }
        out.append(["seed": Int(seed), "wolf": g.keeperId, "cand": g.candidateIds, "excl": g.excludedId, "wit": g.witnessId, "rounds": rounds, "winner": g.result!.winner])
    }
    let d = try! JSONSerialization.data(withJSONObject: out, options: [.sortedKeys])
    print(String(data: d, encoding: .utf8)!)
    exit(0)
}
if args.count > 2, args[1] == "validate" {
    let d = try! Data(contentsOf: URL(fileURLWithPath: args[2]))
    do { let l = try Backup.validate(d); print("OK days=\(l.days.count) tasks=\(l.days.reduce(0){$0+$1.tasks.count}) events=\(l.events.count) cards=\(l.cards.count)")
        if args.count > 3 { try! l.data(pretty: true)!.write(to: URL(fileURLWithPath: args[3])) }
    } catch let e as BackupError { print("ERR \(e.message)") } catch { print("ERR other") }
    exit(0)
}

// ---- rules ----
let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("hc-test-\(UUID().uuidString)")
let ud = UserDefaults(suiteName: "hc-test-\(UUID().uuidString)")!
let store = Store(directory: tmp, defaults: ud)
check(store.s.hp == 84 && store.xp == 0, "fresh")
let a = store.addQuest(title: "写方案", bonus: false, estimate: 25, step: "")!
let b = store.addQuest(title: "读文章", bonus: true, estimate: 15, step: "")!
let c = store.addQuest(title: "发邮件", bonus: false, estimate: 10, step: "")!
check(store.today.tasks.count == 3, "3 tasks")
check(store.damage == 12 - 1 - 2, "damage 9 (gatekeeper)")
// preview: required, attack 2, on time, no prep => 6+2+3+1 = 12
var parts = store.preview(a, grade: .full, actual: 25, focusedMinutes: 0)
check(Rules.total(parts) == 12, "full on-time xp 12 got \(Rules.total(parts)) \(parts)")
parts = store.preview(a, grade: .full, actual: 60, focusedMinutes: 3)
check(Rules.total(parts) == 6 + 2 + 0 + 1 + 1, "over-estimate with timer = 10 got \(Rules.total(parts))")
parts = store.preview(a, grade: .partial, actual: nil, focusedMinutes: 0)
check(Rules.total(parts) == 4 + 1, "partial = 8/2 + 1 got \(Rules.total(parts)) \(parts)")
parts = store.preview(b, grade: .full, actual: 10, focusedMinutes: 0)
check(Rules.total(parts) == 8 + 2 + 1, "bonus fast = 11 got \(Rules.total(parts))")
// prep penalties
store.decide(a, .prepare("缺材料")); store.decide(a, .prepare("还缺")); store.decide(a, .prepare("再来"))
check(store.quest(a)!.prep == 3, "prep 3")
parts = store.preview(a, grade: .full, actual: nil, focusedMinutes: 0)
check(Rules.total(parts) == 6 + 2 - 2, "prep 3 → -2, got \(Rules.total(parts))")
// council cut
let seat = Rules.stringSeat(store.quest(a)!, topic: 0)
check(store.cut(a, seat: seat) == true, "cut hit")
check(store.cut(a, seat: seat) == nil, "cut twice nil")
parts = store.preview(a, grade: .full, actual: nil, focusedMinutes: 0)
check(Rules.total(parts) == 6 + 2 - 2 + 1, "cut bonus")
store.setTopic(a, 1)
let wrong = (Rules.stringSeat(store.quest(a)!, topic: 1) + 1) % 3
check(store.cut(a, seat: wrong, byInterface: true) == false, "interface cut wrong")
store.toggleSuspect(a, seat: 2); store.toggleSuspect(a, seat: 0); store.toggleSuspect(a, seat: 2)
check(store.quest(a)!.rounds[1]!.suspects == [0], "suspects")
check(store.rebut(a, seat: 1, text: " 不同意 "), "rebut")
check(store.quest(a)!.rounds[1]!.replies[1] == "不同意", "reply stored")
// complete
let done = store.complete(a, grade: .full, actual: 30, context: "顺利", focusedMinutes: 0)!
check(done.xp == 6 + 2 + 3 - 2 + 1, "complete xp \(done.xp)")
check(done.heal == 2 && store.hp == 86, "heal")
check(done.opened.map(\.id) == ["decisions"], "opened decisions: \(done.opened.map(\.id))")
check(done.newStrategy == "对照前后发言", "new strategy")
check(store.completed == 1, "completed 1")
check(store.complete(a, grade: .full, actual: nil, context: "", focusedMinutes: 0) == nil, "no double complete")
// partial then upgrade
let p = store.complete(c, grade: .partial, actual: nil, context: "", focusedMinutes: 0)!
check(p.quest.isPartial && store.completed == 1 && p.heal == 1, "partial")
check(Rules.misses(store.today).map(\.id) == [c], "partial is a miss")
check(Rules.lossLines(store.today, store.s).map(\.loss) == [5], "partial half damage 5 got \(Rules.lossLines(store.today, store.s).map(\.loss))")
let up = store.complete(c, grade: .full, actual: 10, context: "", focusedMinutes: 2)!
check(up.quest.isFull && store.completed == 2 && up.opened.map(\.id) == ["backstage"], "upgrade partial→full opened \(up.opened.map(\.id))")
check(store.undo(c) && store.completed == 1 && store.quest(c)!.earned == 0, "undo")
// settle with a miss
let xpBefore = store.xp
let r = Rules.rewards(store.today, store.s)
check(!r.clear && r.bonusXP == 1 && r.draws == 0, "rewards: half done → +1 \(r)")
let st = store.settle(reflection: "明天先发")!
check(st.loss == 9 && store.s.hp == 86 - 9, "settle loss 9 hp \(store.s.hp)")
check(store.s.xp == xpBefore + 1 && store.closed, "xp settled + bonus")
check(store.settle(reflection: "") == nil, "no double settle")
check(store.addQuest(title: "x", bonus: false, estimate: 1, step: "") == nil, "closed day rejects")
// persistence round trip
let store2 = Store(directory: tmp, defaults: ud)
check(store2.s == store.s, "reload equals")
// rollover
var l = store.s
let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
check(Rules.rollover(&l, now: tomorrow) && l.days.count == 2 && l.days.last!.id == Clock.dayID(tomorrow), "rollover")
let later = Calendar.current.date(byAdding: .day, value: 5, to: Date())!
var l2 = Ledger(today: Clock.dayID()); l2.streak = 4
l2.days[0].tasks = [Quest(title: "t", bonus: false, estimate: 5)]
check(Rules.rollover(&l2, now: later) && l2.streak == 0 && l2.days[0].closed && l2.hp == 84 - 9, "rollover settles + streak reset hp \(l2.hp)")
// clear day with bonus → draws, streak
var l3 = Ledger(today: Clock.dayID()); l3.streak = 2
var q1 = Quest(title: "a", bonus: false, estimate: 5); q1.done = true; q1.earned = 9; q1.healed = 2; q1.grade = .full
var q2 = Quest(title: "b", bonus: true, estimate: 5); q2.done = true; q2.earned = 8; q2.grade = .full
l3.days[0].tasks = [q1, q2]
let s3 = Rules.settle(&l3)!
check(s3.draws == 2 && s3.streak == 3 && s3.bonusXP == 4 && l3.xp == 9 + 8 + 4 && l3.hp == 86 && s3.loss == 0, "clear day \(s3)")
// demo
store.enterDemo(); check(store.demo && store.today.tasks.count == 2 && store.quest("demo-quest-1")?.prep == 1, "demo")
_ = store.complete("demo-quest-1", grade: .full, actual: nil, context: "", focusedMinutes: 0)
store.exitDemo(); check(!store.demo && store.s == store2.s, "exit demo restores")
// baits
store.logBait(taken: true, "x"); store.logBait(taken: false, "y"); store.logBait(taken: false, "z")
check(Rules.humanContent(store.s).percent == 67, "human content 67 got \(Rules.humanContent(store.s))")
// draw
var l4 = Ledger(today: Clock.dayID()); l4.draws = 1
// export → validate
let exported = store.exportData()!
do { let back = try Backup.validate(exported); check(back == store.s, "export→validate equal") } catch { check(false, "validate own export threw \(error)") }
// focus timer
let ft = FocusTimer(defaults: ud)
ft.start("t1", date: Clock.dayID(), demo: false); check(ft.isActive(for: "t1"), "focus active")
ft.pause(); check(ft.state?.running == false, "paused"); ft.resume(); _ = ft.stop(); check(ft.activeTask == nil, "stopped")
check(FocusTimer.format(3725) == "01:02:05" && FocusTimer.format(65) == "01:05", "format")
// atlas
check(Atlas.next(completed: 0)?.id == "decisions" && Atlas.next(completed: 6) == nil, "atlas next")
check(Atlas.sceneOpen(3, completed: 3) == false && Atlas.sceneOpen(3, completed: 4), "scene fog")
// estimate suggestion
var l5 = Ledger(today: "2026-01-03")
for (i, m) in [30, 10, 20].enumerated() { var q = Quest(title: "同名", bonus: false, estimate: 15); q.done = true; q.actual = m; q.grade = .full; var d = Day(id: "2026-01-0\(i+1)"); d.tasks = [q]; if i == 0 { l5.days = [d] } else { l5.days.append(d) } }
check(Rules.estimateSuggestion(title: "同名", in: l5)?.minutes == 20, "median")
// synth
var total = 0.0
for cue in Cue.allCases {
    let buf = CueBook.render(cue)
    total += buf.duration
    check(buf.peak > 0.01 && buf.peak < 0.99, "\(cue.rawValue) peak \(buf.peak)")
    check(buf.duration > 0.02 && buf.duration < 1.6, "\(cue.rawValue) dur \(buf.duration)")
    check(!buf.left.contains { $0.isNaN }, "\(cue.rawValue) NaN")
}
let amb = CueBook.ambience(); check(amb.peak > 0.005 && amb.peak < 0.5, "ambience peak \(amb.peak)")
print("cues: \(Cue.allCases.count), total \(String(format: "%.1f", total))s")
// wav dump for inspection
func wav(_ b: StereoBuffer, _ path: String) {
    var d = Data(); let n = b.left.count
    func u32(_ v: UInt32) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 4)) }
    func u16(_ v: UInt16) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 2)) }
    d.append("RIFF".data(using: .ascii)!); u32(UInt32(36 + n * 4)); d.append("WAVEfmt ".data(using: .ascii)!)
    u32(16); u16(1); u16(2); u32(44100); u32(44100 * 4); u16(4); u16(16); d.append("data".data(using: .ascii)!); u32(UInt32(n * 4))
    for i in 0..<n { u16(UInt16(bitPattern: Int16(max(-1, min(1, b.left[i])) * 32767))); u16(UInt16(bitPattern: Int16(max(-1, min(1, b.right[i])) * 32767))) }
    try! d.write(to: URL(fileURLWithPath: path))
}
if args.count > 1, args[1] == "wav" { try? FileManager.default.createDirectory(atPath: "wav", withIntermediateDirectories: true); for cue in Cue.allCases { wav(CueBook.render(cue), "wav/\(cue.rawValue).wav") } }
print(failures == 0 ? "ALL PASS" : "\(failures) FAILURES")
exit(failures == 0 ? 0 : 1)
