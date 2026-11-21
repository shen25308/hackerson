import SwiftUI

/// 木偶剧场的入口：带哪件事进去、从哪一幕开始。
struct LabMenuSheet: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var stage: Stage
    @State private var taskId = ""
    @State private var denied = 0
    @State private var deniedKey = ""

    var body: some View {
        SheetScaffold(title: "木偶剧场") {
            VStack(alignment: .leading, spacing: 8) {
                Text("这次，界面是来捣乱的。").font(Theme.brush(24)).foregroundStyle(Theme.text)
                Text("按钮会追你，选项会换位，它还会替你默认同意。")
                    .font(.subheadline)
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !store.today.tasks.isEmpty {
                Field(label: "带哪件事进去") {
                    Picker("带哪件事进去", selection: $taskId) {
                        Text("先用示例").tag("")
                        ForEach(store.today.tasks) { quest in
                            Text(quest.title).tag(quest.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Theme.ember)
                    .onChange(of: taskId) { _, _ in sfx(.tick) }
                }
            }
            Button("从序章开始") { start("intro") }
                .buttonStyle(.ember)
            VStack(spacing: 0) {
                ForEach(LabData.menu) { item in
                    row(item)
                }
            }
        }
        .onAppear {
            taskId = store.today.tasks.first { !$0.done }?.id ?? ""
        }
    }

    private func locked(_ key: String) -> Bool {
        LabData.backstage.contains(key) && !store.isOpen("backstage")
    }

    private func row(_ item: LabData.MenuItem) -> some View {
        let isLocked = locked(item.key)
        let need = max(1, (Atlas.place("backstage")?.need ?? 2) - store.gateCount)
        return Button {
            if isLocked {
                sfx(.lock)
                deniedKey = item.key
                withAnimation(.default) { denied += 1 }
            } else {
                start(item.key)
            }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title).font(.body.weight(.semibold)).foregroundStyle(isLocked ? Theme.dim : Theme.text)
                    Text(isLocked ? "再做完 \(need) 项任务开门" : item.line)
                        .font(.footnote)
                        .foregroundStyle(Theme.dim)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: isLocked ? "lock.fill" : "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.dim)
            }
            .padding(.vertical, 13)
            .overlay(alignment: .bottom) { Theme.hairline.frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(Shake(amount: isLocked && deniedKey == item.key ? CGFloat(denied) : 0))
        .accessibilityLabel(isLocked ? "\(item.title)，还差 \(need) 项任务才开门" : "\(item.title)，\(item.line)")
    }

    /// 先收起这张面板，再拉开剧场的幕。
    private func start(_ level: String) {
        let stage = self.stage
        let quest = taskId.isEmpty ? nil : store.quest(taskId)
        stage.sheet = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            stage.startLab(level: level, task: quest)
        }
    }
}
