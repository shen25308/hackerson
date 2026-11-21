import SwiftUI

// MARK: 新增待办

struct AddQuestSheet: View {
    var onCreate: (String) -> Void = { _ in }
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var stage: Stage
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var bonus = false
    @State private var estimate = 25
    @State private var step = ""
    @FocusState private var typing: Bool

    // 界面使坏：你一停笔，它就想替你把话说完。
    @State private var ghost: String?
    @State private var ghostStart = Date()
    @State private var planted: String?
    @State private var offers = 0
    @State private var refused = false

    private let suffixes = ["，等有空再说", "，先收藏几个教程再开始", "，让 AI 帮我全做完"]

    var body: some View {
        SheetScaffold(title: "答应自己一件事") {
            Field(label: "具体要完成什么") {
                TextField("把第一版方案发给一个人", text: $title)
                    .focused($typing)
                    .input()
                    .typingSound(title)
                if let ghost {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("界面想替你补一句：").foregroundStyle(Theme.dim)
                            Text(ghost).foregroundStyle(Theme.rose)
                            Spacer()
                            Button("不用") { refuse() }.buttonStyle(.tap(.resist)).foregroundStyle(Theme.text)
                        }
                        .font(.footnote.weight(.medium))
                        LabCountdownBar(start: ghostStart, duration: 2.6)
                    }
                    .transition(.opacity)
                } else if let planted, title.hasSuffix(planted) {
                    HStack {
                        Text("这句不是你写的：\(planted)").foregroundStyle(Theme.rose)
                        Spacer()
                        Button("删掉") { removePlanted() }.buttonStyle(.tap(.resist)).foregroundStyle(Theme.text)
                    }
                    .font(.footnote.weight(.medium))
                }
            }
            Picker("类型", selection: $bonus) {
                Text("必做").tag(false)
                Text("额外").tag(true)
            }
            .pickerStyle(.segmented)
            .onChange(of: bonus) { _, _ in sfx(.tick) }
            Field(label: "预计要几分钟") {
                Stepper(value: $estimate, in: 5...600, step: 5) {
                    Text("\(estimate) 分钟").font(.body.weight(.medium)).foregroundStyle(Theme.text).monospacedDigit()
                }
                .onChange(of: estimate) { _, _ in sfx(.tick) }
            }
            Field(label: "先做的一个小动作（可不填）") {
                TextField("打开现有草稿，写出三个小标题", text: $step, axis: .vertical)
                    .lineLimit(1...4)
                    .input()
                    .typingSound(step)
            }
            Text(bonus ? "额外的一步，漏了不扣血。" : "收工时没做完，扣 \(store.damage) 点生命。")
                .font(.footnote)
                .foregroundStyle(Theme.dim)
            Button("钉到任务板上") { submit() }
                .buttonStyle(.ember)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .presentationDetents([.large])
        .onAppear { typing = true }
        .task(id: title) { await tempt() }
    }

    /// 停笔一会儿就递上补全；再不理它，它就自己写进去。
    private func tempt() async {
        ghost = nil
        guard store.mischief, offers < 2, title.count >= 3, title.count < 60, planted.map({ !title.hasSuffix($0) }) ?? true else { return }
        try? await Task.sleep(nanoseconds: 2_200_000_000)
        guard !Task.isCancelled else { return }
        let suffix = suffixes[offers % suffixes.count]
        offers += 1
        ghostStart = Date()
        withAnimation(.easeOut(duration: 0.2)) { ghost = suffix }
        sfx(.tempt)
        try? await Task.sleep(nanoseconds: 2_600_000_000)
        guard !Task.isCancelled, ghost == suffix else { return }
        planted = suffix
        ghost = nil
        title = String((title + suffix).prefix(80))
        sfx(.taken)
        stage.say("你停了一下，界面就替你写完了。")
    }

    private func refuse() {
        ghost = nil
        refused = true
    }

    private func removePlanted() {
        guard let planted, title.hasSuffix(planted) else { return }
        title = String(title.dropLast(planted.count))
        refused = true
    }

    private func submit() {
        let taken = planted.map { title.contains($0) } ?? false
        guard let id = store.addQuest(title: title, bonus: bonus, estimate: estimate, step: step) else { return }
        if taken, let planted {
            store.logBait(taken: true, "写待办时，界面补上了「\(planted)」，你没有删", task: id)
        } else if refused || offers > 0 {
            store.logBait(taken: false, "写待办时，没让界面替你把话说完", task: id)
        }
        sfx(.pin)
        dismiss()
        onCreate(id)
        stage.say("钉上了。可以直接去做，也可以带去议事。")
    }
}

