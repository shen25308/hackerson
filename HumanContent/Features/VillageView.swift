import SwiftUI

/// 首页：一圈可以左右拖动环视的夜巡山庄。地点贴在画里，木偶吊在线上。
struct VillageView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var stage: Stage
    @EnvironmentObject private var music: MusicPlayer

    @State private var yaw = 3.0
    @State private var pitch = 0.0
    @State private var anchor: (yaw: Double, pitch: Double)?
    @State private var selected: String?
    @State private var lastTick = 0
    @State private var suppressTapUntil = Date.distantPast
    @State private var denied = 0
    @State private var nudge = false
    @AppStorage("map.seen") private var seenRaw = "board,theater,fire,tower"
    @AppStorage("hint.look") private var lookHintSeen = false

    private struct Puppet: Identifiable {
        let id: String
        let name: String
        let bearing: Double
        var art: String { "puppet_" + id }
    }

    private let puppets = [
        Puppet(id: "guard", name: "守门人", bearing: 25),
        Puppet(id: "witch", name: "药师", bearing: 44),
        Puppet(id: "grave", name: "寻迹人", bearing: 78),
        Puppet(id: "villager", name: "双生木偶", bearing: 114),
        Puppet(id: "fool", name: "琴师", bearing: 135),
        Puppet(id: "dream", name: "织梦人", bearing: 170),
        Puppet(id: "wolf", name: "灰毛", bearing: -125),
        Puppet(id: "wolfking", name: "戴冠者", bearing: -48),
        Puppet(id: "wolfbeauty", name: "玫瑰夫人", bearing: -28),
    ]

    var body: some View {
        VStack(spacing: 0) {
            hud
            Spacer(minLength: 0)
            bottom
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { scene.ignoresSafeArea(edges: .top) }
        .onAppear {
            #if DEBUG
            if Screenshots.scene == "village-dock" { selected = "fire" }
            if Screenshots.scene == "village-locked", let ferry = Atlas.place("ferry") {
                selected = "ferry"
                yaw = wrap(Atlas.bearing(ferry))
            }
            if Screenshots.scene == "village-puppet" {
                selected = "puppet:guard"
                yaw = 25
            }
            #endif
        }
        .toolbarBackground(Theme.night, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }

    private var scene: some View {
        GeometryReader { geo in
            let size = geo.size
            let sceneHeight = size.height * 1.06
            let sceneWidth = (sceneHeight * 1024 / 644).rounded()
            let ring = sceneWidth * 4
            ZStack(alignment: .topLeading) {
                backdrop(size: size, sceneWidth: sceneWidth, sceneHeight: sceneHeight, ring: ring)
                LinearGradient(colors: [.black.opacity(0.55), .clear, .clear, Theme.night.opacity(0.9)], startPoint: .top, endPoint: .bottom)
                    .allowsHitTesting(false)
                ForEach(puppets) { puppet in
                    puppetView(puppet, size: size, ring: ring)
                }
                ForEach(Atlas.places) { place in
                    placeView(place, size: size, sceneHeight: sceneHeight, ring: ring)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipped()
            .contentShape(Rectangle())
            .simultaneousGesture(look)
            .onTapGesture { clearSelection() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("夜巡山庄全景，左右拖动环视")
    }

    // MARK: 画面

    private func backdrop(size: CGSize, sceneWidth: CGFloat, sceneHeight: CGFloat, ring: CGFloat) -> some View {
        var x = (size.width / 2 - CGFloat((yaw + 222) / 360) * ring).truncatingRemainder(dividingBy: ring)
        if x > 0 { x -= ring }
        return HStack(spacing: 0) {
            ForEach(0..<8, id: \.self) { i in
                Image(Atlas.sceneArt[Atlas.panorama[i % 4]])
                    .resizable()
                    .frame(width: sceneWidth, height: sceneHeight)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .leading)
        .offset(x: x, y: CGFloat(pitch) * 2)
        .accessibilityHidden(true)
    }

    private func wrap(_ a: Double) -> Double {
        var v = (a + 180).truncatingRemainder(dividingBy: 360)
        if v < 0 { v += 360 }
        return v - 180
    }

    /// 方位角换成屏幕上的横坐标；离得太远就不画。
    private func screenX(_ bearing: Double, size: CGSize, ring: CGFloat) -> CGFloat? {
        let angle = wrap(bearing - yaw)
        let x = size.width / 2 + CGFloat(angle / 360) * ring
        return x > -90 && x < size.width + 90 ? x : nil
    }

    @ViewBuilder
    private func placeView(_ place: Place, size: CGSize, sceneHeight: CGFloat, ring: CGFloat) -> some View {
        if let x = screenX(Atlas.bearing(place), size: size, ring: ring) {
            let open = store.isOpen(place.id)
            let y = (size.height - sceneHeight) / 2 + CGFloat(place.y) * sceneHeight + CGFloat(pitch) * 2
            let chosen = selected == place.id
            VStack(spacing: 5) {
                HStack(spacing: 5) {
                    if !open { Image(systemName: "lock.fill").font(.caption2) }
                    Text(place.name).font(Theme.brush(17))
                }
                .foregroundStyle(open ? Theme.ink : Theme.text.opacity(0.85))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(open ? Theme.paper : Theme.raised.opacity(0.92), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay {
                    if chosen { RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(Theme.ember, lineWidth: 2) }
                }
                .shadow(color: .black.opacity(0.5), radius: 5, y: 3)
                if !open {
                    Text("还差 \(place.need - store.gateCount) 项")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Theme.text.opacity(0.8))
                }
            }
            .background {
                if !open {
                    Ellipse().fill(Theme.night.opacity(0.75)).frame(width: 190, height: 120).blur(radius: 26)
                }
            }
            .modifier(Shake(amount: chosen && !open ? CGFloat(denied) : 0))
            .scaleEffect(chosen ? 1.08 : 1)
            .position(x: x, y: y)
            .onTapGesture { pick(place.id, bearing: Atlas.bearing(place)) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(open ? "\(place.name)，\(place.feature)" : "\(place.name)，还差 \(place.need - store.gateCount) 项任务才开门")
            .accessibilityAddTraits(.isButton)
        }
    }

    @ViewBuilder
    private func puppetView(_ puppet: Puppet, size: CGSize, ring: CGFloat) -> some View {
        if let x = screenX(puppet.bearing, size: size, ring: ring) {
            let mine = store.role.art == puppet.art
            let top = size.height * 0.2
            ZStack(alignment: .top) {
                Path { p in
                    p.move(to: CGPoint(x: 30, y: 0))
                    p.addLine(to: CGPoint(x: 38, y: top))
                    p.move(to: CGPoint(x: 66, y: 0))
                    p.addLine(to: CGPoint(x: 58, y: top))
                }
                .stroke(Theme.text.opacity(0.35), lineWidth: 1)
                VStack(spacing: 6) {
                    Image(puppet.art)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 96, height: 104)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .stroke(mine ? Theme.ember : Color.black.opacity(0.7), lineWidth: mine ? 2.5 : 1.5)
                        }
                        .shadow(color: .black.opacity(0.6), radius: 8, y: 5)
                    Text(mine ? "\(puppet.name) · 同行" : puppet.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(mine ? Theme.ember : Theme.paper, in: RoundedRectangle(cornerRadius: 3))
                }
                .padding(.top, top)
            }
            .frame(width: 96, height: top + 140, alignment: .top)
            .position(x: x, y: (top + 140) / 2 + CGFloat(pitch) * 3)
            .onTapGesture { pick("puppet:" + puppet.id, bearing: puppet.bearing) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("木偶\(puppet.name)")
            .accessibilityAddTraits(.isButton)
        }
    }

    // MARK: 环视

    private var look: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                if anchor == nil {
                    anchor = (yaw, pitch)
                    if selected != nil { selected = nil }
                    if !lookHintSeen { lookHintSeen = true }
                }
                guard let start = anchor else { return }
                yaw = wrap(start.yaw - Double(value.translation.width) * 0.14)
                pitch = max(-10, min(10, start.pitch + Double(value.translation.height) * 0.05))
                let tick = Int((yaw / 12).rounded(.down))
                if tick != lastTick {
                    lastTick = tick
                    sfx(.tick, strength: 0.5)
                }
            }
            .onEnded { value in
                guard let start = anchor else { return }
                anchor = nil
                suppressTapUntil = Date().addingTimeInterval(0.35)
                // 松手后顺着惯性再转一点。
                let coast = Double(value.predictedEndTranslation.width - value.translation.width) * 0.14
                withAnimation(.easeOut(duration: 0.5)) {
                    yaw = wrap(start.yaw - Double(value.translation.width) * 0.14 - max(-40, min(40, coast)))
                    pitch = 0
                }
            }
    }

    private func pick(_ id: String, bearing: Double) {
        guard Date() > suppressTapUntil else { return }
        selected = id
        withAnimation(.easeInOut(duration: 0.35)) { yaw = wrap(bearing) }
        sfx(.scan, strength: 0.7)
    }

    private func clearSelection() {
        guard selected != nil, Date() > suppressTapUntil else { return }
        selected = nil
        sfx(.close, strength: 0.5)
    }

    // MARK: 顶部

    private var hud: some View {
        let content = Rules.humanContent(store.s)
        return VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Button {
                    stage.go(.puppets)
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(store.role.name).font(Theme.title(19)).foregroundStyle(Theme.text)
                            Text("Lv.\(store.level)").font(.caption.weight(.semibold)).foregroundStyle(Theme.ember)
                        }
                        Meter(value: Double(store.hp) / 100, color: Theme.rose, height: 5).frame(width: 128)
                        Text("生命 \(store.hp) · 经验 \(store.xp)").font(.caption2).foregroundStyle(Theme.text.opacity(0.75))
                    }
                    .fixedSize()
                }
                .buttonStyle(.tap)
                .layoutPriority(1)
                Spacer(minLength: 4)
                Button {
                    stage.go(.echo)
                } label: {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(content.percent)%").font(Theme.title(19)).foregroundStyle(content.percent >= 60 ? Theme.text : Theme.rose)
                        Text("人类含量").font(.caption2).foregroundStyle(Theme.text.opacity(0.75))
                    }
                }
                .buttonStyle(.tap)
                .accessibilityLabel("人类含量百分之\(content.percent)")
                roundButton("speaker.wave.2.fill", label: "声音") { stage.sheet = .sound }
                roundButton("gearshape.fill", label: "设置与说明") { stage.sheet = .help }
            }
            if store.demo {
                HStack {
                    Text("示例中，不写入你的档案").font(.footnote)
                    Button("退出") {
                        store.exitDemo()
                        sfx(.close)
                    }
                    .font(.footnote.weight(.semibold))
                }
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Theme.ember, in: Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    private func roundButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.text)
                .frame(width: 38, height: 38)
                .background(Theme.night.opacity(0.6), in: Circle())
        }
        .buttonStyle(.tap(.open))
        .accessibilityLabel(label)
    }

    // MARK: 底部

    @ViewBuilder
    private var bottom: some View {
        if let selected, let info = describe(selected) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(info.title).font(Theme.brush(24)).foregroundStyle(Theme.text)
                    Spacer()
                    Text(info.hint).font(.caption).foregroundStyle(Theme.dim)
                }
                Text(info.text).font(.subheadline).foregroundStyle(Theme.text.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
                Button(info.button) { enter(selected) }
                    .buttonStyle(.ember)
            }
            .padding(16)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.5), radius: 16, y: 6)
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else {
            VStack(spacing: 10) {
                if !lookHintSeen {
                    Label("左右拖动，环视山庄", systemImage: "hand.draw")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Theme.night.opacity(0.7), in: Capsule())
                        .offset(x: nudge ? 14 : -14)
                        .onAppear {
                            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { nudge = true }
                        }
                        .padding(.bottom, 6)
                }
                Text("人类含量").font(Theme.brush(34)).foregroundStyle(Theme.text).shadow(color: .black, radius: 8)
                leadButton
                HStack(spacing: 8) {
                    chip("map", "地图") { stage.sheet = .map }
                    chip("theatermasks", "剧场") { stage.sheet = .labMenu }
                    chip(music.playing ? "pause.fill" : "music.note", "音乐") { stage.sheet = .music }
                    chip("moon.zzz", store.closed ? "今日记录" : "收工") {
                        if store.closed { stage.go(.echo) } else { stage.openSettle() }
                    }
                }
            }
            .padding(.bottom, 12)
        }
    }

    // MARK: 引路

    private struct Lead {
        let text: String
        let symbol: String
        let action: () -> Void
    }

    /// 眼下最值得做的一件事。
    private var lead: Lead {
        let seen = Set(seenRaw.split(separator: ",").map(String.init))
        let fresh = Atlas.places.filter { store.isOpen($0.id) && !seen.contains($0.id) }.max { $0.need < $1.need }
        if let fresh, !store.unlockAll {
            return Lead(text: "\(fresh.name)的雾散了，去地图看看", symbol: "map") { stage.sheet = .map }
        }
        if store.closed {
            return Lead(text: "今天已收工，翻翻今天的回声", symbol: "waveform") { stage.go(.echo) }
        }
        if store.today.tasks.isEmpty {
            return Lead(text: "先去任务板，写下今天的一件事", symbol: "pencil.line") {
                stage.go(.tasks)
                stage.wantsAdd = true
            }
        }
        if let next = store.today.tasks.first(where: { !$0.done }) {
            return Lead(text: "下一步：\(next.title)", symbol: "figure.walk") { stage.openTask(next.id) }
        }
        return Lead(text: "今天的事都登记了，可以收工", symbol: "moon.zzz") { stage.openSettle() }
    }

    private var leadButton: some View {
        let next = self.lead
        return Button {
            sfx(.open)
            next.action()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: next.symbol).font(.footnote.weight(.semibold))
                Text(next.text).font(.subheadline.weight(.medium)).lineLimit(1)
                Image(systemName: "chevron.right").font(.caption2.weight(.bold))
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 14)
            .frame(minHeight: 38)
            .background(Theme.ember, in: Capsule())
            .shadow(color: .black.opacity(0.5), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 18)
    }

    private func chip(_ symbol: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.footnote)
                Text(title).font(.footnote.weight(.medium))
            }
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 12)
            .frame(minHeight: 38)
            .background(Theme.night.opacity(0.78), in: Capsule())
            .overlay { Capsule().stroke(Theme.text.opacity(0.18), lineWidth: 1) }
        }
        .buttonStyle(.tap(.open))
    }

    private struct Info {
        var title: String
        var hint: String
        var text: String
        var button: String
    }

    private func describe(_ id: String) -> Info? {
        if id.hasPrefix("puppet:") {
            let key = String(id.dropFirst(7))
            guard let puppet = puppets.first(where: { $0.id == key }) else { return nil }
            return Info(title: puppet.name, hint: "山庄里的木偶", text: "你现在与\(store.role.name)同行。换谁、有哪些牌，都在木偶工坊。", button: "去木偶工坊")
        }
        guard let place = Atlas.place(id) else { return nil }
        if !store.isOpen(id) {
            let left = place.need - store.gateCount
            return Info(title: place.name, hint: "雾还没散", text: "\(place.feature)。再整件做完 \(left) 项任务，这里开门。", button: "去任务板拿钥匙")
        }
        let text: String
        let button: String
        switch id {
        case "board":
            text = store.closed ? "今天已经收工，记录还在。" : store.today.tasks.isEmpty ? "先写下一件今天能做完的事。" : "今天还有 \(store.pending) 项待办。"
            button = "看今日待办"
        case "theater":
            text = "抢写、追着你跑的按钮、换位的选项。亲手试一次界面怎么抢走你的决定。"
            button = "进剧场"
        case "backstage":
            text = "后三幕：像素、反驳、第 N 次。"
            button = "去后台"
        case "fire":
            text = "三张字条和五席夜谈都在这里。夜谈现在能用到第 \(store.strategyTier + 1) 手。"
            button = "坐到火堆旁"
        case "tower":
            text = "已经整件做完 \(store.completed) 项。回看任务、选票和用时。"
            button = "翻开行为回声"
        case "decisions":
            text = "回看你采用过的策略和投过的票。"
            button = "上观星台"
        case "mirror":
            text = "把现实里的行动和桌上的决定并排放。"
            button = "走进回声廊"
        case "ferry":
            text = "建一个房间邀朋友，或输入六位房间码入座。"
            button = "去渡口"
        default:
            text = "写下一个假设，下次留下可以核对的记录。"
            button = "到镜湖边"
        }
        return Info(title: place.name, hint: place.feature, text: text, button: button)
    }

    private func enter(_ id: String) {
        if id.hasPrefix("puppet:") {
            selected = nil
            stage.go(.puppets)
            return
        }
        guard store.isOpen(id) else {
            sfx(.lock)
            withAnimation(.default) { denied += 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                selected = nil
                stage.go(.tasks)
            }
            return
        }
        selected = nil
        sfx(.open)
        stage.enter(id)
    }
}

/// 左右晃几下，用在“门没开”的时候。
struct Shake: GeometryEffect {
    var amount: CGFloat
    var animatableData: CGFloat {
        get { amount }
        set { amount = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 7 * sin(amount * .pi * 4), y: 0))
    }
}
