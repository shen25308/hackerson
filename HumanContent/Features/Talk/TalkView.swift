import SwiftUI

/// 单机夜谈的桌面：一局对质，加上还没提交的指认。换页、切换议事方式都不会丢。
final class TalkTable: ObservableObject {
    static let shared = TalkTable()

    @Published var game: KeyCase?
    @Published var candidate: String?
    /// 这一局在行为回声里的编号。
    var session = ""
    var recorded = false
    /// 上次看到的是不是示例模式。进出示例时清桌。
    var demoSeen: Bool?

    func reset() {
        game = nil
        candidate = nil
        session = ""
        recorded = false
    }
}

/// 五席夜谈：北门钥匙不见了，五个人对质，最多三轮。
struct TalkView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var stage: Stage
    @StateObject private var table = TalkTable.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("北门的钥匙不见了。").font(Theme.brush(24)).foregroundStyle(Theme.text)
                progress
                Picker("入座方式", selection: $stage.talkOnline) {
                    Text("单机").tag(false)
                    Text("联机").tag(true)
                }
                .pickerStyle(.segmented)
                if stage.talkOnline {
                    OnlineTalkView()
                } else {
                    SoloTalkView(table: table)
                }
            }
            .page()
            .padding(.vertical, 12)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear { syncDemo() }
        .onChange(of: store.demo) { _, _ in syncDemo() }
        .onChange(of: stage.talkOnline) { _, _ in
            table.candidate = nil
            sfx(.nav)
        }
    }

    private var progress: some View {
        let tier = store.strategyTier
        return VStack(alignment: .leading, spacing: 8) {
            Text("夜谈第 \(tier + 1) 手 · 已整件做完 \(store.completed) 项")
                .font(.subheadline)
                .foregroundStyle(Theme.dim)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Strategy.names.indices, id: \.self) { i in
                        Tag(i <= tier ? Strategy.names[i] : "\(Strategy.names[i]) · \(Strategy.thresholds[i]) 项",
                            color: i <= tier ? Theme.ember : Theme.dim)
                    }
                }
            }
        }
    }

    /// 进出示例时清掉桌面和联机凭证：示例里的记录不该和真实的混在一起。
    private func syncDemo() {
        if let seen = table.demoSeen, seen != store.demo {
            table.reset()
            OnlineRoom.shared.resetSession()
        }
        table.demoSeen = store.demo
    }
}

// MARK: 单机

struct SoloTalkView: View {
    @ObservedObject var table: TalkTable
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var stage: Stage

    var body: some View {
        if let game = table.game {
            play(game)
        } else {
            lobby
        }
    }

    private var lobby: some View {
        let stats = store.talkStats
        return VStack(alignment: .leading, spacing: 12) {
            Text("你是守夜人。四位同伴里，有一个人拿了钥匙。").font(Theme.title(20)).foregroundStyle(Theme.text)
            Text("最多三轮。每轮说一句，再指认一席。").font(.subheadline).foregroundStyle(Theme.dim)
            Button("入座") { start() }.buttonStyle(.ember)
            if stats.played > 0 {
                Text("\(stats.played) 局 · 找回钥匙 \(stats.wins) 次").font(.footnote).foregroundStyle(Theme.dim)
            }
        }
        .raised()
    }

