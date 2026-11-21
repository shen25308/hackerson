import SwiftUI
import UIKit

/// 联机夜谈：建一个房间邀朋友，或用六位房间码入座。电脑补满五席。
struct OnlineTalkView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var stage: Stage
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var room = OnlineRoom.shared
    @State private var candidate: String?
    @State private var now = Date()

    let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// 渡口开了、也不在示例里，才向服务读写。
    private var usable: Bool { store.isOpen("ferry") && !store.demo }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !store.isOpen("ferry") {
                lockedNote
            } else if store.demo {
                demoNote
            } else {
                connected
            }
        }
        .onAppear {
            room.onEvent = { event in handle(event) }
            room.start(active: usable && scenePhase == .active)
        }
        .onDisappear { room.stop() }
        .onChange(of: scenePhase) { _, phase in room.start(active: usable && phase == .active) }
        .onChange(of: usable) { _, ok in room.start(active: ok && scenePhase == .active) }
        .onChange(of: room.room?.stage) { _, _ in candidate = nil }
        .onReceive(clock) { date in tick(date) }
    }

    // MARK: 还不能用的两种情况

    private var lockedNote: some View {
        let left = max(0, (Atlas.place("ferry")?.need ?? 4) - store.gateCount)
        return VStack(alignment: .leading, spacing: 12) {
            Text("渡口还没开：再整件做完 \(left) 项任务，就能邀朋友入座。")
                .font(.body)
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            Button("去任务板") { stage.go(.tasks) }.buttonStyle(.quiet)
        }
        .raised()
    }

    private var demoNote: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("先退出示例，再和真人入座。").font(.body).foregroundStyle(Theme.text)
            Button("退出示例") {
                store.exitDemo()
                sfx(.close)
            }
            .buttonStyle(.quiet)
        }
        .raised()
    }

    // MARK: 连接

    @ViewBuilder
    private var connected: some View {
        if !room.error.isEmpty { errorBox }
        if room.session == nil {
            form
        } else if let snapshot = room.room {
            board(snapshot)
        } else {
            reconnectCard
        }
    }

    private var errorBox: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(room.state == .offline ? "连接暂时中断" : "没成功").font(.subheadline.weight(.bold)).foregroundStyle(Theme.rose)
            Text(room.error).font(.subheadline).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
            if room.session != nil {
                Button("重试连接") { room.reconnect() }.buttonStyle(.quietCompact).disabled(room.busy)
            }
            if room.pending != nil {
                Text("上一步有没有送到还不确定，重发不会重复计入。").font(.footnote).foregroundStyle(Theme.dim)
                Button("重发上一步") { room.retryPending() }.buttonStyle(.quietCompact).disabled(room.busy)
            }
        }
        .raised()
    }

    @ViewBuilder
    private var form: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("叫上真人，一起对质。").font(Theme.title(20)).foregroundStyle(Theme.text)
            Text("房主和至少一位朋友入座后开始，电脑补满五席。").font(.subheadline).foregroundStyle(Theme.dim)
        }
        Field(label: "联机服务地址") {
            TextField("https://你的联机服务地址", text: $room.draftBase)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .input()
                .typingSound(room.draftBase)
        }
        Field(label: "你的名字") {
            TextField("给席位起个名字", text: $room.draftNickname)
                .autocorrectionDisabled()
                .input()
                .typingSound(room.draftNickname)
                .onChange(of: room.draftNickname) { _, value in
                    if value.count > 20 { room.draftNickname = String(value.prefix(20)) }
                }
        }
        Button(room.busy ? "连接中…" : "创建房间") { room.connect(join: false, completedCount: store.gateCount) }
            .buttonStyle(.ember)
            .disabled(room.busy)
        Field(label: "已有六位房间码") {
            TextField("ABC234", text: $room.draftCode)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .input()
                .typingSound(room.draftCode)
                .onChange(of: room.draftCode) { _, value in
                    let tidy = String(value.uppercased().prefix(6))
                    if tidy != value { room.draftCode = tidy }
                }
        }
        Button("加入房间") { room.connect(join: true, completedCount: store.gateCount) }
            .buttonStyle(.quiet)
            .disabled(room.busy)
        Text("昵称和已做完的任务数会发给这个服务。").font(.footnote).foregroundStyle(Theme.dim)
    }

    private var reconnectCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("房间 \(room.session?.code ?? "")").font(Theme.title(20)).foregroundStyle(Theme.text)
            Text("入座凭证还在这台设备上。").font(.subheadline).foregroundStyle(Theme.dim)
            Button(room.busy ? "连接中…" : "重新连接") { room.reconnect() }.buttonStyle(.ember).disabled(room.busy)
            Button("退出房间") { room.leave() }.buttonStyle(.quiet).disabled(room.busy)
        }
        .raised()
    }

    // MARK: 房间

    @ViewBuilder
    private func board(_ r: RoomSnapshot) -> some View {
        let canPlay = room.canPlay(now: now)
        bar(r)
        if store.gateCount > r.me.completedCount {
            Text("你做完了新任务，新的一手下次入座生效。").font(.footnote).foregroundStyle(Theme.ember)
        }
        TalkSeats(seats: seats(r))
        if r.stage == "ready" { ready(r, canPlay: canPlay) }
        TalkTestimony(slips: slips(r.statements, r), empty: r.stage == "ready" ? "" : "发言还没开始。")
        TalkHistory(rounds: history(r))
        if r.stage != "ready" && !r.me.hints.isEmpty { TalkHints(title: "只有你看得到的线索", hints: r.me.hints) }
        if r.stage == "statement" { strategies(r, canPlay: canPlay) }
        if r.stage == "vote" { voting(r, canPlay: canPlay) }
        closing(r)
    }

    private func bar(_ r: RoomSnapshot) -> some View {
        let live = room.state == .connected
        let role = r.stage == "ready" ? "等房主开始" : "你是\(TalkWords.role(r.me.role)) · 第 \(r.me.tier + 1) 手"
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(TalkWords.stage(r.stage)).font(Theme.title(22)).foregroundStyle(Theme.text)
                Text("第 \(r.round ?? 1) / 3 轮\(r.voteAttempt == 2 ? " · 平票重投" : "")").font(.subheadline).foregroundStyle(Theme.dim)
                Spacer()
                Text(room.clockText(now: now)).font(Theme.title(20)).foregroundStyle(Theme.ember).monospacedDigit()
            }
            HStack(spacing: 6) {
                Circle().fill(live ? Theme.moss : Theme.rose).frame(width: 7, height: 7)
                Button {
                    UIPasteboard.general.string = r.code
                    sfx(.accept)
                    stage.say("房间码 \(r.code) 已复制，发给朋友。")
                } label: {
                    HStack(spacing: 4) {
                        Text("房间 \(r.code)").fontWeight(.semibold).foregroundStyle(Theme.text)
                        Image(systemName: "doc.on.doc").font(.caption2)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("复制房间码 \(r.code)")
                Text(live ? "已连接" : "连接中断")
                Spacer()
                Text(role)
            }
            .font(.footnote)
            .foregroundStyle(Theme.dim)
        }
    }

    private func ready(_ r: RoomSnapshot, canPlay: Bool) -> some View {
        let humans = r.players.filter { !$0.bot }.count
        return VStack(alignment: .leading, spacing: 10) {
            Text("真人 \(humans) / 4").font(Theme.title(20)).foregroundStyle(Theme.text)
            Text("至少两位真人，开始时电脑补满五席。").font(.subheadline).foregroundStyle(Theme.dim)
            Button(r.hostId == r.me.id ? "开始这局" : "等房主开始") { room.act("start") }
                .buttonStyle(.ember)
                .disabled(!r.me.canStart || !canPlay)
        }
        .raised()
    }

    private func strategies(_ r: RoomSnapshot, canPlay: Bool) -> some View {
        let me = r.me
        return VStack(alignment: .leading, spacing: 0) {
            SectionHeading(me.canStatement ? "这一轮只能说一次" : "已经说过了，等其他人").padding(.bottom, 6)
            ForEach(r.strategyRows()) { option in
                let locked = option.tier > me.tier
                TalkOptionRow(title: option.label, detail: option.detail,
                              trailing: locked ? "做完 \(threshold(option.tier)) 项解锁" : nil,
                              disabled: !me.canStatement || locked || !canPlay) {
                    room.act("statement", optionId: option.id)
                }
            }
        }
    }

    @ViewBuilder
    private func voting(_ r: RoomSnapshot, canPlay: Bool) -> some View {
        if r.me.canVote && canPlay {
            let targets = r.players.filter { $0.alive && $0.id != r.me.id }.map { TalkTarget(id: $0.id, seat: $0.seat, name: $0.nickname) }
            let picked = r.player(candidate)
            VStack(alignment: .leading, spacing: 12) {
                SectionHeading("指认谁", trailing: "提交后不能改")
                TalkTargets(targets: targets, selected: candidate) { id in
                    candidate = id
                    sfx(.tick)
                }
                Button(picked.map { "确认指认 \($0.seat)号" } ?? "先选一席") {
                    if let candidate { room.act("vote", targetId: candidate) }
                }
                .buttonStyle(.danger)
                .disabled(picked == nil || room.busy)
            }
        } else {
            Text("这一票已经锁定，等结果。").font(.subheadline).foregroundStyle(Theme.dim)
        }
    }

    /// 本轮揭晓、整局结局，以及刷新和退出。
    @ViewBuilder
    private func closing(_ r: RoomSnapshot) -> some View {
        if let text = r.revealText {
            VStack(alignment: .leading, spacing: 10) {
                Text(text).font(Theme.title(19)).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
                TalkBallots(lines: ballots(r.votes, r))
            }
            .raised()
        }
        if r.stage == "finished" {
            let lost = r.result?.winner == "wolf"
            VStack(alignment: .leading, spacing: 10) {
                Text(lost ? "钥匙没找回来。" : "钥匙找回来了。").font(Theme.brush(24)).foregroundStyle(lost ? Theme.rose : Theme.moss)
                if let reason = r.result?.reason, !reason.isEmpty {
                    Text(reason).font(.subheadline).foregroundStyle(Theme.text.opacity(0.9)).fixedSize(horizontal: false, vertical: true)
                }
                if r.revealText == nil { TalkBallots(lines: ballots(r.votes, r)) }
                Text("想再来一局，退出后重新建房。").font(.footnote).foregroundStyle(Theme.dim)
            }
            .raised()
        }
        HStack(spacing: 14) {
            Button("刷新") { room.reconnect() }.buttonStyle(.quietCompact).disabled(room.busy)
            Button("退出房间") { room.leave() }
                .buttonStyle(.tap)
                .font(.subheadline)
                .foregroundStyle(Theme.dim)
                .disabled(room.busy)
            Spacer()
            Text(syncText).font(.caption).foregroundStyle(Theme.dim)
        }
    }

    // MARK: 数据整理

    private var syncText: String {
        guard let last = room.lastSync else { return "还没同步" }
        let seconds = max(0, Int(now.timeIntervalSince(last)))
        return seconds < 2 ? "刚刚同步" : "\(seconds) 秒前同步"
    }

    private func threshold(_ tier: Int) -> Int {
        Strategy.thresholds.indices.contains(tier) ? Strategy.thresholds[tier] : 6
    }

    private func seats(_ r: RoomSnapshot) -> [TalkSeatInfo] {
        r.players.map { p in
            let role = r.role(of: p)
            return TalkSeatInfo(id: p.id, seat: p.seat, name: p.nickname, me: p.id == r.me.id, alive: p.alive, role: role,
                                note: TalkWords.seatNote(alive: p.alive, stage: r.stage, hasStatement: p.hasStatement,
                                                         hasVoted: p.hasVoted, bot: p.bot, role: role))
        }
    }

    private func slips(_ list: [RoomStatement], _ r: RoomSnapshot) -> [TalkSlipInfo] {
        list.map { s in
            let speaker = r.player(s.playerId)
            let seat = s.seat ?? speaker?.seat
            let head = seat.map { "\($0)号 · " } ?? ""
            return TalkSlipInfo(id: "\(s.index)", who: head + (speaker?.nickname ?? "席位"), tier: s.tier ?? 0, text: s.text)
        }
    }

    private func ballots(_ votes: [RoomBallot], _ r: RoomSnapshot) -> [String] {
        votes.map { "\(r.seatLabel($0.voterId)) → \($0.targetId.map { r.seatLabel($0) } ?? "弃权")" }
    }

    private func history(_ r: RoomSnapshot) -> [TalkHistoryRound] {
        r.earlierRounds.map { h in
            TalkHistoryRound(id: h.index, round: h.round, slips: slips(h.statements, r), ballots: ballots(h.votes, r))
        }
    }

    // MARK: 事件

    private func tick(_ date: Date) {
        now = date
        guard usable, let stageName = room.room?.stage, stageName == "statement" || stageName == "vote",
              let left = room.secondsLeft(now: date), (1...5).contains(left) else { return }
        sfx(.countdown)
    }

    private func handle(_ event: RoomEvent) {
        switch event {
        case .connected:
            sfx(.open)
        case .failed:
            sfx(.error)
        case .left:
            sfx(.close)
        case .acted(let type):
            if type == "vote" {
                sfx(.vote)
                sfx(.stamp, delay: 0.12)
            } else {
                sfx(.scan)
            }
        case .stageChanged(let next, let winner):
            if next == "vote" {
                sfx(.vote)
            } else if next == "finished" {
                sfx(winner == "villagers" ? .revealSuccess : .revealWrong)
            } else {
                sfx(.revealSuccess)
            }
        case .confirmed(let action, let facts):
            log(action, facts)
        }
    }

    /// 服务确认过的发言和指认，才写进行为回声。
    private func log(_ action: RoomAction, _ facts: RoomFacts) {
        var t = Trace(kind: action.type == "statement" ? "strategy" : "vote", mode: "online", session: facts.session,
                      round: facts.round, completedCount: facts.completedCount, unlockedTier: facts.unlockedTier)
        t.strategyTier = facts.strategyTier
        t.strategyLabel = facts.strategyLabel
        if action.type == "vote" {
            guard let seat = facts.targetSeat, (1...5).contains(seat) else { return }
            t.targetSeat = seat
            t.voteAttempt = facts.voteAttempt
        }
        store.trace(t)
    }
}
