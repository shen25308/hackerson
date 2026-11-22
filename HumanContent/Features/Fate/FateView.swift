import SwiftUI

// MARK: 导演：按步骤念旁白、等你选、结算、存档

enum FateMood: String {
    case night, dawn, day, blood

    var tint: Color {
        switch self {
        case .night: return Color(red: 0.2, green: 0.08, blue: 0.34).opacity(0.42)
        case .dawn: return Color(red: 0.36, green: 0.44, blue: 0.56).opacity(0.26)
        case .day: return Color(red: 0.62, green: 0.4, blue: 0.16).opacity(0.2)
        case .blood: return Color(red: 0.46, green: 0.04, blue: 0.08).opacity(0.46)
        }
    }
}

@MainActor
final class FateDirector: ObservableObject {
    @Published var game: FateGame?
    @Published var line = ""
    @Published var typing = false
    @Published var holding = false
    @Published var ask = ""
    @Published var options: [FateOption] = []
    @Published var mood: FateMood = .night
    @Published var speaking: String?
    /// 不为 nil 时显示“下一夜还没到”的两个按钮。
    @Published var gateNeed: Int?
    @Published var verdict: FateResult?

    let data = FateData.shared
    private let fate = FateStore.shared
    private weak var store: Store?
    private var instant = false
    private var task: Task<Void, Never>?
    private var choice: CheckedContinuation<Int, Never>?
    private var skipLine = false
    private var skipHold = false
    private var lastTick = Date.distantPast

    /// 打开牌桌：看结果、接着打，或者开新局。
    func begin(store: Store, instant: Bool) {
        self.store = store
        self.instant = instant
        task?.cancel()
        gateNeed = nil
        if fate.wantsVerdict, let r = fate.last {
            fate.wantsVerdict = false
            game = fate.game
            verdict = r
            return
        }
        fate.wantsVerdict = false
        var resumed = true
        if fate.game == nil || fate.game?.finished == true {
            fate.newGame(role: store.s.role)
            resumed = false
        }
        game = fate.game
        verdict = nil
        sfx(.whoosh)
        task = Task { [weak self] in await self?.run(resumed: resumed) }
    }

    /// 合上牌桌：停掉旁白，存档。
    func stop() {
        task?.cancel()
        task = nil
        resumeChoice(-1)
        typing = false
        holding = false
        if let game { fate.update(game) }
    }

    func restart() {
        stop()
        verdict = nil
        gateNeed = nil
        line = ""
        ask = ""
        options = []
        mood = .night
        speaking = nil
        fate.game = nil
        if let store { begin(store: store, instant: instant) }
    }

    /// 点旁白：先把这一句打完，再跳过停顿。
    func tap() {
        if typing {
            skipLine = true
        } else if holding {
            skipHold = true
        }
    }

    func pick(_ index: Int) {
        guard let c = choice else { return }
        choice = nil
        sfx(.click)
        c.resume(returning: index)
    }

    // MARK: 主流程

    private func commit(_ g: FateGame) {
        game = g
        fate.update(g)
    }

    private func run(resumed: Bool) async {
        guard var g = game else { return }
        if g.phase == .intro {
            mood = .night
            await narrate(data.lines.opening, speed: 34)
            if Task.isCancelled { return }
            g.advance()
            commit(g)
        } else if resumed, g.phase != .verdict, !data.lines.resume.isEmpty {
            await narrate([data.lines.resume])
        }
        while !Task.isCancelled {
            guard let store else { return }
            switch g.phase {
            case .intro:
                g.advance()
                commit(g)
            case .nightAsk:
                let n = g.night
                if !g.canEnter(night: n, completed: store.gateCount) {
                    mood = .night
                    gateNeed = max(1, FateGame.need(forNight: n) - store.gateCount)
                    await say(data.fill(data.lines.gate, night: n))
                    return
                }
                if await playNight(&g) == false { return }
            case .dawn:
                await playDawn(&g)
            case .dayAsk:
                if await playDay(&g) == false { return }
            case .vote:
                if await playVote(&g) == false { return }
            case .finale:
                mood = .night
                await narrate(data.lines.finale, speed: 28)
                if Task.isCancelled { return }
                g.advance()
                commit(g)
            case .ties:
                if await playTies(&g) == false { return }
                return
            case .verdict:
                verdict = g.result ?? fate.last
                return
            }
            await sleep(0.4)
        }
    }