    @ViewBuilder
    private func play(_ g: KeyCase) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(TalkWords.stage(g.stage.rawValue)).font(Theme.title(22)).foregroundStyle(Theme.text)
            Spacer()
            Text("第 \(g.round) / \(g.maxRounds) 轮 · 你是守夜人").font(.subheadline).foregroundStyle(Theme.dim)
        }
        TalkSeats(seats: seats(g))
        VStack(alignment: .leading, spacing: 8) {
            SectionHeading("现场记录")
            Text(g.publicClue).font(.subheadline).foregroundStyle(Theme.text.opacity(0.9)).fixedSize(horizontal: false, vertical: true)
        }
        .raised()
        TalkTestimony(slips: slips(g.statements, g), empty: "发言还没开始。")
        TalkHistory(rounds: history(g))
        if g.stage == .statement { strategies(g) }
        if !g.hints.isEmpty { TalkHints(title: "你拿到的线索", hints: g.hints) }
        if g.stage == .vote { voting(g) }
        if let reveal = g.reveal { outcome(g, reveal) }
        ending(g)
    }

    private func strategies(_ g: KeyCase) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading("这一轮说哪一句").padding(.bottom, 6)
            ForEach(g.options(completed: store.gateCount)) { option in
                TalkOptionRow(title: option.label, detail: option.detail,
                              trailing: option.unlocked ? nil : "做完 \(option.at) 项解锁",
                              disabled: !option.unlocked) {
                    choose(option.id)
                }
            }
        }
    }

    private func voting(_ g: KeyCase) -> some View {
        let targets = g.players.filter { $0.alive && $0.id != "me" }.map { TalkTarget(id: $0.id, seat: $0.seat, name: $0.nickname) }
        let picked = table.candidate.flatMap { g.seat($0) }
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeading("指认谁", trailing: "提交后不能改")
            TalkTargets(targets: targets, selected: table.candidate) { id in pick(id) }
            Button(picked.map { "确认指认 \($0.seat)号" } ?? "先选一席") { vote() }
                .buttonStyle(.danger)
                .disabled(picked == nil)
        }
    }

    private func outcome(_ g: KeyCase, _ reveal: Reveal) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(reveal.text).font(Theme.title(19)).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
            TalkBallots(lines: ballots(g.votes, g))
            if g.stage == .reveal {
                Button("下一轮") { next() }.buttonStyle(.ember)
            }
        }
        .raised()
    }

    @ViewBuilder
    private func ending(_ g: KeyCase) -> some View {
        if let result = g.result {
            let won = result.winner == "villagers"
            VStack(alignment: .leading, spacing: 10) {
                Text(won ? "钥匙找回来了，藏得也没多深。" : "钥匙没找回来。下次别让语气替你指认。")
                    .font(Theme.brush(24))
                    .foregroundStyle(won ? Theme.moss : Theme.rose)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(result.reason)拿钥匙的是 \(g.num(g.keeperId))「\(g.seat(g.keeperId)?.nickname ?? "")」。")
                    .font(.subheadline)
                    .foregroundStyle(Theme.text.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                Button("再来一局") { start() }.buttonStyle(.ember)
                Button("回去做一件事") { stage.go(.tasks) }.buttonStyle(.quiet)
            }
            .raised()
        } else {
            Button("离开这一桌") { abandon() }
                .buttonStyle(.tap(.close))
                .font(.subheadline)
                .foregroundStyle(Theme.dim)
        }
    }

    // MARK: 数据整理

    private func seats(_ g: KeyCase) -> [TalkSeatInfo] {
        g.players.map { p in
            let role: String? = g.result == nil ? nil : (g.result?.keeperId == p.id ? "wolf" : "villager")
            return TalkSeatInfo(id: p.id, seat: p.seat, name: p.nickname, me: p.id == "me", alive: p.alive, role: role,
                                note: TalkWords.seatNote(alive: p.alive, stage: g.stage.rawValue, hasStatement: p.hasStatement,
                                                         hasVoted: p.hasVoted, bot: p.bot, role: role))
        }
    }

    private func slips(_ list: [Statement], _ g: KeyCase) -> [TalkSlipInfo] {
        list.map { s in
            TalkSlipInfo(id: s.id, who: "\(s.seat)号 · \(g.seat(s.playerId)?.nickname ?? "席位")", tier: s.tier, text: s.text)
        }
    }

    private func ballots(_ votes: [Ballot], _ g: KeyCase) -> [String] {
        votes.map { "\(g.num($0.voterId)) → \($0.targetId.map { g.num($0) } ?? "弃权")" }
    }

    private func history(_ g: KeyCase) -> [TalkHistoryRound] {
        g.history.filter { $0.round < g.round }.map { h in
            TalkHistoryRound(id: h.round, round: h.round, slips: slips(h.statements, g), ballots: ballots(h.votes, g))
        }
    }

    /// 写进行为回声的事实：哪一局、第几轮、当时开放到第几手、这一轮用了哪一手。
    private func facts(_ kind: String, _ g: KeyCase) -> Trace {
        var t = Trace(kind: kind, mode: "solo", session: table.session, round: g.round,
                      completedCount: store.gateCount, unlockedTier: store.strategyTier)
        if let tier = g.statements.first(where: { $0.playerId == "me" })?.tier {
            t.strategyTier = tier
            t.strategyLabel = Strategy.names[min(3, max(0, tier))]
        }
        return t
    }

    // MARK: 动作

    private func start() {
        table.game = KeyCase()
        table.session = newID()
        table.candidate = nil
        table.recorded = false
        sfx(.drawShuffle)
    }

    private func abandon() {
        table.reset()
    }

    private func choose(_ optionId: String) {
        guard var g = table.game else { return }
        guard g.statement(optionId: optionId, completed: store.gateCount) else { return }
        table.game = g
        store.trace(facts("strategy", g))
        sfx(.scan)
    }

    private func pick(_ id: String) {
        guard table.game?.stage == .vote else { return }
        table.candidate = id
        sfx(.tick)
    }

    private func vote() {
        guard var g = table.game, let target = table.candidate, let seat = g.seat(target)?.seat else { return }
        guard g.vote(targetId: target) else { return }
        table.game = g
        var t = facts("vote", g)
        t.targetSeat = seat
        t.voteAttempt = 1
        store.trace(t)
        table.candidate = nil
        sfx(.vote)
        sfx(.stamp, delay: 0.12)
        record(g)
    }

    /// 一局结束只记一次：战绩、公开结局、结局的声音。
    private func record(_ g: KeyCase) {
        guard let result = g.result, !table.recorded else { return }
        table.recorded = true
        store.recordTalk(winner: result.winner)
        var t = facts("result", g)
        t.winner = result.winner
        t.reason = result.reason
        store.trace(t)
        sfx(result.winner == "villagers" ? .revealSuccess : .revealWrong, delay: 0.35)
    }

    private func next() {
        guard var g = table.game else { return }
        guard g.next() else { return }
        table.game = g
        table.candidate = nil
        sfx(.open)
    }
}

