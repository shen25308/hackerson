import SwiftUI

enum AppTab: Hashable {
    case village, tasks, council, puppets, echo
}

enum TaskRoute: Hashable {
    case detail(String)
    case settle
}

enum CouncilMode: Hashable {
    case slips, talk
}

/// 反向体验从哪一幕开始、带着哪件事进去。
struct LabEntry: Identifiable, Equatable {
    let id = UUID()
    var level: String
    var taskId: String?
    var taskTitle: String
}

enum SheetRoute: Identifiable, Equatable {
    case map, sound, music, help, labMenu
    case district(String)

    var id: String {
        switch self {
        case .map: return "map"
        case .sound: return "sound"
        case .music: return "music"
        case .help: return "help"
        case .labMenu: return "labMenu"
        case .district(let d): return "district-" + d
        }
    }
}

struct Flash: Identifiable, Equatable {
    let id = UUID()
    var big: String
    var small: String
    var bad: Bool
}

/// 页面之间的去向，以及全局的提示。
final class Stage: ObservableObject {
    @Published var tab: AppTab = .village
    @Published var taskPath: [TaskRoute] = []
    @Published var councilMode: CouncilMode = .slips
    @Published var councilTask: String?
    @Published var talkOnline = false
    @Published var sheet: SheetRoute?
    @Published var lab: LabEntry?
    @Published var toast: String?
    @Published var flash: Flash?

    private var toastWork: DispatchWorkItem?
    private var flashWork: DispatchWorkItem?

    func say(_ text: String) {
        toastWork?.cancel()
        withAnimation(.spring(duration: 0.3)) { toast = text }
        let work = DispatchWorkItem { [weak self] in
            withAnimation(.easeOut(duration: 0.25)) { self?.toast = nil }
        }
        toastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.6, execute: work)
    }

    func announce(_ big: String, _ small: String = "", bad: Bool = false) {
        flashWork?.cancel()
        flash = Flash(big: big, small: small, bad: bad)
        let work = DispatchWorkItem { [weak self] in
            withAnimation(.easeOut(duration: 0.3)) { self?.flash = nil }
        }
        flashWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.7, execute: work)
    }

    func go(_ next: AppTab) {
        sheet = nil
        if tab != next { sfx(.nav) }
        tab = next
    }

    func openTask(_ id: String) {
        sheet = nil
        tab = .tasks
        taskPath = [.detail(id)]
        sfx(.nav)
    }

    func openSettle() {
        sheet = nil
        tab = .tasks
        taskPath = [.settle]
        sfx(.nav)
    }

    func openCouncil(task: String?) {
        sheet = nil
        if let task { councilTask = task }
        councilMode = .slips
        tab = .council
        sfx(.nav)
    }

    func openTalk(online: Bool) {
        sheet = nil
        councilMode = .talk
        talkOnline = online
        tab = .council
        sfx(.nav)
    }

    func startLab(level: String = "intro", task: Quest? = nil) {
        sheet = nil
        lab = LabEntry(level: level, taskId: task?.id, taskTitle: task?.title ?? "")
        sfx(.open)
    }

    /// 从地图或山庄走进一处地点。
    func enter(_ place: String) {
        switch place {
        case "board": go(.tasks)
        case "theater", "backstage": sheet = .labMenu
        case "fire": openTalk(online: false)
        case "tower": go(.echo)
        case "ferry": openTalk(online: true)
        case "decisions", "mirror", "experiment": sheet = .district(place)
        default: break
        }
    }
}

// MARK: 全局反馈

struct ToastView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Theme.ink)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Theme.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
            .padding(.horizontal, 18)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// 屏幕中央的大字，带几颗散开的火星。
struct FlashView: View {
    let flash: Flash
    @State private var burst = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var color: Color { flash.bad ? Theme.rose : Theme.ember }

    var body: some View {
        ZStack {
            if !reduceMotion {
                ForEach(0..<12, id: \.self) { i in
                    let angle = Double(i) / 12 * 2 * Double.pi + Double(i % 3) * 0.3
                    let distance = 70.0 + Double((i * 37) % 90)
                    Circle()
                        .fill(color)
                        .frame(width: 6, height: 6)
                        .offset(x: burst ? cos(angle) * distance : 0, y: burst ? sin(angle) * distance : 0)
                        .opacity(burst ? 0 : 1)
                }
            }
            VStack(spacing: 6) {
                Text(flash.big).font(Theme.brush(40)).foregroundStyle(color)
                if !flash.small.isEmpty {
                    Text(flash.small).font(.subheadline.weight(.medium)).foregroundStyle(Theme.text)
                }
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 18)
            .background(Theme.night.opacity(0.92), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .scaleEffect(burst ? 1 : 0.8)
        }
        .allowsHitTesting(false)
        .transition(.opacity)
        .onAppear {
            withAnimation(.spring(duration: 0.45, bounce: 0.35)) { burst = true }
        }
    }
}

/// 贴在标签栏上方的计时条，离开任务页也能看到。
struct FocusDock: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var focus: FocusTimer
    @EnvironmentObject private var stage: Stage

    var body: some View {
        if let id = focus.activeTask, let quest = store.quest(id), focus.state?.demo == store.demo {
            let _ = focus.beat
            HStack(spacing: 12) {
                Button {
                    stage.openTask(id)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "timer").foregroundStyle(Theme.ember)
                        Text(quest.title).lineLimit(1).foregroundStyle(Theme.text)
                        Spacer(minLength: 4)
                        Text(FocusTimer.format(focus.elapsed())).monospacedDigit().foregroundStyle(Theme.text)
                    }
                }
                .buttonStyle(.tap)
                Button {
                    if focus.state?.running == true {
                        focus.pause()
                        sfx(.focusPause)
                    } else {
                        focus.resume()
                        sfx(.focusStart)
                    }
                } label: {
                    Image(systemName: focus.state?.running == true ? "pause.fill" : "play.fill")
                        .frame(width: 34, height: 34)
                        .foregroundStyle(Theme.ink)
                        .background(Theme.ember, in: Circle())
                }
                .accessibilityLabel(focus.state?.running == true ? "暂停计时" : "继续计时")
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
            .padding(.horizontal, 14)
        }
    }
}