    private func playNight(_ g: inout FateGame) async -> Bool {
        mood = .night
        sfx(.countdown, strength: 0.4)
        var lines = [data.lines.night]
        if let lead = data.roleLead[g.role] { lines.append(lead) }
        await narrate(lines, speed: 30)
        await speak(g.chatter("night", count: 1, data: data))
        guard !Task.isCancelled else { return false }
        guard let c = g.currentCase(data) else {
            g.advance()
            commit(g)
            return true
        }
        await say(c.text, speed: 30)
        let i = await choose(ask: c.ask, opts: c.opts)
        guard i >= 0 else { return false }
        g.answer(c, option: i, data: data)
        g.advance()
        commit(g)
        await say(c.opts[i].r, speed: 26)
        await sleep(0.65)
        return true
    }

    private func playDawn(_ g: inout FateGame) async {
        mood = .dawn
        let dawn = g.playDawn()
        commit(g)
        if let id = dawn.victim, let s = g.seat(id) {
            sfx(.damage)
            await narrate([data.fill(data.lines.dawnDeath, name: s.name)], speed: 28)
            await speak(g.chatter("dawnDeath", count: 1, data: data))
        } else {
            sfx(.settleSafe)
            await narrate([data.fill(data.lines.dawnSafe, n: g.aliveSeats.count)], speed: 28)
            await speak(g.chatter("dawnSafe", count: 1, data: data))
        }
        if !dawn.clue.isEmpty { await narrate([dawn.clue], speed: 28) }
        commit(g)
    }

    private func playDay(_ g: inout FateGame) async -> Bool {
        mood = .day
        await speak(g.chatter("day", count: 2, data: data))
        guard !Task.isCancelled else { return false }
        guard let c = g.currentCase(data) else {
            g.advance()
            commit(g)
            return true
        }
        await say(c.text, speed: 30)
        let i = await choose(ask: c.ask, opts: c.opts)
        guard i >= 0 else { return false }
        g.answer(c, option: i, data: data)
        g.advance()
        commit(g)
        await say(c.opts[i].r, speed: 26)
        await pause(900)
        await speak(g.chatter("afterSay", count: 1, data: data))
        commit(g)
        return true
    }

    private func playVote(_ g: inout FateGame) async -> Bool {
        guard let c = g.currentCase(data) else {
            g.advance()
            commit(g)
            return true
        }
        await say(c.text, speed: 30)
        let i = await choose(ask: c.ask, opts: c.opts)
        guard i >= 0 else { return false }
        let exile = g.playVote(c, option: i, data: data)
        commit(g)
        await say(c.opts[i].r, speed: 26)
        await pause(900)
        if let id = exile.seat, let s = g.seat(id) {
            sfx(.vote)
            sfx(.stamp, delay: 0.12)
            if exile.hit {
                mood = .blood
                sfx(.revealSuccess, delay: 0.4)
                await narrate(data.lines.exileHit.map { data.fill($0, name: s.name) }, speed: 28)
                await speak(g.chatter("voteHit", count: 1, data: data))
            } else {
                sfx(.revealWrong, delay: 0.4)
                await narrate(data.lines.exileMiss.map { data.fill($0, name: s.name) }, speed: 28)
                await speak(g.chatter("voteMiss", count: 1, data: data))
            }
        }
        await narrate([data.fill(data.lines.count, n: g.aliveSeats.count, w: g.pullersAlive)], speed: 28)
        commit(g)
        await sleep(0.8)
        return !Task.isCancelled
    }

