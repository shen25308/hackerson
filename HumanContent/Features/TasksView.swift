import SwiftUI

struct TasksRoot: View {
    @EnvironmentObject private var stage: Stage

    var body: some View {
        NavigationStack(path: $stage.taskPath) {
            TasksView()
                .navigationDestination(for: TaskRoute.self) { route in
                    switch route {
                    case .detail(let id): QuestDetailView(id: id)
                    case .settle: SettleView()
                    }
                }
        }
        .tabChrome()
    }
}

/// 今天的任务板：一张张钉着的纸条。
struct TasksView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var stage: Stage
    @State private var adding = false
    @State private var completing: Quest?

    var body: some View {
        let day = store.today
        let required = day.tasks.filter { !$0.bonus }
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(summary(day, required)).font(.subheadline).foregroundStyle(Theme.dim)
                if day.closed {
                    Text("今天已收工，新的约定明天再写。").font(.subheadline).foregroundStyle(Theme.text).raised()
                }
                if day.tasks.isEmpty {
                    EmptyNote(title: "先别拯救世界。先写一件今天能做完的事。", action: "写下第一件事") { adding = true }
                    if !store.demo {
                        Button("先看看示例") {
                            store.enterDemo()
                            sfx(.open)
                        }
                        .buttonStyle(.tap)
                        .font(.subheadline)
                        .foregroundStyle(Theme.ember)
                    }
                } else {
                    ForEach(Array(day.tasks.enumerated()), id: \.element.id) { index, quest in
                        QuestSlip(quest: quest, closed: day.closed, tilt: index.isMultiple(of: 2) ? -0.5 : 0.4) {
                            toggle(quest)
                        } open: {
                            stage.taskPath.append(.detail(quest.id))
                        }
                    }
                }
                if !day.tasks.isEmpty {
                    Button(day.closed ? "看今天的记录" : "收工") {
                        if day.closed { stage.go(.echo) } else { stage.taskPath.append(.settle) }
                    }
                    .buttonStyle(.quiet)
                    .padding(.top, 6)
                }
            }
            .page()
            .padding(.vertical, 12)
        }
        .nightBackground()
        .navigationTitle("今天的约定")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    sfx(.open)
                    adding = true
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(day.closed)
                .accessibilityLabel("新增待办")
            }
        }
        .sheet(isPresented: $adding) {
            AddQuestSheet { id in stage.taskPath = [.detail(id)] }
                .preferredColorScheme(.dark)
        }
        .sheet(item: $completing) { quest in
            CompleteSheet(id: quest.id).preferredColorScheme(.dark)
        }
    }

    private func summary(_ day: Day, _ required: [Quest]) -> String {
        let extra = day.tasks.filter { $0.bonus && $0.isFull }.count
        let head = "\(Clock.dayLabel(day.id)) · 必做 \(required.filter(\.isFull).count)/\(required.count)"
        return head + (extra > 0 ? " · 额外 \(extra)" : "") + " · 经验 +\(Rules.earned(day))"
    }

    private func toggle(_ quest: Quest) {
        if quest.isFull {
            if store.undo(quest.id) {
                sfx(.undo)
                stage.say("已撤销完成。")
            }
        } else {
            sfx(.open)
            completing = quest
        }
    }
}

/// 任务板上的一张纸条。
struct QuestSlip: View {
    let quest: Quest
    let closed: Bool
    let tilt: Double
    let check: () -> Void
    let open: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: check) {
                ZStack {
                    Circle().stroke(Theme.ink.opacity(0.55), lineWidth: 1.6)
                    if quest.isFull {
                        Circle().fill(Theme.ink)
                        Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.paper)
                    } else if quest.isPartial {
                        Circle().trim(from: 0, to: 0.5).fill(Theme.ink).rotationEffect(.degrees(90))
                    }
                }
                .frame(width: 26, height: 26)
                .padding(4)
            }
            .buttonStyle(.plain)
            .disabled(closed)
            .accessibilityLabel(quest.isFull ? "撤销完成：\(quest.title)" : "登记完成：\(quest.title)")
            Button(action: open) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(quest.title)
                        .font(.body.weight(.semibold))
                        .strikethrough(quest.isFull, color: Theme.ink.opacity(0.5))
                        .multilineTextAlignment(.leading)
                    Text(meta).font(.footnote).foregroundStyle(Theme.inkSoft)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.tap(.paper))
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.inkSoft).padding(.top, 8)
        }
        .paper(padding: 14)
        .overlay(alignment: .top) {
            Circle().fill(quest.bonus ? Theme.ember : Theme.rose).frame(width: 9, height: 9).offset(y: -4)
                .shadow(color: .black.opacity(0.4), radius: 1, y: 1)
        }
        .opacity(quest.isFull ? 0.78 : 1)
        .rotationEffect(.degrees(tilt))
    }

    private var meta: String {
        let kind = quest.bonus ? "额外" : "必做"
        if quest.isFull {
            return "\(kind) · \(quest.actual.map { "用了 \($0) 分钟" } ?? "未填用时") · 经验 +\(quest.earned)"
        }
        if quest.isPartial { return "\(kind) · 做完一部分 · 经验 +\(quest.earned)" }
        return "\(kind) · 预计 \(quest.estimate) 分钟" + (quest.decision.isEmpty ? "" : " · \(quest.decision)")
    }
}

