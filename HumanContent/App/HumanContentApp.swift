import SwiftUI

@main
struct HumanContentApp: App {
    @StateObject private var store = Store()
    @StateObject private var focus = FocusTimer()
    @StateObject private var stage = Stage()
    @StateObject private var sound = SoundEngine.shared
    @StateObject private var music = MusicPlayer.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(focus)
                .environmentObject(stage)
                .environmentObject(sound)
                .environmentObject(music)
                .preferredColorScheme(.dark)
                .tint(Theme.ember)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var focus: FocusTimer
    @EnvironmentObject private var stage: Stage
    @EnvironmentObject private var sound: SoundEngine
    @EnvironmentObject private var music: MusicPlayer
    @Environment(\.scenePhase) private var scenePhase

    let minute = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        TabView(selection: $stage.tab) {
            VillageView()
                .tabItem { Label("山庄", systemImage: "house.lodge") }
                .tag(AppTab.village)
            TasksRoot()
                .tabItem { Label("待办", systemImage: "checklist") }
                .tag(AppTab.tasks)
                .badge(store.pending)
            CouncilRoot()
                .tabItem { Label("议事", systemImage: "bubble.left.and.bubble.right") }
                .tag(AppTab.council)
            PuppetsRoot()
                .tabItem { Label("木偶", systemImage: "theatermasks") }
                .tag(AppTab.puppets)
            EchoRoot()
                .tabItem { Label("回声", systemImage: "waveform") }
                .tag(AppTab.echo)
        }
        .overlay(alignment: .bottom) {
            if let toast = stage.toast {
                ToastView(text: toast).padding(.bottom, 62)
            }
        }
        .overlay {
            if let flash = stage.flash {
                FlashView(flash: flash).id(flash.id)
            }
        }
        .sheet(item: $stage.sheet) { route in
            Group {
                switch route {
                case .map: MapSheet()
                case .sound: SoundSheet()
                case .music: MusicSheet()
                case .help: HelpSheet()
                case .labMenu: LabMenuSheet()
                case .district(let id): DistrictSheet(place: id)
                }
            }
            .preferredColorScheme(.dark)
        }
        .fullScreenCover(item: $stage.lab) { entry in
            LabView(entry: entry).preferredColorScheme(.dark)
        }
        .onChange(of: stage.tab) { _, _ in sfx(.nav) }
        .onChange(of: sound.enabled) { _, on in music.setMuted(!on) }
        .onChange(of: scenePhase) { _, phase in
            let active = phase == .active
            sound.setActive(active)
            music.setActive(active)
            if active { newDayCheck() }
        }
        .onReceive(minute) { _ in newDayCheck() }
        .onAppear {
            focus.startTicking()
            music.setMuted(!sound.enabled)
            if store.loadWarning { stage.say("原有记录没能读出来，现在是一座空山庄。") }
        }
    }

    private func newDayCheck() {
        if store.rolloverIfNeeded() {
            stage.taskPath = []
            stage.say("新的一天。昨天的约定已经结算入档。")
        }
    }
}

/// 除山庄外的四个标签页共用：示例提示条和计时条。
struct TabChrome: ViewModifier {
    @EnvironmentObject private var store: Store

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                FocusDock().padding(.bottom, 8)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if store.demo {
                    HStack {
                        Text("正在体验示例，不写入你的档案").font(.footnote)
                        Spacer()
                        Button("退出示例") {
                            store.exitDemo()
                            sfx(.close)
                        }
                        .font(.footnote.weight(.semibold))
                    }
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(Theme.ember)
                }
            }
            .toolbarBackground(Theme.night, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
            .toolbarBackground(Theme.night, for: .navigationBar)
    }
}

extension View {
    func tabChrome() -> some View { modifier(TabChrome()) }
}
