import SwiftUI
import UniformTypeIdentifiers

/// 声音设置和试听。
struct SoundSheet: View {
    @EnvironmentObject private var sound: SoundEngine
    @EnvironmentObject private var stage: Stage

    private static let pad: [Cue] = [
        .pin, .taskComplete, .xp, .levelup, .unlock, .lock,
        .snip, .scan, .revealSuccess, .revealWrong, .tempt, .resist,
        .taken, .drawShuffle, .drawReveal, .damage, .settleSafe, .streak,
        .takeover, .collect, .glitch, .countdown, .fire, .focusEnd,
    ]

    var body: some View {
        SheetScaffold(title: "声音") {
            Toggle("全部声音", isOn: $sound.enabled)
                .onChange(of: sound.enabled) { _, on in if on { sfx(.toggleOn) } }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("音效音量").foregroundStyle(Theme.text)
                    Spacer()
                    Text("\(Int((sound.volume * 100).rounded()))%").foregroundStyle(Theme.dim).monospacedDigit()
                }
                Slider(value: $sound.volume, in: 0...1, step: 0.05)
                    .onChange(of: sound.volume) { _, _ in sfx(.slide) }
            }
            .disabled(!sound.enabled)
            Toggle("触感反馈", isOn: $sound.haptics)
                .onChange(of: sound.haptics) { _, on in sfx(on ? .toggleOn : .toggleOff) }
            Toggle("低频环境声", isOn: $sound.ambience)
                .onChange(of: sound.ambience) { _, on in sfx(on ? .toggleOn : .toggleOff) }
                .disabled(!sound.enabled)
            SectionHeading("试听")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 98), spacing: 8)], spacing: 8) {
                ForEach(Self.pad, id: \.self) { cue in
                    Button(cue.label) {
                        SoundEngine.shared.play(cue, force: true)
                    }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity, minHeight: 42)
                    .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .buttonStyle(.plain)
                }
            }
            .disabled(!sound.enabled)
            Button("山庄音乐") { stage.sheet = .music }.buttonStyle(.quiet)
        }
        .tint(Theme.ember)
        .foregroundStyle(Theme.text)
    }
}

/// 背景音乐：默认试听、导入自己的音频、去 Apple Music 听原曲。
struct MusicSheet: View {
    @EnvironmentObject private var music: MusicPlayer
    @EnvironmentObject private var sound: SoundEngine
    @Environment(\.openURL) private var openURL
    @State private var importing = false

    var body: some View {
        SheetScaffold(title: "山庄音乐") {
            VStack(alignment: .leading, spacing: 4) {
                Text(music.status).font(Theme.title(20)).foregroundStyle(Theme.text)
                Text(music.filename.isEmpty ? "音源已移除" : music.filename).font(.footnote).foregroundStyle(Theme.dim)
            }
            if !sound.enabled {
                Button("打开全部声音") {
                    sound.enabled = true
                }
                .buttonStyle(.ember)
            }
            Toggle("背景循环", isOn: Binding(get: { music.enabled && music.hasSource }, set: { on in
                if on { music.play() } else { music.pause() }
                sfx(on ? .toggleOn : .toggleOff)
            }))
            .disabled(!music.hasSource)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("音乐音量").foregroundStyle(Theme.text)
                    Spacer()
                    Text("\(Int((music.volume * 100).rounded()))%").foregroundStyle(Theme.dim).monospacedDigit()
                }
                Slider(value: $music.volume, in: 0...1, step: 0.05)
            }
            HStack(spacing: 10) {
                Button(music.playing ? "暂停" : "播放") { music.toggle() }
                    .buttonStyle(.ember)
                    .disabled(!music.hasSource || !sound.enabled)
                Button(music.hasSource ? "换一段音频" : "导入音频") { importing = true }
                    .buttonStyle(.quiet)
            }
            if music.source != .bundled && music.bundledURL != nil {
                Button("恢复默认试听") { music.restoreDefault() }.buttonStyle(.quiet)
            }
            if music.hasSource {
                Button("移除音源") { music.remove() }
                    .buttonStyle(.tap)
                    .font(.subheadline)
                    .foregroundStyle(Theme.rose)
            }
            if !music.message.isEmpty {
                Text(music.message).font(.footnote.weight(.medium)).foregroundStyle(Theme.rose)
            }
            Button {
                openURL(MusicPlayer.officialURL)
            } label: {
                Label("在 Apple Music 听原曲", systemImage: "arrow.up.right")
            }
            .buttonStyle(.tap)
            .font(.subheadline)
            .foregroundStyle(Theme.ember)
        }
        .tint(Theme.ember)
        .foregroundStyle(Theme.text)
        .fileImporter(isPresented: $importing, allowedContentTypes: MusicPlayer.importTypes) { result in
            if case .success(let url) = result { music.importFile(url) }
        }
    }
}