// MARK: 详情

struct QuestDetailView: View {
    let id: String
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var stage: Stage
    @EnvironmentObject private var focus: FocusTimer
    @State private var step = ""
    @State private var completing = false
    @State private var adjusting = false
    @State private var switching = false
    @FocusState private var editing: Bool

    var body: some View {
        if let quest = store.quest(id) {
            let locked = store.closed || quest.done
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(quest.title).font(Theme.brush(27)).foregroundStyle(Theme.text)
                        HStack(spacing: 6) {
                            Tag(quest.bonus ? "额外" : "必做", color: quest.bonus ? Theme.ember : Theme.rose)
                            Tag("预计 \(quest.estimate) 分钟")
                            if quest.isFull { Tag("已完成", color: Theme.moss) }
                            if quest.isPartial { Tag("做完一部分", color: Theme.ember) }
                        }
                    }
                    if quest.done { result(quest) }
                    if !quest.isFull && !store.closed { FocusPanel(quest: quest) { switching = true } }
                    stepEditor(quest, locked: locked)
                    if let hint = Rules.estimateSuggestion(title: quest.title, in: store.s), !locked {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("同名任务最近三次用了 \(hint.samples.map { "\($0.minutes)" }.joined(separator: "、")) 分钟。")
                                .font(.subheadline).foregroundStyle(Theme.text)
                            Button("把预计改成 \(hint.minutes) 分钟") {
                                store.useEstimate(id)
                                sfx(.accept)
                            }
                            .buttonStyle(.quietCompact)
                        }
                        .raised()
                    }
                    actions(quest)
                    footprints
                }
                .page()
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .nightBackground()
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { step = quest.step }
            .sheet(isPresented: $completing) { CompleteSheet(id: id).preferredColorScheme(.dark) }
            .sheet(isPresented: $adjusting) { AdjustSheet(id: id).preferredColorScheme(.dark) }
            .confirmationDialog("另一件事还在计时", isPresented: $switching, titleVisibility: .visible) {
                Button("结束上一段，开始这项") {
                    focus.stop()
                    focus.start(id, date: store.today.id, demo: store.demo)
                    sfx(.focusStart)
                }
                Button("保留原计时", role: .cancel) {}
            }
        } else {
            EmptyNote(title: "这项任务不在今天。", action: "回到任务板") { stage.taskPath = [] }
                .page()
                .frame(maxHeight: .infinity, alignment: .top)
                .nightBackground()
        }
    }

    private func result(_ quest: Quest) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("经验 +\(quest.earned)").font(Theme.title(22)).foregroundStyle(Theme.ember)
                if quest.healed > 0 { Text("生命 +\(quest.healed)").font(.subheadline).foregroundStyle(Theme.rose) }
                Spacer()
                if let actual = quest.actual { Text("\(actual) / \(quest.estimate) 分钟").font(.subheadline).foregroundStyle(Theme.dim) }
            }
            ForEach(quest.xpParts, id: \.label) { part in
                LedgerRow(label: part.label, value: part.value > 0 ? "+\(part.value)" : "\(part.value)",
                          color: part.value < 0 ? Theme.rose : Theme.text)
            }
            if !quest.context.isEmpty {
                Text(quest.context).font(.footnote).foregroundStyle(Theme.dim).padding(.top, 4)
            }
        }
        .raised()
    }

    private func stepEditor(_ quest: Quest, locked: Bool) -> some View {
        Field(label: "下一步，具体做什么") {
            TextField("例如：把现有草稿发给小林，问他哪一段看不懂", text: $step, axis: .vertical)
                .lineLimit(2...5)
                .focused($editing)
                .disabled(locked)
                .input()
                .typingSound(step)
            if !locked, step.trimmingCharacters(in: .whitespacesAndNewlines) != quest.step {
                Button("保存这一步") {
                    store.saveStep(id, step)
                    editing = false
                    sfx(.accept)
                    stage.say("下一步已保存。")
                }
                .buttonStyle(.quietCompact)
            }
        }
    }

    @ViewBuilder
    private func actions(_ quest: Quest) -> some View {
        VStack(spacing: 10) {
            if !store.closed {
                if !quest.done {
                    Button("我做完了") {
                        sfx(.open)
                        completing = true
                    }
                    .buttonStyle(.ember)
                } else {
                    if quest.isPartial {
                        Button("补完剩下的") {
                            sfx(.open)
                            completing = true
                        }
                        .buttonStyle(.ember)
                    }
                    Button("撤销这次完成") {
                        if store.undo(id) {
                            sfx(.undo)
                            stage.say("已撤销，经验和回血一起撤回。")
                        }
                    }
                    .buttonStyle(.quiet)
                }
            }
            HStack(spacing: 10) {
                Button("带去议事") { stage.openCouncil(task: id) }.buttonStyle(.quiet)
                Button("带进剧场") { stage.startLab(task: quest) }.buttonStyle(.quiet)
            }
            if !quest.done && !store.closed {
                Button("目标变了？") {
                    sfx(.open)
                    adjusting = true
                }
                .buttonStyle(.tap)
                .font(.subheadline)
                .foregroundStyle(Theme.dim)
                .padding(.top, 4)
            }
        }
    }

    private var footprints: some View {
        let events = store.events(for: id).suffix(5)
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeading("足迹")
            ForEach(Array(events)) { event in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(event.time).font(.caption).monospacedDigit().foregroundStyle(Theme.dim)
                    Text(event.text).font(.subheadline).foregroundStyle(Theme.text.opacity(0.9))
                }
            }
        }
    }
}

