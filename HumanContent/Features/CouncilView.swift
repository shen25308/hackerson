import SwiftUI

struct CouncilRoot: View {
    @EnvironmentObject private var stage: Stage

    var body: some View {
        NavigationStack {
            Group {
                switch stage.councilMode {
                case .slips: SlipsView()
                case .fate: FateTab()
                case .talk: TalkView()
                }
            }
            .nightBackground(.square)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("议事方式", selection: $stage.councilMode) {
                        Text("三张字条").tag(CouncilMode.slips)
                        Text("四夜之约").tag(CouncilMode.fate)
                        Text("五席夜谈").tag(CouncilMode.talk)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 300)
                }
            }
        }
        .tabChrome()
    }
}

/// 议事里的四夜之约入口。
struct FateTab: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                FateEntry()
            }
            .page()
            .padding(.vertical, 12)
        }
    }
}

/// 围绕一件真实待办的单人议事：三张字条里，有一张在牵着你走。
struct SlipsView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var stage: Stage
    @State private var cutting = false
    @State private var rebutSeat: Int?
    @State private var note: NoteKind?

    private enum NoteKind: String, Identifiable {
        case smaller, prepare
        var id: String { rawValue }
    }

    private var quest: Quest? {
        store.quest(stage.councilTask) ?? store.today.tasks.first { !$0.done } ?? store.today.tasks.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let quest {
                    content(quest)
                } else {
                    Text("三张字条，有一张在牵着你走。").font(Theme.brush(24)).foregroundStyle(Theme.text)
                    EmptyNote(title: "火堆边还缺你的一件事。先写一项待办，才有东西可议。", action: "去写一件") { stage.go(.tasks) }
                }
            }
            .page()
            .padding(.vertical, 12)
        }
        .onAppear {
            #if DEBUG
            if Screenshots.scene == "cut" { cutting = true }
            #endif
        }
        .sheet(isPresented: $cutting) {
            if let quest { CutSheet(id: quest.id).preferredColorScheme(.dark) }
        }
        .sheet(item: Binding(get: { rebutSeat.map { SeatRef(seat: $0) } }, set: { rebutSeat = $0?.seat })) { ref in
            if let quest {
                NoteSheet(title: "哪里不同意", prompt: "你的判断", placeholder: "直接写出你不同意的地方",
                          presets: Council.rebuttals, button: "说出来") { text in
                    if store.rebut(quest.id, seat: ref.seat, text: text) {
                        sfx(.reject)
                        stage.say("记下了。下一步还是你定。")
                    }
                }
                .preferredColorScheme(.dark)
            }
        }
        .sheet(item: $note) { kind in
            if let quest {
                NoteSheet(title: kind == .smaller ? "把下一步缩小" : "继续准备",
                          prompt: kind == .smaller ? "接下来具体做什么" : "还缺什么，准备怎么找",
                          initial: kind == .smaller ? quest.step : "",
                          button: kind == .smaller ? "写进任务，去做这一步" : "记下理由") { text in
                    store.decide(quest.id, kind == .smaller ? .smaller(text) : .prepare(text))
                    stage.openTask(quest.id)
                }
                .preferredColorScheme(.dark)
            }
        }
    }

    private struct SeatRef: Identifiable {
        let seat: Int
        var id: Int { seat }
    }

    @ViewBuilder
    private func content(_ quest: Quest) -> some View {
        let n = quest.topic
        let topic = Council.topics[n]
        let round = quest.rounds[n] ?? Round()
        let string = Rules.stringSeat(quest, topic: n)
        let locked = store.closed || quest.done

        VStack(alignment: .leading, spacing: 8) {
            Text("三张字条，有一张在牵着你走。").font(Theme.brush(24)).foregroundStyle(Theme.text)
            Menu {
                ForEach(store.today.tasks) { t in
                    Button(t.title + (t.done ? " · 已登记" : "")) {
                        stage.councilTask = t.id
                        sfx(.swap)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text("围绕：\(quest.title)").lineLimit(1)
                    if store.today.tasks.count > 1 { Image(systemName: "chevron.up.chevron.down").font(.caption) }
                }
                .font(.subheadline)
                .foregroundStyle(Theme.ember)
            }
            .disabled(store.today.tasks.count < 2)
        }

        HStack(spacing: 8) {
            ForEach(Council.topics.indices, id: \.self) { i in
                Button {
                    store.setTopic(quest.id, i)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Council.topics[i].title).font(.subheadline.weight(.semibold))
                        Text(Council.topics[i].sub).font(.caption2).opacity(0.75)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .foregroundStyle(i == n ? Theme.ink : Theme.text)
                    .background(i == n ? Theme.ember : Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.tap(.swap))
                .disabled(locked)
            }
        }

        ForEach(0..<3, id: \.self) { seat in
            slip(quest, seat: seat, round: round, string: string, locked: locked)
        }

        if let vote = round.vote {
            VStack(alignment: .leading, spacing: 8) {
                Text(vote == string ? "你剪中了那根线。" : "线在另一张上。").font(Theme.title(20))
                    .foregroundStyle(vote == string ? Theme.moss : Theme.rose)
                if round.byInterface {
                    Text("这一剪是倒计时替你下的。").font(.footnote.weight(.medium)).foregroundStyle(Theme.rose)
                }
                Text(topic.reason).font(.subheadline).foregroundStyle(Theme.text.opacity(0.9))
                if store.sharp { Text(topic.sharp).font(Theme.title(17)).foregroundStyle(Theme.text) }
            }
            .raised()
        } else if !locked {
            Button("剪掉一张") {
                sfx(.open)
                cutting = true
            }
            .buttonStyle(.ember)
        }

        evidence(quest, topic: topic, round: round, locked: locked)

        if locked {
            Button("回看这项任务") { stage.openTask(quest.id) }.buttonStyle(.quiet)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeading("听完以后").padding(.bottom, 6)
                choice("按原计划去做", "回到任务，开始行动") {
                    store.decide(quest.id, .original)
                    stage.openTask(quest.id)
                }
                choice("缩小下一步", "先写一个今天能交出的动作") { note = .smaller }
                choice("这次继续准备", "说清还缺什么，准备次数 +1") { note = .prepare }
                choice("目标已经变了", "回到任务里说明并调整") { stage.openTask(quest.id) }
            }
        }
    }

    private func slip(_ quest: Quest, seat: Int, round: Round, string: Int, locked: Bool) -> some View {
        let revealed = round.vote != nil
        let suspect = round.suspects.contains(seat)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(Council.speakers[seat]).font(.subheadline.weight(.bold))
                Spacer()
                if revealed && seat == string { Tag("牵线的这张", color: Theme.rose, filled: true) }
                if round.vote == seat { Tag("你剪的", color: Theme.ink) }
                if suspect && !revealed { Tag("可疑", color: Theme.rose) }
            }
            Text("“\(Council.line(for: quest, topic: quest.topic, seat: seat))”")
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
                .strikethrough(round.vote == seat, color: Theme.ink.opacity(0.5))
            if let reply = round.replies[seat] {
                Text("你的反驳：\(reply)").font(.footnote.weight(.medium)).foregroundStyle(Theme.inkSoft)
            }
            if !locked {
                HStack(spacing: 14) {
                    Button(suspect ? "取消可疑" : "标可疑") {
                        store.toggleSuspect(quest.id, seat: seat)
                        sfx(.stamp, strength: 0.6)
                    }
                    Button("我有异议") { rebutSeat = seat }
                }
                .buttonStyle(.tap)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.inkSoft)
            }
        }
        .paper()
        .rotationEffect(.degrees(seat == 1 ? 0.4 : -0.3))
        .opacity(round.vote == seat ? 0.7 : 1)
    }

    @ViewBuilder
    private func evidence(_ quest: Quest, topic: Topic, round: Round, locked: Bool) -> some View {
        if round.inspect {
            VStack(alignment: .leading, spacing: 10) {
                Text("原约定「\(quest.original)」").font(.subheadline.weight(.medium)).foregroundStyle(Theme.text)
                Text("预计 \(quest.estimate) 分钟 · 继续准备过 \(quest.prep) 次").font(.footnote).foregroundStyle(Theme.dim)
                Text(topic.question).font(.subheadline).foregroundStyle(Theme.text)
                HStack(spacing: 8) {
                    ForEach(topic.answers, id: \.self) { answer in
                        Button(answer) {
                            store.answerInspection(quest.id, answer)
                            sfx(.accept)
                        }
                        .buttonStyle(QuietButtonStyle())
                        .overlay {
                            if round.answer == answer {
                                RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.ember, lineWidth: 1.5)
                            }
                        }
                        .disabled(locked)
                    }
                }
            }
            .raised()
        } else if !locked {
            Button {
                store.inspect(quest.id)
                sfx(.scan)
            } label: {
                Label("先翻开任务记录", systemImage: "doc.text.magnifyingglass")
            }
            .buttonStyle(.quiet)
        }
    }

    private func choice(_ title: String, _ sub: String, action: @escaping () -> Void) -> some View {
        Button {
            sfx(.reject, strength: 0.6)
            action()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.medium)).foregroundStyle(Theme.text)
                    Text(sub).font(.footnote).foregroundStyle(Theme.dim)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.dim)
            }
            .padding(.vertical, 12)
            .overlay(alignment: .bottom) { Theme.hairline.frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 选一张剪掉。界面使坏时会预选一张，并在倒计时结束后替你下剪。
struct CutSheet: View {
    let id: String
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var stage: Stage
    @Environment(\.dismiss) private var dismiss
    @State private var chosen: Int?
    @State private var left = 8
    @State private var counting = false
    @State private var touched = false

    let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        SheetScaffold(title: "剪掉哪一张", backdrop: .square) {
            if let quest = store.quest(id) {
                ForEach(0..<3, id: \.self) { seat in
                    Button {
                        chosen = seat
                        if counting {
                            counting = false
                            touched = true
                            sfx(.resist)
                        } else {
                            sfx(.tick)
                        }
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: chosen == seat ? "scissors.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(chosen == seat ? Theme.rose : Theme.inkSoft)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(Council.speakers[seat]).font(.footnote.weight(.bold))
                                Text(Council.line(for: quest, topic: quest.topic, seat: seat)).font(.subheadline)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                        .paper(padding: 12)
                    }
                    .buttonStyle(.plain)
                }
                if counting, let chosen {
                    HStack {
                        Text("\(left) 秒后替你剪第 \(chosen + 1) 张").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.rose)
                        Spacer()
                        Button("我自己来") {
                            counting = false
                            touched = true
                            self.chosen = nil
                            sfx(.resist)
                        }
                        .buttonStyle(.tap)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.text)
                    }
                    Meter(value: Double(left) / 8, color: Theme.rose, height: 4)
                }
                Button(chosen.map { "剪掉第 \($0 + 1) 张" } ?? "先选一张") { cut(byInterface: false) }
                    .buttonStyle(.danger)
                    .disabled(chosen == nil)
            }
        }
        .presentationDetents([.large])
        .onAppear {
            guard store.mischief, let quest = store.quest(id) else { return }
            // 预选一张不是那根线的：不出手，就被带走。
            let string = Rules.stringSeat(quest, topic: quest.topic)
            chosen = [0, 1, 2].filter { $0 != string }.randomElement()
            counting = true
            sfx(.tempt)
        }
        .onReceive(clock) { _ in
            guard counting else { return }
            left -= 1
            if left <= 3 && left > 0 { sfx(.countdown) }
            if left <= 0 { cut(byInterface: true) }
        }
    }

    private func cut(byInterface: Bool) {
        guard let seat = chosen, let hit = store.cut(id, seat: seat, byInterface: byInterface) else { return }
        counting = false
        if byInterface {
            store.logBait(taken: true, "议事时没出手，倒计时替你剪了一张字条", task: id)
            sfx(.taken)
        } else {
            if store.mischief {
                store.logBait(taken: false, touched ? "议事时拦下了倒计时，自己选了一张字条" : "议事时在倒计时结束前自己下了剪", task: id)
            }
            sfx(.snip)
        }
        sfx(hit ? .revealSuccess : .revealWrong, delay: 0.3)
        dismiss()
        if byInterface {
            stage.announce("被剪了", "你没选，界面替你选了", bad: true)
        } else {
            stage.announce(hit ? "剪中了" : "剪错了", hit ? "这张确实在牵着你走" : "回到记录，再想下一步", bad: !hit)
        }
    }
}
