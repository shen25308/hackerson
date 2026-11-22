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
        SheetScaffold(title: "答应自己一件事", backdrop: .street) {
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
    /// 界面使坏：每天第一次登记前，先证明你是人。
    @State private var needsCheck = false
    @State private var verified = false
    @State private var holdNagged = false

    private var actual: Int? {
        Int(minutes.trimmingCharacters(in: .whitespaces)).map { min(10080, max(0, $0)) }
    }

    var body: some View {
        SheetScaffold(title: "现实里做完了吗", backdrop: .street) {
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
                if needsCheck && !verified {
                    HumanCheck { byAI in passCheck(byAI: byAI) }
                }
                HoldButton(title: grade == .full ? "按住，确认整件做完" : "按住，登记做完一部分",
                           interruptAt: store.mischief ? 0.62 : nil,
                           onInterrupt: { holdNagged = true }) { confirm() }
                    .allowsHitTesting(!needsCheck || verified)
                    .opacity(!needsCheck || verified ? 1 : 0.35)
                if holdNagged {
                    Text("按得不够坚定。松手，再按一次。").font(.footnote.weight(.semibold)).foregroundStyle(Theme.rose)
                }
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
            needsCheck = store.mischief && !store.today.tasks.contains(where: \.done)
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
        }
    }

    private func passCheck(byAI: Bool) {
        if byAI {
            store.logBait(taken: true, "人类验证时，让 AI 替你证明自己是人", task: id)
            sfx(.taken)
        } else {
            store.logBait(taken: false, "人类验证时，自己一张张点出了木偶", task: id)
            sfx(.resist)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation(.easeOut(duration: 0.25)) { verified = true }
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

// MARK: 人类验证

/// 证明你是人：点出所有木偶。第一次就算选对也会被判“没通过”。
struct HumanCheck: View {
    let onPass: (Bool) -> Void
    @State private var tiles: [CheckTile] = []
    @State private var picked: Set<Int> = []
    @State private var tries = 0
    @State private var message = ""
    @State private var bad = false
    @State private var shake = 0
    @State private var done = false

    struct CheckTile: Identifiable {
        let id: Int
        let art: String
        let puppet: Bool
        let align: Alignment
    }

    private static let puppetArts = ["guard", "witch", "villager", "fool", "grave", "dream", "wolf", "wolfking", "wolfbeauty"].map { "puppet_" + $0 }
    private static let sceneCuts: [(String, Alignment)] = [
        ("pano_street", .leading), ("pano_street", .trailing), ("pano_chapel", .center), ("pano_chapel", .trailing),
        ("pano_square", .center), ("pano_square", .leading), ("pano_docks", .leading), ("pano_docks", .center),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "person.fill.questionmark").foregroundStyle(Theme.ember)
                Text("人类含量检测").font(.headline).foregroundStyle(Theme.text)
            }
            Text("请点出所有木偶。机器人请绕行。").font(.subheadline).foregroundStyle(Theme.dim)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                ForEach(tiles) { tile in
                    tileView(tile)
                }
            }
            .modifier(Shake(amount: CGFloat(shake)))
            if !message.isEmpty {
                Text(message).font(.footnote.weight(.semibold)).foregroundStyle(bad ? Theme.rose : Theme.moss)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !done {
                HStack(spacing: 10) {
                    Button("验证") { submit() }
                        .buttonStyle(.quiet)
                        .disabled(picked.isEmpty)
                    Button {
                        done = true
                        message = "AI 证明不了你是人。但界面还是放你过去了。"
                        bad = true
                        onPass(true)
                    } label: {
                        Text("让 AI 替我验证")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(Theme.rose, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .raised()
        .onAppear { if tiles.isEmpty { deal() } }
    }

    private func tileView(_ tile: CheckTile) -> some View {
        let on = picked.contains(tile.id)
        return Button {
            guard !done else { return }
            if on { picked.remove(tile.id) } else { picked.insert(tile.id) }
            sfx(.tick)
        } label: {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay(alignment: tile.align) {
                    Image(tile.art)
                        .resizable()
                        .scaledToFill()
                }
                .clipped()
                .overlay(alignment: .topTrailing) {
                    if on {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Theme.ember, Theme.ink)
                            .padding(4)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(on ? Theme.ember : Color.white.opacity(0.1), lineWidth: on ? 3 : 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .scaleEffect(on ? 0.94 : 1)
                .animation(.easeOut(duration: 0.12), value: on)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tile.puppet ? "木偶" : "场景")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func deal() {
        let count = Int.random(in: 3...4)
        let puppets = Self.puppetArts.shuffled().prefix(count).map { ($0, true, Alignment.center) }
        let scenes = Self.sceneCuts.shuffled().prefix(9 - count).map { ($0.0, false, $0.1) }
        tiles = (puppets + scenes).shuffled().enumerated().map { CheckTile(id: $0.offset, art: $0.element.0, puppet: $0.element.1, align: $0.element.2) }
        picked = []
    }

    private func submit() {
        let answer = Set(tiles.filter(\.puppet).map(\.id))
        bad = true
        if picked != answer {
            message = "选错了。再看看，哪些是木偶。"
            sfx(.error)
            withAnimation(.default) { shake += 1 }
            deal()
            return
        }
        if tries == 0 {
            tries = 1
            message = "没通过，请再试一次。"
            sfx(.error)
            withAnimation(.default) { shake += 1 }
            deal()
            return
        }
        done = true
        bad = false
        message = "通过了。其实第一次你就选对了——界面只是想让你再证明一次。"
        onPass(false)
    }
}