    private func playTies(_ g: inout FateGame) async -> Bool {
        let ties = g.ties(data).filter { g.tiebreaks[$0] == nil }
        if !ties.isEmpty {
            mood = .dawn
            await narrate([data.lines.ties], speed: 26)
        }
        for k in ties {
            guard let t = data.tiebreak[k] else { continue }
            await say(t.text, speed: 30)
            let i = await choose(ask: t.ask, opts: t.opts)
            guard i >= 0 else { return false }
            g.tiebreaks[k] = t.opts[i].v
            commit(g)
            await say(t.opts[i].r, speed: 26)
            await sleep(0.5)
        }
        guard !Task.isCancelled else { return false }
        let r = g.tally(data)
        commit(g)
        let nick = r.typeInfo?.nick ?? ""
        let puppet = data.puppetName(r.fit?.main ?? "")
        store?.logFate("测出 \(r.type) · \(nick) · 最像\(puppet)")
        sfx(.levelup)
        withAnimation(instant ? nil : .easeInOut(duration: 0.5)) { verdict = r }
        return true
    }

    // MARK: 念与等

    private func choose(ask: String, opts: [FateOption]) async -> Int {
        guard !Task.isCancelled else { return -1 }
        self.ask = ask
        withAnimation(instant ? nil : .easeOut(duration: 0.25)) { options = opts }
        let i = await withCheckedContinuation { (cont: CheckedContinuation<Int, Never>) in
            choice = cont
        }
        options = []
        self.ask = ""
        return i
    }

    private func resumeChoice(_ v: Int) {
        if let c = choice {
            choice = nil
            c.resume(returning: v)
        }
    }

    private func tick() {
        let now = Date()
        if now.timeIntervalSince(lastTick) > 0.07 {
            lastTick = now
            sfx(.type, strength: 0.25)
        }
    }

    /// 打字机：标点处停一拍，念起来像人说话。
    private func say(_ text: String, speed: Double = 36) async {
        skipLine = false
        guard !Task.isCancelled else { return }
        if instant || speed <= 0 {
            line = text
            return
        }
        typing = true
        line = ""
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            if Task.isCancelled || skipLine { break }
            i += 1
            line = String(chars[0..<i])
            tick()
            let ch = chars[i - 1]
            var extra = 0.0
            if "，、；：".contains(ch) {
                extra = 170
            } else if "。！？".contains(ch) {
                extra = 300
            } else if ch == "…" || ch == "—" {
                extra = 220
            }
            try? await Task.sleep(nanoseconds: UInt64((speed + extra) * 1_000_000))
        }
        line = text
        typing = false
        skipLine = false
    }

    /// 句子之间的安静；点一下可以跳过。
    private func pause(_ ms: Double) async {
        guard !Task.isCancelled else { return }
        holding = true
        skipHold = false
        let end = Date().addingTimeInterval(ms / 1000)
        while Date() < end && !skipHold && !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        holding = false
        skipHold = false
    }

    private func sleep(_ seconds: Double) async {
        guard !instant else { return }
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private func narrate(_ lines: [String], speed: Double = 32) async {
        for t in lines where !t.isEmpty {
            if Task.isCancelled { return }
            await say(t, speed: speed)
            await pause(max(1100, Double(t.count) * 46))
        }
    }

    /// 在场的人开口；谁说话，桌上那张牌就亮一下。
    private func speak(_ lines: [FateLine]) async {
        for l in lines {
            if Task.isCancelled { break }
            speaking = l.who.isEmpty ? nil : l.who
            let text = l.spoken
            await say(text, speed: 32)
            await pause(max(1100, Double(text.count) * 46))
        }
        speaking = nil
    }
}

// MARK: 牌桌