/// 行动计时。
struct FocusPanel: View {
    let quest: Quest
    let askSwitch: () -> Void
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var focus: FocusTimer
    @EnvironmentObject private var stage: Stage
    @State private var stopped: TimeInterval?

    var body: some View {
        let _ = focus.beat
        let mine = focus.state?.taskId == quest.id && focus.state?.demo == store.demo
        let running = mine && focus.state?.running == true
        let finished = mine && focus.state?.finished == true
        let seconds = mine ? focus.elapsed() : 0
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(FocusTimer.format(seconds))
                    .font(.system(size: 46, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(running ? Theme.text : Theme.dim)
                    .contentTransition(.numericText())
                Spacer()
                Text(!mine ? "先做一会儿" : finished ? "计时已结束" : running ? "正在计时" : "已暂停")
                    .font(.subheadline)
                    .foregroundStyle(Theme.dim)
            }
            Meter(value: seconds / Double(max(1, quest.estimate) * 60))
            HStack(spacing: 10) {
                if !mine || finished {
                    Button("开始计时") { start() }.buttonStyle(.quiet)
                } else {
                    Button(running ? "暂停" : "继续") {
                        if running {
                            focus.pause()
                            sfx(.focusPause)
                        } else {
                            focus.resume()
                            sfx(.focusStart)
                        }
                    }
                    .buttonStyle(.quiet)
                    Button("结束") {
                        stopped = focus.stop()
                        sfx(.focusEnd)
                    }
                    .buttonStyle(.quiet)
                }
            }
        }
        .raised()
        .alert("这段计时结束了", isPresented: Binding(get: { stopped != nil }, set: { if !$0 { stopped = nil } })) {
            Button("好") {}
        } message: {
            Text("\(Int((stopped ?? 0) / 60)) 分 \(Int(stopped ?? 0) % 60) 秒。做没做完，由你来登记。")
        }
    }

    private func start() {
        if let other = focus.activeTask, other != quest.id {
            askSwitch()
            return
        }
        focus.start(quest.id, date: store.today.id, demo: store.demo)
        sfx(.focusStart)
    }
}
