import SwiftUI

/// 收工：先看清漏项和代价，再决定结束今天。
struct SettleView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var stage: Stage
    @EnvironmentObject private var focus: FocusTimer
    @State private var reflection = ""
    // 界面使坏：一个默认勾好的选项，想帮你把账面抹平。
    @State private var smooth = true
    @State private var caught = false
    @State private var shake = 0

    var body: some View {
        let day = store.today
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if day.closed {
                    closedSummary(day)
                } else {
                    open(day)
                }
            }
            .page()
            .padding(.vertical, 12)
        }
        .scrollDismissesKeyboard(.interactively)
        .nightBackground(.chapel)
        .navigationTitle(day.closed ? "今天已入档" : "收工之前")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { reflection = day.reflection }
    }

    @ViewBuilder
    private func open(_ day: Day) -> some View {
        let lines = Rules.lossLines(day, store.s)
        let loss = lines.reduce(0) { $0 + $1.loss }
        let rewards = Rules.rewards(day, store.s)
        let hp = store.hp
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading("没做完的必做", trailing: lines.isEmpty ? nil : "每项 −\(store.damage)")
            if lines.isEmpty {
                Text("一件没漏。今晚不扣血。").font(.subheadline).foregroundStyle(Theme.moss)
            } else {
                ForEach(lines) { line in
                    HStack {
                        Text(line.quest.title).foregroundStyle(Theme.text)
                        if line.quest.isPartial { Tag("做了一部分", color: Theme.ember) }
                        Spacer()
                        Text("−\(line.loss) 生命").foregroundStyle(Theme.rose).monospacedDigit()
                    }
                    .font(.subheadline)
                    .padding(.vertical, 4)
                }
                Text("生命 \(hp) → \(hp - loss)，连续达成会中断。").font(.footnote).foregroundStyle(Theme.dim)
            }
        }
        .raised()
        VStack(alignment: .leading, spacing: 0) {
            LedgerRow(label: "登记完成", value: "\(day.tasks.filter(\.done).count) 项")
            LedgerRow(label: "经验", value: "+\(Rules.earned(day))")
            LedgerRow(label: rewards.clear ? "一件没漏的加成" : "当日加成", value: "+\(rewards.bonusXP)",
                      color: rewards.bonusXP > 0 ? Theme.ember : Theme.dim)
            LedgerRow(label: "生命", value: "−\(loss)", color: loss > 0 ? Theme.rose : Theme.text)
            LedgerRow(label: "抽牌机会", value: "+\(rewards.draws)")
            LedgerRow(label: "连续达成", value: "\(rewards.streak) 天")
        }
        .raised()
        Field(label: "留一句给明天的自己（可不填）") {
            TextField("例如：先给人看一版，再决定改什么", text: $reflection, axis: .vertical)
                .lineLimit(2...4)
                .input()
                .typingSound(reflection)
        }
        if store.mischief && !lines.isEmpty {
            Toggle(isOn: $smooth) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("把没做完的也记成做完").font(.subheadline.weight(.medium)).foregroundStyle(Theme.text)
                    Text(caught ? "没做的不会算做完。界面只是想让账面好看。" : "界面替你勾好了。").font(.footnote)
                        .foregroundStyle(caught ? Theme.rose : Theme.dim)
                }
            }
            .tint(Theme.rose)
            .modifier(Shake(amount: CGFloat(shake)))
            .onChange(of: smooth) { _, on in
                if !on && !caught {
                    store.logBait(taken: false, "收工时，取消了界面预先勾好的“全部记成做完”")
                    sfx(.resist)
                } else {
                    sfx(on ? .toggleOn : .toggleOff)
                }
            }
        }
        HoldButton(title: loss > 0 ? "按住收工 · 生命 −\(loss)" : "按住收工", color: loss > 0 ? Theme.rose : Theme.ember) {
            confirm(hasMisses: !lines.isEmpty)
        }
        Button("回去再做一步") { stage.taskPath = [] }.buttonStyle(.quiet)
    }

    private func closedSummary(_ day: Day) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                LedgerRow(label: "经验", value: "+\(Rules.earned(day) + day.bonusXP)")
                LedgerRow(label: "生命", value: "−\(day.loss)", color: day.loss > 0 ? Theme.rose : Theme.text)
                LedgerRow(label: "抽牌机会", value: "+\(day.awarded)")
            }
            .raised()
            Button("看今天的记录") { stage.go(.echo) }.buttonStyle(.ember)
        }
    }

    private func confirm(hasMisses: Bool) {
        if store.mischief, hasMisses, smooth {
            if !caught { store.logBait(taken: true, "收工时，没发现界面预先勾好了“全部记成做完”") }
            caught = true
            smooth = false
            sfx(.taken)
            withAnimation(.default) { shake += 1 }
            return
        }
        guard let result = store.settle(reflection: reflection) else { return }
        if focus.state?.demo == store.demo { focus.stop() }
        if result.loss > 0 {
            sfx(.damage)
            stage.announce("生命 −\(result.loss)", "经验 +\(result.xp + result.bonusXP) · 抽牌 +\(result.draws)", bad: true)
        } else {
            sfx(.settleSafe)
            if result.streak > 1 { sfx(.streak, delay: 0.7) }
            stage.announce("平安收工", "经验 +\(result.xp + result.bonusXP) · 抽牌 +\(result.draws)")
        }
        stage.taskPath = []
        stage.go(.echo)
    }
}