struct FateView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var stage: Stage
    @StateObject private var director = FateDirector()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Atmosphere(backdrop: .square, quiet: true)
            director.mood.tint
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .animation(reduceMotion ? nil : .easeInOut(duration: 1.2), value: director.mood)
            if let verdict = director.verdict {
                FateVerdictView(result: verdict, again: again, home: close)
                    .transition(.opacity)
            } else {
                FateTableScreen(director: director, close: close, toTasks: toTasks)
            }
        }
        .onAppear { director.begin(store: store, instant: reduceMotion) }
        .onDisappear { director.stop() }
    }

    private func close() {
        director.stop()
        sfx(.close)
        stage.fateOpen = false
    }

    private func toTasks() {
        director.stop()
        stage.fateOpen = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { stage.go(.tasks) }
    }

    private func again() {
        sfx(.drawShuffle)
        director.restart()
    }
}

struct FateTableScreen: View {
    @ObservedObject var director: FateDirector
    let close: () -> Void
    let toTasks: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            FateTopBar(game: director.game, close: close)
            FateSeatsView(seats: director.game?.seats ?? [], speaking: director.speaking)
            FateNarration(line: director.line, ask: director.ask) { director.tap() }
            if let need = director.gateNeed {
                FateGateButtons(need: need, toTasks: toTasks, later: close)
            } else {
                FateOptionsView(options: director.options, letters: director.data.letters) { director.pick($0) }
            }
            FateDials(score: director.game?.score(director.data) ?? [:], data: director.data)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }
}

struct FateTopBar: View {
    let game: FateGame?
    let close: () -> Void
    @EnvironmentObject private var store: Store

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(FateData.shared.nightName(game?.night ?? 1))
                .font(Theme.brush(26))
                .foregroundStyle(Theme.text)
            Text("\(store.role.name) · 守夜人")
                .font(.subheadline)
                .foregroundStyle(Theme.dim)
            Spacer(minLength: 6)
            Text("\(game?.aliveSeats.count ?? 10) 人在场")
                .font(.subheadline)
                .foregroundStyle(Theme.dim)
                .monospacedDigit()
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .frame(width: 36, height: 36)
                    .background(Color.black.opacity(0.5), in: Circle())
            }
            .accessibilityLabel("合上牌桌")
        }
    }
}

struct FateSeatsView: View {
    let seats: [FateSeat]
    let speaking: String?

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 10) {
            ForEach(seats) { seat in
                FateSeatCard(seat: seat, speaking: speaking != nil && speaking == seat.name)
            }
        }
    }
}

struct FateSeatCard: View {
    let seat: FateSeat
    let speaking: Bool

    private var revealed: Bool { seat.me || !seat.alive }