/// 设置与玩法。
struct HelpSheet: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var stage: Stage

    var body: some View {
        SheetScaffold(title: "设置与玩法") {
            VStack(alignment: .leading, spacing: 10) {
                Text("可以借力，决定留给自己。").font(Theme.brush(24)).foregroundStyle(Theme.text)
                rule("checklist", "写下今天的约定，做完后亲手登记。完成得越干脆，经验越多。")
                rule("map", "每整件做完一项，地图上的雾散一点，新的地点和夜谈策略随之开放。")
                rule("moon.stars", "四夜之约：十个人里藏着三个提线人。每做完一件现实里的事，下一夜才会降临；四夜走完，测出你的牌风。")
                rule("scissors", "三张字条里有一张在牵着你走；五席夜谈里有一个人拿了钥匙。")
                rule("hand.raised", "界面会在细节里使坏。亲手拦下，人类含量就不会掉。")
            }
            Divider().overlay(Theme.hairline)
            Picker("木偶怎么说话", selection: Binding(get: { store.sharp }, set: { store.setTone(sharp: $0) })) {
                Text("嘴损一点").tag(true)
                Text("温和一点").tag(false)
            }
            .pickerStyle(.segmented)
            Toggle("让界面使坏", isOn: $store.mischief)
                .onChange(of: store.mischief) { _, on in sfx(on ? .tempt : .toggleOff) }
            if store.mischief { HateList() }
            Toggle("演示：地图全部开门", isOn: $store.unlockAll)
                .onChange(of: store.unlockAll) { _, on in sfx(on ? .unlock : .lock) }
            Divider().overlay(Theme.hairline)
            Button(store.demo ? "退出示例" : "体验示例") {
                if store.demo { store.exitDemo() } else { store.enterDemo() }
                sfx(.open)
                stage.go(.tasks)
            }
            .buttonStyle(.quiet)
            Button("声音与音乐") { stage.sheet = .sound }.buttonStyle(.quiet)
            Button("重看开场") {
                stage.sheet = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { stage.intro = true }
            }
            .buttonStyle(.quiet)
            if !store.storageOK {
                Text("最近一次保存没成功，请到“回声”里导出备份。").font(.footnote.weight(.medium)).foregroundStyle(Theme.rose)
            }
        }
        .tint(Theme.ember)
        .foregroundStyle(Theme.text)
    }

    private func rule(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(Theme.ember).frame(width: 22)
            Text(text).font(.subheadline).foregroundStyle(Theme.text.opacity(0.9)).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// 恨点图鉴：界面会在哪些地方故意让你不爽。
struct HateList: View {
    private static let items: [(String, String, String)] = [
        ("pencil.line", "写待办", "你一停笔，它就替你把话写完。"),
        ("theatermasks", "任务板", "每天第一次来，剧团递上“今日安排”。拒绝要点一行自嘲的小字，叉第一次还会躲开。"),
        ("timer", "开始计时", "假加载冲到 99% 就卡住，旁边递上“先刷会儿再说”。"),
        ("hand.point.up.left", "我做完了", "头两次会躲开你的手指。"),
        ("sparkles", "登记完成", "最显眼的是“一键全部打勾”。"),
        ("person.fill.questionmark", "人类验证", "每天第一次登记要点出所有木偶。第一次选对了也判你没通过。"),
        ("hand.tap", "长按确认", "按到一半，被它打断一次。"),
        ("arrow.left.arrow.right", "撤销", "想点“保留”，它跟“撤销”换了位置。"),
        ("scissors", "剪字条", "替你预选一张错的，8 秒后自己下剪。"),
        ("moon.zzz", "收工", "默认勾好“把没做完的也记成做完”。"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("恨点图鉴").font(.headline).foregroundStyle(Theme.text)
            ForEach(Self.items, id: \.1) { item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: item.0).foregroundStyle(Theme.rose).frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.1).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                        Text(item.2).font(.footnote).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Text("每一次你亲手拦下或被它带走，都会算进人类含量。").font(.footnote).foregroundStyle(Theme.dim)
        }
        .raised()
    }
}
