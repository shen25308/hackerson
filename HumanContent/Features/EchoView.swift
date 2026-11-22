import SwiftUI
import UniformTypeIdentifiers

struct EchoRoot: View {
    var body: some View {
        NavigationStack {
            EchoView()
        }
        .tabChrome()
    }
}

private enum EchoTab: Hashable {
    case day, task, long
}

/// 行为回声：你做过什么、怎么决定的，都只按留下的记录说话。
struct EchoView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var stage: Stage
    @EnvironmentObject private var focus: FocusTimer
    @State private var tab: EchoTab = .day
    @State private var dayID: String?
    @State private var exported: ExportFile?
    @State private var importing = false
    @State private var pending: Ledger?
    @State private var writing = false

    var body: some View {
        let data = Echo.summary(store.s, demo: store.demo)
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                content(data)
                facts(data)
                districts
                Picker("回看方式", selection: $tab) {
                    Text("按天").tag(EchoTab.day)
                    Text("每项任务").tag(EchoTab.task)
                    Text("长期").tag(EchoTab.long)
                }
                .pickerStyle(.segmented)
                .onChange(of: tab) { _, _ in sfx(.paper) }
                switch tab {
                case .day: dayView
                case .task: taskView
                case .long: longView(data)
                }
            }
            .page()
            .padding(.vertical, 12)
        }
        .nightBackground(.chapel)
        .navigationTitle("行为回声")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("导出备份", systemImage: "square.and.arrow.up") { export() }
                    Button("导入备份", systemImage: "square.and.arrow.down") { importing = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("备份")
            }
        }
        .sheet(item: $exported) { file in
            ActivityView(items: [file.url])
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            read(result)
        }
        .alert("用这份备份替换现在的记录？", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
            Button("替换", role: .destructive) { applyPending() }
            Button("保留现在的", role: .cancel) { pending = nil }
        } message: {
            if let pending {
                Text("\(pending.days.count) 个日期，\(pending.days.reduce(0) { $0 + $1.tasks.count }) 项任务。计时会清空。")
            }
        }
        .sheet(isPresented: $writing) {
            NoteSheet(title: "下次想验证什么", prompt: "这是计划中的小实验，还没发生",
                      placeholder: "下次先发草稿，看看是否真的需要再准备一小时",
                      initial: Echo.suggestion(data), button: "作为假设保存") { text in
                store.addHypothesis(text)
            }
            .preferredColorScheme(.dark)
        }
    }

    // MARK: 人类含量

    private func content(_ data: EchoSummary) -> some View {
        let hc = Rules.humanContent(store.s)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(hc.percent)%").font(Theme.brush(52)).foregroundStyle(hc.percent >= 60 ? Theme.ember : Theme.rose)
                VStack(alignment: .leading, spacing: 2) {
                    Text("人类含量").font(.headline).foregroundStyle(Theme.text)
                    Text(hc.byHand + hc.taken == 0 ? "界面还没来得及对你下手" : "亲手决定 \(hc.byHand) 次 · 被界面带走 \(hc.taken) 次")
                        .font(.footnote).foregroundStyle(Theme.dim)
                }
            }
            ForEach(data.baits.suffix(3).reversed()) { event in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: event.taken == true ? "xmark" : "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(event.taken == true ? Theme.rose : Theme.moss)
                    Text(event.text).font(.subheadline).foregroundStyle(Theme.text.opacity(0.9))
                }
            }
        }
    }

    private func facts(_ data: EchoSummary) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            LedgerRow(label: "整件做完", value: data.ratio.map { "\(data.completed) / \(data.total) · \($0)%" } ?? "还没有任务")
            LedgerRow(label: "留下完整用时", value: data.timed > 0 ? "\(data.timed) 次 · 预计 \(data.estimatedMinutes) / 实际 \(data.actualMinutes) 分钟" : "还没有")
            LedgerRow(label: "夜谈", value: "\(data.strategies) 手策略 · \(data.votes) 次指认 · \(data.finished) 局")
        }
    }

    private var districts: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(["decisions", "mirror", "experiment"], id: \.self) { id in
                if let place = Atlas.place(id) {
                    let open = store.isOpen(id)
                    Button {
                        if open {
                            sfx(.open)
                            stage.sheet = .district(id)
                        } else {
                            sfx(.lock)
                            stage.say("\(place.name)还没开：再整件做完 \(place.need - store.gateCount) 项。")
                        }
                    } label: {
                        HStack {
                            Image(systemName: open ? "door.left.hand.open" : "lock.fill")
                                .foregroundStyle(open ? Theme.ember : Theme.dim)
                                .frame(width: 26)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(place.name).font(.body.weight(.medium)).foregroundStyle(open ? Theme.text : Theme.dim)
                                Text(open ? place.feature : "做完 \(place.need) 项开门").font(.footnote).foregroundStyle(Theme.dim)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.dim)
                        }
                        .padding(.vertical, 11)
                        .overlay(alignment: .bottom) { Theme.hairline.frame(height: 1) }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: 按天

    @ViewBuilder
    private var dayView: some View {
        let day = store.s.days.first { $0.id == dayID } ?? store.today
        Menu {
            ForEach(store.s.days.reversed()) { d in
                Button("\(Clock.dayLabel(d.id)) · \(d.closed ? "已收工" : "记录中")") {
                    dayID = d.id
                    sfx(.paper)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(Clock.dayLabel(day.id)).font(Theme.title(20))
                Image(systemName: "chevron.up.chevron.down").font(.caption)
            }
            .foregroundStyle(Theme.text)
        }
        Text(day.closed
             ? "经验 +\(Rules.earned(day) + day.bonusXP) · 生命 −\(day.loss) · 抽牌 +\(day.awarded)"
             : "记录中 · 经验 +\(Rules.earned(day))")
            .font(.subheadline).foregroundStyle(Theme.dim)
        if day.tasks.isEmpty {
            Text("这一天没有任务记录。").font(.subheadline).foregroundStyle(Theme.dim)
        }
        ForEach(day.tasks) { quest in
            QuestRecord(quest: quest, date: nil)
        }
        if !day.reflection.isEmpty {
            Text("留给自己的话：「\(day.reflection)」").font(.subheadline).foregroundStyle(Theme.text).raised()
        }
        let events = store.s.events.filter { $0.date == day.id }.reversed()
        if !events.isEmpty {
            SectionHeading("这一天的经过")
            ForEach(Array(events)) { event in
                EventRow(event: event, questTitle: event.task.flatMap { id in day.tasks.first { $0.id == id }?.title })
            }
        }
    }

    // MARK: 每项任务

    @ViewBuilder
    private var taskView: some View {
        let all = Rules.allQuests(store.s).reversed()
        if all.isEmpty {
            Text("还没有任务。写下第一项后，估时、选择和行动都会连到它身上。").font(.subheadline).foregroundStyle(Theme.dim)
        }
        ForEach(Array(all), id: \.quest.id) { item in
            QuestRecord(quest: item.quest, date: item.date)
        }
    }

    // MARK: 长期

    @ViewBuilder
    private func longView(_ data: EchoSummary) -> some View {
        Text(data.timed < 3
             ? "完整用时还不到 3 次，先不谈估时习惯。"
             : "\(data.timed) 次完整用时里，有 \(data.overEstimate) 次超过了预计。")
            .font(.subheadline).foregroundStyle(Theme.text)
        Button("写一个下次要验证的动作") {
            if store.isOpen("experiment") {
                sfx(.open)
                writing = true
            } else {
                sfx(.lock)
                stage.say("镜湖还没开：再整件做完 \((Atlas.place("experiment")?.need ?? 6) - store.gateCount) 项。")
            }
        }
        .buttonStyle(.quiet)
        ForEach(data.hypotheses.reversed()) { event in
            VStack(alignment: .leading, spacing: 3) {
                Text("\(event.date) · 假设，还没验证").font(.caption).foregroundStyle(Theme.dim)
                Text(event.text).font(.subheadline).foregroundStyle(Theme.text)
            }
        }
    }

    // MARK: 备份

    private func export() {
        guard let data = store.exportData() else {
            stage.say("记录没能导出，请再试一次。")
            return
        }
        guard data.count <= Backup.maxBytes else {
            stage.say("记录超过 2 MB，暂时导不出。")
            return
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(store.exportName)
        do {
            try data.write(to: url, options: .atomic)
            sfx(.accept)
            exported = ExportFile(url: url)
        } catch {
            stage.say("记录没能导出，请再试一次。")
        }
    }

    private func read(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            stage.say("文件没能读出来，换个位置再试。")
            return
        }
        do {
            pending = try Backup.validate(data)
            sfx(.scan)
        } catch let error as BackupError {
            sfx(.error)
            stage.say(error.message)
        } catch {
            sfx(.error)
            stage.say(BackupError.unreadable.message)
        }
    }

    private func applyPending() {
        guard let backup = pending else { return }
        pending = nil
        focus.clear()
        TalkTable.shared.reset()
        OnlineRoom.shared.resetSession()
        store.apply(backup: backup)
        dayID = nil
        sfx(.accept)
        stage.say(store.storageOK ? "备份已导入。" : "备份已载入，但没能存到本机，请再导出一次。")
    }
}

struct ExportFile: Identifiable {
    let url: URL
    var id: String { url.path }
}

/// 系统的分享面板。
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// 档案里的一项任务。
struct QuestRecord: View {
    let quest: Quest
    let date: String?
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(quest.title).font(.body.weight(.semibold)).foregroundStyle(Theme.text)
                Spacer()
                Tag(quest.isFull ? "做完了" : quest.isPartial ? "一部分" : "没登记", color: quest.isFull ? Theme.moss : quest.isPartial ? Theme.ember : Theme.dim)
            }
            Text(line).font(.footnote).foregroundStyle(Theme.dim)
            if !quest.step.isEmpty { Text("下一步：\(quest.step)").font(.footnote).foregroundStyle(Theme.text.opacity(0.85)) }
            if !quest.context.isEmpty { Text("补充：\(quest.context)").font(.footnote).foregroundStyle(Theme.text.opacity(0.85)) }
            if quest.original != quest.title || !quest.rounds.isEmpty {
                Button(expanded ? "收起" : "追溯字条与原约定") {
                    sfx(.paper)
                    withAnimation(.easeOut(duration: 0.2)) { expanded.toggle() }
                }
                .buttonStyle(.tap)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.ember)
                if expanded { trail }
            }
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Theme.hairline.frame(height: 1) }
    }

    private var line: String {
        var parts: [String] = []
        if let date { parts.append(date) }
        parts.append(quest.bonus ? "额外" : "必做")
        parts.append("预计 \(quest.estimate) 分钟")
        if quest.done { parts.append(quest.actual.map { "实际 \($0) 分钟" } ?? "未填用时") }
        if quest.done { parts.append("经验 +\(quest.earned)") }
        if quest.prep > 0 { parts.append("继续准备 \(quest.prep) 次") }
        return parts.joined(separator: " · ")
    }

    private var trail: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("最初写下：「\(quest.original)」")
            ForEach(quest.rounds.keys.sorted(), id: \.self) { n in
                if let round = quest.rounds[n], Council.topics.indices.contains(n) {
                    Text(roundLine(n, round))
                }
            }
        }
        .font(.footnote)
        .foregroundStyle(Theme.text.opacity(0.85))
    }

    private func roundLine(_ n: Int, _ round: Round) -> String {
        var text = Council.topics[n].title + "："
        if let vote = round.vote {
            let hit = vote == Rules.stringSeat(quest, topic: n)
            text += "剪了第 \(vote + 1) 张，" + (hit ? "剪中" : "没剪中") + (round.byInterface ? "（倒计时替你剪的）" : "")
        } else {
            text += "没有下剪"
        }
        if let answer = round.answer { text += "；判断：\(answer)" }
        return text
    }
}