    var body: some View {
        VStack(spacing: 4) {
            face
                .frame(width: 50, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(border, lineWidth: seat.me || (seat.puller && !seat.alive) ? 2 : 1)
                }
                .shadow(color: speaking ? Theme.ember.opacity(0.9) : .clear, radius: speaking ? 9 : 0)
                .scaleEffect(speaking ? 1.06 : 1)
                .animation(.easeOut(duration: 0.25), value: speaking)
            Text(seat.me ? "你" : seat.name)
                .font(.caption2.weight(.medium))
                .foregroundStyle(seat.alive ? Theme.text : Theme.dim)
                .strikethrough(!seat.alive, color: Theme.dim)
                .lineLimit(1)
            if !seat.alive {
                Text(seat.puller ? "提线人" : (seat.exiled ? "出庄" : "出事"))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(seat.puller ? Theme.rose : Theme.dim)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private var face: some View {
        if revealed {
            Image(seat.image)
                .resizable()
                .scaledToFill()
                .saturation(seat.alive ? 1 : 0.35)
                .brightness(seat.alive ? 0 : -0.1)
        } else {
            ZStack {
                Theme.raised
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(Theme.ember.opacity(0.35), lineWidth: 1)
                    .padding(5)
                Image(systemName: "suit.diamond.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.ember.opacity(0.55))
            }
        }
    }

    private var border: Color {
        if seat.me { return Theme.ember }
        if seat.puller && !seat.alive { return Theme.rose }
        return Color.white.opacity(0.16)
    }

    private var label: String {
        if seat.me { return "你的座位" }
        if seat.alive { return "\(seat.name)，在场" }
        return "\(seat.name)，\(seat.exiled ? "已被请出山庄" : "已出事")\(seat.puller ? "，是提线人" : "")"
    }
}

struct FateNarration: View {
    let line: String
    let ask: String
    let tap: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)
            Text(line)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(Theme.text)
                .lineSpacing(7)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .shadow(color: .black.opacity(0.8), radius: 6)
                .accessibilityAddTraits(.updatesFrequently)
            if !ask.isEmpty {
                Text(ask)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ember)
                    .transition(.opacity)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 130, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture(perform: tap)
        .accessibilityHint("点一下跳过")
    }
}

struct FateOptionsView: View {
    let options: [FateOption]
    let letters: [String]
    let pick: (Int) -> Void

    var body: some View {
        VStack(spacing: 8) {
            ForEach(Array(options.enumerated()), id: \.offset) { i, option in
                Button {
                    pick(i)
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Text(letters.indices.contains(i) ? letters[i] : "\(i + 1)")
                            .font(Theme.title(14))
                            .foregroundStyle(Theme.ember)
                            .frame(width: 24, height: 24)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.ember.opacity(0.6), lineWidth: 1))
                        Text(option.t)
                            .font(.subheadline)
                            .foregroundStyle(Theme.text)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.text.opacity(0.14), lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
}

struct FateGateButtons: View {
    let need: Int
    let toTasks: () -> Void
    let later: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Button("去任务板 · 还差 \(need) 件", action: toTasks)
                .buttonStyle(.ember)
            Button("先收着", action: later)
                .buttonStyle(.quiet)
        }
    }
}

/// 四个维度的指针：不显示分数，只让指针慢慢偏向更像你的那一边。
struct FateDials: View {
    let score: [String: Int]
    let data: FateData

    var body: some View {
        HStack(spacing: 12) {
            ForEach(data.axisOrder, id: \.self) { k in
                if let axis = data.axes[k] {
                    FateDial(left: axis.a, right: axis.b, score: score[k] ?? 0)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}

struct FateDial: View {
    let left: String
    let right: String
    let score: Int

    var body: some View {
        let towardRight = min(0.92, max(0.08, Double(6 - score) / 12))
        HStack(spacing: 4) {
            Text(left).font(.caption2.weight(.semibold)).foregroundStyle(score > 0 ? Theme.ember : Theme.dim)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.16)).frame(width: 40, height: 3)
                Circle()
                    .fill(Theme.ember)
                    .frame(width: 7, height: 7)
                    .offset(x: towardRight * 33)
                    .animation(.spring(duration: 0.6), value: score)
            }
            .frame(width: 40, height: 8)
            Text(right).font(.caption2.weight(.semibold)).foregroundStyle(score < 0 ? Theme.ember : Theme.dim)
        }
    }
}

// MARK: 结算

struct FateVerdictView: View {
    let result: FateResult
    let again: () -> Void
    let home: () -> Void

    private var data: FateData { FateData.shared }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                FateVerdictHeader(result: result)
                FateVerdictAxes(result: result)
                FateVerdictPerson(result: result)
                FateVerdictPuppet(result: result)
                FateVerdictLedger(result: result)
                Text(data.note)
                    .font(.footnote)
                    .foregroundStyle(Theme.dim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                VStack(spacing: 10) {
                    Button("再打一局", action: again).buttonStyle(.ember)
                    Button("回山庄", action: home).buttonStyle(.quiet)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 24)
            .padding(.bottom, 40)
        }
    }
}

struct FateVerdictHeader: View {
    let result: FateResult

    var body: some View {
        let info = result.typeInfo
        VStack(spacing: 6) {
            Text("四夜之约 · 结算").font(.caption).foregroundStyle(Theme.dim)
            Text(result.type)
                .font(Theme.brush(64))
                .tracking(8)
                .foregroundStyle(Theme.text)
                .shadow(color: Theme.ember.opacity(0.35), radius: 18)
            Text("\(info?.nick ?? "") · \(FateData.shared.kinName[info?.kin ?? ""] ?? "")")
                .font(Theme.title(18))
                .foregroundStyle(Theme.ember)
            Text(info?.stack ?? "")
                .font(.footnote)
                .foregroundStyle(Theme.dim)
        }
        .frame(maxWidth: .infinity)
    }
}

struct FateVerdictAxes: View {
    let result: FateResult

    var body: some View {
        let data = FateData.shared
        VStack(alignment: .leading, spacing: 16) {
            SectionHeading("四个维度")
            ForEach(data.axisOrder, id: \.self) { k in
                if let axis = data.axes[k] {
                    FateAxisRow(axis: axis, pctA: result.pct[axis.a] ?? 50)
                }
            }
        }
        .raised()
    }
}

struct FateAxisRow: View {
    let axis: FateAxis
    let pctA: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("\(axis.a) \(axis.an)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(pctA >= 50 ? Theme.ember : Theme.dim)
                Spacer()
                Text("\(pctA)% · \(100 - pctA)%")
                    .font(.caption)
                    .foregroundStyle(Theme.dim)
                    .monospacedDigit()
                Spacer()
                Text("\(axis.b) \(axis.bn)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(pctA < 50 ? Theme.ember : Theme.dim)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.14)).frame(height: 4)
                    Circle()
                        .fill(Theme.ember)
                        .frame(width: 12, height: 12)
                        .offset(x: max(0, min(geo.size.width - 12, CGFloat(100 - pctA) / 100 * geo.size.width - 6)))
                }
                .frame(height: 12)
            }
            .frame(height: 12)
            Text(pctA >= 50 ? axis.ad : axis.bd)
                .font(.footnote)
                .foregroundStyle(Theme.dim)
        }
    }
}