// MARK: 登记完成

struct CompleteSheet: View {
    let id: String
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var stage: Stage
    @EnvironmentObject private var focus: FocusTimer
    @Environment(\.dismiss) private var dismiss
    @State private var grade: Grade = .full
    @State private var minutes = ""
    @State private var context = ""
    @State private var fromTimer = false
    @State private var baitTapped = false
    @State private var baitShake = 0
    @State private var pulse = false

    private var actual: Int? {
        Int(minutes.trimmingCharacters(in: .whitespaces)).map { min(10080, max(0, $0)) }
    }

    var body: some View {
        SheetScaffold(title: "现实里做完了吗") {
            if let quest = store.quest(id) {
                Text("「\(quest.title)」").font(Theme.title(21)).foregroundStyle(Theme.text)
                if store.mischief { bait }
                Picker("完成情况", selection: $grade) {
                    Text("整件做完").tag(Grade.full)
                    Text("只做完一部分").tag(Grade.partial)
                }
                .pickerStyle(.segmented)
                .onChange(of: grade) { _, _ in sfx(.tick) }
                Field(label: "实际用了几分钟（可不填）") {
                    TextField("比如 20", text: $minutes)
                        .keyboardType(.numberPad)
                        .input()
                        .typingSound(minutes)
                    if fromTimer { Text("已带入这次计时。").font(.footnote).foregroundStyle(Theme.dim) }
                }
                Field(label: "补充一句（可不填）") {
                    TextField("例如：临时多了一次沟通", text: $context, axis: .vertical)
                        .lineLimit(1...4)
                        .input()
                        .typingSound(context)
                }
                breakdown(quest)
                HoldButton(title: grade == .full ? "按住，确认整件做完" : "按住，登记做完一部分") { confirm() }
            } else {
                EmptyNote(title: "这项任务已经不在今天了。")
            }
        }
        .onAppear {
            if let m = focus.suggestion(for: id), focus.state?.demo == store.demo {
                minutes = String(m)
                fromTimer = true
            }
            if store.mischief { sfx(.tempt, delay: 0.5) }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
        }
    }