/// 时间线上的一条。反向体验的记录可以展开。
struct EventRow: View {
    let event: LogEvent
    let questTitle: String?
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(event.time) · \(Echo.typeLabel(event.type))").font(.caption).foregroundStyle(Theme.dim)
            Text(event.text).font(.subheadline).foregroundStyle(event.taken == true ? Theme.rose : Theme.text)
            if let questTitle { Text("对应：\(questTitle)").font(.footnote).foregroundStyle(Theme.dim) }
            if !event.records.isEmpty {
                Button(expanded ? "收起" : "看这轮界面怎么带偏你 · \(event.records.count) 条") {
                    sfx(.paper)
                    withAnimation(.easeOut(duration: 0.2)) { expanded.toggle() }
                }
                .buttonStyle(.tap)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.ember)
                if expanded {
                    ForEach(Array(event.records.enumerated()), id: \.offset) { _, record in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.label.isEmpty ? record.level : record.label).font(.footnote.weight(.semibold))
                            Text(record.text).font(.footnote)
                            if !record.note.isEmpty { Text("你的观察：\(record.note)").font(.footnote).foregroundStyle(Theme.ember) }
                        }
                        .foregroundStyle(Theme.text.opacity(0.88))
                        .padding(.top, 2)
                    }
                }
            }
        }
        .padding(.vertical, 5)
    }
}