struct FateVerdictPerson: View {
    let result: FateResult

    var body: some View {
        let info = result.typeInfo
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading("你是这样的人")
            Text(info?.drive ?? "")
                .font(Theme.title(18))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 10) {
                FateTrait(title: "最强", text: info?.best ?? "")
                FateTrait(title: "最怕", text: info?.fear ?? "")
            }
        }
        .raised()
    }
}

struct FateTrait: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(Theme.dim)
            Text(text).font(.subheadline).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct FateVerdictPuppet: View {
    let result: FateResult

    var body: some View {
        let data = FateData.shared
        let main = result.fit?.main ?? "villager"
        let alts = (result.fit?.alt ?? []).map { data.puppetName($0) }.joined(separator: " · ")
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading("最像你的木偶")
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 6) {
                    Image("puppet_" + main)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 92, height: 108)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Theme.ember, lineWidth: 1.5))
                    Text(data.puppetName(main)).font(Theme.title(15)).foregroundStyle(Theme.text)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Tag("最像你", color: Theme.ember, filled: true)
                    Text(result.fit?.why ?? "")
                        .font(.subheadline)
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                    if !alts.isEmpty {
                        Text("也很适合：\(alts)").font(.footnote).foregroundStyle(Theme.dim)
                    }
                }
            }
        }
        .raised()
    }
}

struct FateVerdictLedger: View {
    let result: FateResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeading("这一局的账")
            LedgerRow(label: "你的身份", value: "\(result.roleName) · 守夜人")
            LedgerRow(label: "提线人是谁", value: result.pullerNames.joined(separator: "、"), color: Theme.rose)
            LedgerRow(label: "请对 / 请错", value: "\(result.rightVotes) / \(result.wrongVotes)")
            LedgerRow(label: "结局", value: result.win == "good" ? "守夜人胜" : "提线人胜",
                      color: result.win == "good" ? Theme.moss : Theme.rose)
        }
        .raised()
    }
}