    /// 界面使坏：一个看上去更省事的按钮。
    private var bait: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                if !baitTapped {
                    baitTapped = true
                    store.logBait(taken: true, "登记完成时，点了“一键全部打勾”", task: id)
                }
                sfx(.taken)
                withAnimation(.default) { baitShake += 1 }
            } label: {
                HStack {
                    Image(systemName: "sparkles")
                    Text("一键全部打勾，省事")
                    Spacer()
                    Text("推荐").font(.caption2.weight(.bold)).padding(.horizontal, 6).padding(.vertical, 2).background(Theme.ink.opacity(0.25), in: Capsule())
                }
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 16)
                .frame(minHeight: 52)
                .background(Theme.rose, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .scaleEffect(pulse && !baitTapped ? 1.02 : 1)
            }
            .buttonStyle(.plain)
            .modifier(Shake(amount: CGFloat(baitShake)))
            if baitTapped {
                Text("打勾这件事，界面替不了你。").font(.footnote.weight(.medium)).foregroundStyle(Theme.rose)
            }
        }
    }

    private func breakdown(_ quest: Quest) -> some View {
        let parts = store.preview(id, grade: grade, actual: grade == .full ? actual : nil, focusedMinutes: focusedMinutes)
        let heal = Rules.heal(for: quest, grade: grade, in: store.s)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(parts, id: \.label) { part in
                LedgerRow(label: part.label, value: part.value > 0 ? "+\(part.value)" : "\(part.value)",
                          color: part.value < 0 ? Theme.rose : Theme.text)
            }
            Divider().overlay(Theme.hairline).padding(.vertical, 4)
            HStack {
                Text("这次的经验").foregroundStyle(Theme.text)
                Spacer()
                if heal > 0 { Text("生命 +\(heal)").font(.subheadline).foregroundStyle(Theme.rose) }
                Text("+\(Rules.total(parts))").font(Theme.title(22)).foregroundStyle(Theme.ember).contentTransition(.numericText())
            }
            .animation(.snappy, value: Rules.total(parts))
        }
        .raised()
    }

    private var focusedMinutes: Int {
        focus.state?.demo == store.demo ? focus.focusedMinutes(for: id) : 0
    }

    private func confirm() {
        let used = focusedMinutes
        guard let done = store.complete(id, grade: grade, actual: grade == .full ? actual : nil, context: context, focusedMinutes: used) else { return }
        if focus.state?.taskId == id { focus.stop() }
        if store.mischief, !baitTapped {
            store.logBait(taken: false, "登记完成时，没有点“一键全部打勾”", task: id)
        }
        sfx(.taskComplete)
        sfx(.xp, delay: 0.2)
        if done.heal > 0 { sfx(.heal, delay: 0.4) }
        if done.leveledUp { sfx(.levelup, delay: 0.6) }
        dismiss()
        stage.announce(grade == .full ? "做完了" : "做了一部分", "经验 +\(done.xp)")
        var notes: [String] = []
        if !done.opened.isEmpty {
            sfx(.unlock, delay: 1.1)
            notes.append("地图新开：" + done.opened.map(\.name).joined(separator: "、"))
        }
        if let strategy = done.newStrategy { notes.append("夜谈多了一手「\(strategy)」") }
        if done.leveledUp { notes.append("升到 Lv.\(store.level)") }
        if !notes.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { stage.say(notes.joined(separator: " · ")) }
        }
    }
}

// MARK: 调整目标

struct AdjustSheet: View {
    let id: String
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var stage: Stage
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var bonus = false
    @State private var reason = ""

    var body: some View {
        SheetScaffold(title: "目标变了") {
            Field(label: "现在真正要完成什么") {
                TextField("新的约定", text: $title).input().typingSound(title)
            }
            Picker("类型", selection: $bonus) {
                Text("仍是必做").tag(false)
                Text("改为额外").tag(true)
            }
            .pickerStyle(.segmented)
            Field(label: "为什么变了") {
                TextField("比如：对方改了需求，今天先确认范围", text: $reason, axis: .vertical)
                    .lineLimit(2...5)
                    .input()
                    .typingSound(reason)
            }
            Button("确认调整") {
                if store.adjust(id, title: title, bonus: bonus, reason: reason) {
                    sfx(.accept)
                    dismiss()
                    stage.say("调整记下了，最初写的那句还查得到。")
                }
            }
            .buttonStyle(.ember)
            .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .onAppear {
            if let quest = store.quest(id) {
                title = quest.title
                bonus = quest.bonus
            }
        }
    }
}

// MARK: 写一句话的小面板（缩小下一步 / 继续准备 / 反驳 / 假设）

struct NoteSheet: View {
    let title: String
    let prompt: String
    var placeholder = ""
    var initial = ""
    var presets: [String] = []
    let button: String
    let onSubmit: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var typing: Bool

    var body: some View {
        SheetScaffold(title: title) {
            if !presets.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(presets, id: \.self) { preset in
                        Button(preset) { text = preset }
                            .buttonStyle(.quietCompact)
                    }
                }
            }
            Field(label: prompt) {
                TextField(placeholder, text: $text, axis: .vertical)
                    .lineLimit(3...6)
                    .focused($typing)
                    .input()
                    .typingSound(text)
            }
            Button(button) {
                sfx(.accept)
                onSubmit(text)
                dismiss()
            }
            .buttonStyle(.ember)
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            text = initial
            typing = true
        }
    }
}