// MARK: 三处开门后才能进的地方

struct DistrictSheet: View {
    let place: String
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var stage: Stage
    @State private var writing = false

    var body: some View {
        let data = Echo.summary(store.s, demo: store.demo)
        SheetScaffold(title: Atlas.place(place)?.name ?? "行为回声") {
            if !store.isOpen(place) {
                Text("这里还没开。再整件做完 \((Atlas.place(place)?.need ?? 0) - store.gateCount) 项任务。")
                    .font(.subheadline).foregroundStyle(Theme.dim)
                Button("去任务板") { stage.go(.tasks) }.buttonStyle(.ember)
            } else if place == "decisions" {
                decisions(data)
            } else if place == "mirror" {
                mirror(data)
            } else {
                experiment(data)
            }
        }
        .sheet(isPresented: $writing) {
            NoteSheet(title: "下次想验证什么", prompt: "这是计划中的小实验，还没发生",
                      initial: Echo.suggestion(data), button: "作为假设保存") { text in
                store.addHypothesis(text)
            }
            .preferredColorScheme(.dark)
        }
    }

    private func strategyRows(_ data: EchoSummary) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Strategy.names.indices, id: \.self) { i in
                LedgerRow(label: Strategy.names[i], value: "\(data.strategyCounts[i]) 次")
            }
        }
    }

    private func talkRows(_ events: [LogEvent], limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if events.isEmpty {
                Text("还没有你亲手提交过的策略或指认。").font(.subheadline).foregroundStyle(Theme.dim)
                Button("坐下一局") { stage.openTalk(online: false) }.buttonStyle(.quiet)
            }
            ForEach(events.suffix(limit).reversed()) { event in
                if let t = event.trace {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(event.date) \(event.time) · \(t.mode == "solo" ? "单机" : "联机") · 第 \(t.round) 轮").font(.caption).foregroundStyle(Theme.dim)
                        Text(Echo.describe(t)).font(.subheadline.weight(.medium)).foregroundStyle(Theme.text)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func decisions(_ data: EchoSummary) -> some View {
        Text("你当时用了哪一手，又指认了谁。").font(.subheadline).foregroundStyle(Theme.text)
        strategyRows(data)
        talkRows(data.evidence.filter { $0.trace?.kind != "result" }, limit: 30)
    }

    @ViewBuilder
    private func mirror(_ data: EchoSummary) -> some View {
        SectionHeading("现实的一侧", trailing: "\(data.completed) / \(data.total) 项")
        Text(data.timed > 0 ? "\(data.timed) 项完整用时：预计 \(data.estimatedMinutes) 分钟，实际 \(data.actualMinutes) 分钟。" : "还没有预计和实际都填了的记录。")
            .font(.subheadline).foregroundStyle(Theme.dim)
        ForEach(Array(Rules.allQuests(store.s).filter { $0.quest.isFull }.suffix(3).reversed()), id: \.quest.id) { item in
            QuestRecord(quest: item.quest, date: item.date)
        }
        SectionHeading("桌上的一侧", trailing: "\(data.strategies) 手 · \(data.votes) 次指认")
        strategyRows(data)
        talkRows(data.evidence.filter { $0.trace?.kind == "vote" }, limit: 3)
    }

    @ViewBuilder
    private func experiment(_ data: EchoSummary) -> some View {
        Text(Echo.suggestion(data)).font(.body).foregroundStyle(Theme.ink).paper()
        Button("写下我的验证假设") {
            sfx(.open)
            writing = true
        }
        .buttonStyle(.ember)
        if !data.hypotheses.isEmpty { SectionHeading("留给下次的话") }
        ForEach(data.hypotheses.reversed()) { event in
            VStack(alignment: .leading, spacing: 3) {
                Text("\(event.date) · 假设，还没验证").font(.caption).foregroundStyle(Theme.dim)
                Text(event.text).font(.subheadline).foregroundStyle(Theme.text)
            }
        }
    }
}