// MARK: 单机与联机共用的说法和小部件

enum TalkWords {
    static func stage(_ raw: String) -> String {
        switch raw {
        case "ready": return "等待入座"
        case "statement": return "限定发言"
        case "vote": return "指认"
        case "reveal": return "本轮揭晓"
        case "finished": return "本局结束"
        default: return raw
        }
    }

    /// 服务端的身份取值换成山庄里的说法。
    static func role(_ raw: String?) -> String {
        raw == "wolf" ? "拿钥匙的人" : "守夜人"
    }

    static func seatNote(alive: Bool, stage: String, hasStatement: Bool, hasVoted: Bool, bot: Bool, role: String?) -> String {
        if let role { return TalkWords.role(role) }
        if !alive { return "已离席" }
        switch stage {
        case "statement": return hasStatement ? "已发言" : "等发言"
        case "vote": return hasVoted ? "已指认" : "等指认"
        default: return bot ? "电脑" : "在场"
        }
    }
}

struct TalkSeatInfo: Identifiable {
    var id: String
    var seat: Int
    var name: String
    var me: Bool
    var alive: Bool
    var role: String?
    var note: String
}

/// 五个席位排成一行。
struct TalkSeats: View {
    let seats: [TalkSeatInfo]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(seats) { seat in
                chip(seat)
            }
        }
    }

    private func chip(_ s: TalkSeatInfo) -> some View {
        let keeper = s.role == "wolf"
        let fill = keeper ? Theme.rose.opacity(0.22) : s.me ? Theme.ember.opacity(0.18) : Color.black.opacity(0.45)
        return VStack(spacing: 3) {
            Text("\(s.seat)号").font(.caption.weight(.bold)).foregroundStyle(s.me ? Theme.ember : Theme.text)
            Text(s.name).font(.caption).foregroundStyle(Theme.text).strikethrough(!s.alive).lineLimit(1).minimumScaleFactor(0.7)
            Text(s.note).font(.caption2).foregroundStyle(keeper ? Theme.rose : Theme.dim).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 3)
        .background(fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .opacity(s.alive ? 1 : 0.5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(s.seat)号，\(s.name)\(s.me ? "，你" : "")，\(s.note)")
    }
}

struct TalkSlipInfo: Identifiable {
    var id: String
    var who: String
    var tier: Int
    var text: String
}

/// 一轮里的口供：每人一张纸条。
struct TalkTestimony: View {
    let slips: [TalkSlipInfo]
    var empty = ""

    var body: some View {
        if slips.isEmpty {
            if !empty.isEmpty {
                Text(empty).font(.subheadline).foregroundStyle(Theme.dim)
            }
        } else {
            VStack(spacing: 10) {
                ForEach(slips) { slip in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(slip.who).font(.footnote.weight(.bold))
                            Spacer()
                            if slip.tier > 0 { Tag("第 \(slip.tier + 1) 手", color: Theme.inkSoft) }
                        }
                        Text(slip.text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    }
                    .paper(padding: 12)
                }
            }
        }
    }
}

/// 谁指认了谁。
struct TalkBallots: View {
    let lines: [String]

    var body: some View {
        if !lines.isEmpty {
            Text(lines.joined(separator: "　"))
                .font(.footnote)
                .foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct TalkHistoryRound: Identifiable {
    var id: Int
    var round: Int
    var slips: [TalkSlipInfo]
    var ballots: [String]
}

/// 前几轮的公开记录，默认收起。
struct TalkHistory: View {
    let rounds: [TalkHistoryRound]
    @State private var open = false

    var body: some View {
        if !rounds.isEmpty {
            DisclosureGroup(isExpanded: $open) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(rounds) { round in
                        Text("第 \(round.round) 轮").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                        TalkTestimony(slips: round.slips)
                        TalkBallots(lines: round.ballots)
                    }
                }
                .padding(.top, 10)
            } label: {
                Text("前面 \(rounds.count) 轮的记录").font(.subheadline.weight(.medium)).foregroundStyle(Theme.text)
            }
            .tint(Theme.dim)
            .onChange(of: open) { _, _ in sfx(.paper) }
        }
    }
}

struct TalkHints: View {
    let title: String
    let hints: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeading(title)
            ForEach(Array(hints.enumerated()), id: \.offset) { _, hint in
                Text(hint).font(.subheadline).foregroundStyle(Theme.text.opacity(0.9)).fixedSize(horizontal: false, vertical: true)
            }
        }
        .raised()
    }
}

/// 一种发言：没解锁的只显示条件。
struct TalkOptionRow: View {
    let title: String
    let detail: String
    var trailing: String?
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.medium)).foregroundStyle(Theme.text)
                    Text(detail).font(.footnote).foregroundStyle(Theme.dim).multilineTextAlignment(.leading)
                }
                Spacer()
                if let trailing {
                    Text(trailing).font(.caption).foregroundStyle(Theme.dim)
                } else {
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.dim)
                }
            }
            .padding(.vertical, 12)
            .overlay(alignment: .bottom) { Theme.hairline.frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
    }
}

struct TalkTarget: Identifiable {
    var id: String
    var seat: Int
    var name: String
}

/// 可以指认的席位，选中的一席高亮。
struct TalkTargets: View {
    let targets: [TalkTarget]
    let selected: String?
    let pick: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(targets) { target in
                let chosen = selected == target.id
                Button {
                    pick(target.id)
                } label: {
                    HStack(spacing: 6) {
                        Text("\(target.seat)号").fontWeight(.bold)
                        Text(target.name).lineLimit(1)
                    }
                    .font(.subheadline)
                    .foregroundStyle(chosen ? Theme.ink : Theme.text)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(chosen ? Theme.ember : Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
    }
}
