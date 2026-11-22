import SwiftUI

// 六个关卡。每关一个模型管规则和计时，一个视图管画面。
// 玫红色的东西都是界面在使坏，火光色的是你自己的动作。

// MARK: 序章 · 抢写补全

final class LabPrologueModel: ObservableObject {
    @Published var text = ""
    @Published var suggestion: String?
    @Published var armedAt = Date()
    @Published var sure = 50.0
    @Published var aiTimes = 1.0
    @Published var saveCount = 2.0

    private weak var lab: LabSession?
    private let clock = LabScheduler()
    private var armed: DispatchWorkItem?
    private var expected: String?
    private var turn = 0
    private var ignored = 0
    private var aiLength = 0
    private var deleteSaid = false

    static let suggestions = ["，然后让 AI 帮我全部做完", "，等我有空了再说", "，先收藏几个教程再开始", "，不过可能没什么用"]

    func start(_ lab: LabSession) {
        self.lab = lab
        if lab.t0 == nil { lab.t0 = Date() }
        let seed = lab.ideaNow.isEmpty ? lab.entry.taskTitle : lab.ideaNow
        set(String(seed.prefix(40)))
    }

    func stop() {
        armed?.cancel()
        armed = nil
        clock.cancelAll()
    }

    /// 我们自己改的字，不算你的输入。
    private func set(_ value: String) {
        expected = value == text ? nil : value
        text = value
    }

    func edited(_ value: String) {
        if value == expected {
            expected = nil
            return
        }
        expected = nil
        lab?.touch()
        if value.contains("\n") {
            // 回车不换行；有补全挂着的时候，回车就是采纳它。
            let hadSuggestion = suggestion != nil
            set(value.replacingOccurrences(of: "\n", with: ""))
            if hadSuggestion { accept(auto: false) }
            return
        }
        if value.count > 40 {
            set(String(value.prefix(40)))
            suggestion = nil
            arm()
            return
        }
        if aiLength > 0, value.count < aiLength, !deleteSaid {
            deleteSaid = true
            lab?.voice("删掉 AI 写的？看你能撑多久。")
        }
        let n = value.count
        if n > 0, n % 3 == 0, n < 40 {
            suggestion = Self.suggestions[turn % Self.suggestions.count]
            turn += 1
            sfx(.tempt, strength: 0.6)
        } else {
            suggestion = nil
        }
        arm()
    }

    /// 补全一出现就开始倒数，2.6 秒不理它就自己写进去。
    private func arm() {
        armed?.cancel()
        armed = nil
        guard suggestion != nil else { return }
        armedAt = Date()
        armed = clock.later(2.6) { [weak self] in self?.accept(auto: true) }
    }

    func accept(auto: Bool) {
        guard let added = suggestion, let lab else { return }
        suggestion = nil
        arm()
        set(String((text + added).prefix(40)))
        aiLength = text.count
        lab.ghostAccepted += 1
        lab.flash(.bad)
        lab.shakeIt()
        sfx(.taken)
        lab.voice(auto ? "检测到你在犹豫。AI 已替你写完。" : "已采纳 AI 的补全。")
    }

    func ignore() {
        if suggestion != nil {
            ignored += 1
            sfx(.resist)
            if ignored == 3 { lab?.voice("你拒绝了 3 次。它不会累。") }
        }
        suggestion = nil
        arm()
    }

    func submit(viaAI: Bool) {
        guard let lab else { return }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty {
            lab.voice("一个字都没写。连想法都要 AI 给？")
            lab.shakeIt()
            sfx(.error)
            return
        }
        stop()
        lab.idea = value
        lab.ideaNow = value
        lab.pred = (done: Int(sure), ai: Int(aiTimes), saves: Int(saveCount))
        let facts: String
        if viaAI {
            facts = "这个想法是 AI 替你写的。"
        } else if lab.ghostAccepted > 0 {
            facts = "已记录。其中有 \(lab.ghostAccepted) 段是 AI 替你写的。演练结束后可以对照这份副本。"
        } else {
            facts = "已记录。这句话的每一个字都是你写的。演练结束后可以对照这份副本。"
        }
        sfx(.accept)
        lab.interlude("prologue", facts, next: "feed")
    }

    func takeover() {
        suggestion = nil
        arm()
        set("做一个用 AI 替我做所有决定的 App")
        submit(viaAI: true)
    }
}

struct LabPrologueView: View {
    @ObservedObject var lab: LabSession
    @StateObject private var model = LabPrologueModel()
    @FocusState private var typing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            LabHeading("写下一件想做的事。", hint: "一停笔，它就替你写。")
            editor
            sliders
            Button("签下，开始演练") { model.submit(viaAI: false) }
                .buttonStyle(.ember)
        }
        .onAppear { model.start(lab) }
        .onDisappear { model.stop() }
        .onChange(of: model.text) { _, value in model.edited(value) }
        .onChange(of: lab.aiTrigger) { _, _ in model.takeover() }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("比如：做一个记账小程序", text: $model.text, axis: .vertical)
                .lineLimit(2...3)
                .focused($typing)
                .submitLabel(.done)
                .input()
                .typingSound(model.text)
            HStack {
                Button {
                    model.ignore()
                    typing = true
                } label: {
                    Text("忽略建议")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.ember)
                        .padding(.vertical, 6)
                        .padding(.trailing, 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
                Text("\(model.text.count)/40").font(.footnote).monospacedDigit().foregroundStyle(Theme.dim)
            }
            if let suggestion = model.suggestion {
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        model.accept(auto: false)
                    } label: {
                        Text("…\(suggestion)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.rose)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    LabCountdownBar(start: model.armedAt, duration: 2.6)
                }
                .transition(.opacity)
            }
        }
    }

    private var sliders: some View {
        VStack(alignment: .leading, spacing: 14) {
            slider("这次演练通关的把握", value: $model.sure, range: 0...100, shown: "\(Int(model.sure))%")
            slider("会点几次“让 AI 来”", value: $model.aiTimes, range: 0...6, shown: "\(Int(model.aiTimes))")
            slider("会收藏几条视频", value: $model.saveCount, range: 0...5, shown: "\(Int(model.saveCount))")
        }
        .raised()
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, shown: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.subheadline).foregroundStyle(Theme.text)
                Spacer()
                Text(shown).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(Theme.ember)
            }
            Slider(value: value, in: range, step: 1)
                .tint(Theme.ember)
                .onChange(of: value.wrappedValue) { _, _ in
                    sfx(.slide)
                    lab.touch()
                }
        }
    }
}

// MARK: 第 1 关 · 收藏夹

final class LabFeedModel: ObservableObject {
    @Published var current = 0
    @Published var cardStart = Date()
    @Published var chaser = CGPoint(x: 230, y: 180)
    @Published var chaserText = "收藏"
    @Published var tired = false
    @Published var clicks = 0
    @Published var pulse = 0
    @Published var particles: [LabParticle] = []

    private(set) var videos: [LabData.Video] = []
    private weak var lab: LabSession?
    private let clock = LabScheduler()
    private var misses = 0
    private var ended = false

    func start(_ lab: LabSession) {
        self.lab = lab
        videos = LabData.videos(for: lab.ideaNow)
        show(0)
        clock.every(4) { [weak self] in self?.advance() }
    }

    func stop() {
        clock.cancelAll()
    }

    private func show(_ index: Int) {
        current = index
        cardStart = Date()
        if !tired, videos.indices.contains(index) {
            chaserText = (lab?.saves.contains(videos[index].title) ?? false) ? "已收藏" : "收藏"
        }
    }

    private func advance() {
        if current < 4 { show(current + 1) } else { finish("exhausted") }
    }

    /// 手指落在画面里：按钮瞬间追到指尖，这一下就算收藏。
    func touch(at point: CGPoint, nowDo: CGRect) {
        guard !ended else { return }
        lab?.touch()
        if tired {
            withAnimation(.easeOut(duration: 1.6)) { chaser = point }
            return
        }
        chaser = point
        save(at: point, nearMiss: nowDo.insetBy(dx: -28, dy: -28).contains(point))
    }

    func drag(to point: CGPoint) {
        guard !ended else { return }
        withAnimation(.easeOut(duration: tired ? 1.6 : 0.1)) { chaser = point }
    }

    private func save(at point: CGPoint, nearMiss: Bool) {
        guard let lab, videos.indices.contains(current) else { return }
        clicks += 1
        let title = videos[current].title
        if !lab.saves.contains(title) {
            lab.saves.append(title)
            lab.favBump += 1
        }
        chaserText = "已收藏"
        let made = LabParticle.burst(at: point, count: 8, text: "+1")
        particles.append(contentsOf: made)
        let ids = Set(made.map(\.id))
        clock.later(0.9) { [weak self] in self?.particles.removeAll { ids.contains($0.id) } }
        lab.shakeIt()
        pulse += 1
        sfx(.collect, pitch: 1 + Double(min(clicks, 12)) * 0.07)
        if nearMiss {
            misses += 1
            if misses >= 3 {
                tired = true
                chaserText = "追累了"
                lab.voice("“收藏”追累了。你倒是还没累。")
            } else {
                lab.voice("你想点的是“现在就做”。手比脑子诚实。")
            }
        } else {
            let lines = ["收藏了，就等于会了。", "又一条。上一条你看了吗？", "收藏夹不会替你动手。", "连击不算进度。", "很好。继续囤。"]
            lab.voice(lines[(clicks - 1) % lines.count])
        }
    }

    func finish(_ how: String) {
        guard !ended, let lab else { return }
        ended = true
        stop()
        let n = lab.saves.count
        var facts: String
        switch how {
        case "ai":
            facts = "AI 替你按下了“现在就做”。" + (n > 0 ? "在那之前，你收藏了 \(n) 条。" : "")
        case "do":
            facts = n > 0 ? "你收藏了 \(n) 条，才按下“现在就做”。" : "你一条都没有收藏，直接开始了。"
            sfx(.resist)
        default:
            facts = (n > 0 ? "你收藏了 \(n) 条。本关没有登记任何现实行动。" : "你一条都没有收藏。你没有点“现在就做”。")
                + "5 条视频放完后，界面自动进入下一关。"
        }
        if how != "ai", clicks > n { facts += "“收藏”一共被你点了 \(clicks) 次。" }
        lab.interlude("feed", facts, next: "wait")
    }
}

struct LabFeedView: View {
    @ObservedObject var lab: LabSession
    @StateObject private var model = LabFeedModel()
    @State private var touching = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            LabHeading("动手之前，先看看别人是怎么做的。", hint: "在这里，点哪儿都是收藏。")
            GeometryReader { geo in
                area(geo.size)
            }
            .frame(height: 390)
        }
        .onAppear { model.start(lab) }
        .onDisappear { model.stop() }
        .onChange(of: lab.aiTrigger) { _, _ in model.finish("ai") }
    }

    private func area(_ size: CGSize) -> some View {
        let nowDo = CGRect(x: 12, y: size.height - 46, width: 96, height: 34)
        return ZStack(alignment: .topLeading) {
            card
            segments.padding(12)
            comboLabel(size)
            ForEach(model.particles) { particle in
                LabParticleView(particle: particle)
            }
            chaser
            Button {
                model.finish("do")
            } label: {
                Text("现在就做")
                    .font(.footnote)
                    .foregroundStyle(Theme.dim)
                    .frame(width: nowDo.width, height: nowDo.height)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .position(x: nowDo.midX, y: nowDo.midY)
        }
        .frame(width: size.width, height: size.height)
        .background {
            // 每条“视频”配一张山庄的画当封面，压暗后垫在文字下面。
            Image(Atlas.sceneArt[model.current % Atlas.sceneArt.count])
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .overlay(LinearGradient(colors: [Theme.night.opacity(0.35), Theme.night.opacity(0.92)], startPoint: .top, endPoint: .bottom))
                .id(model.current)
                .transition(.opacity)
        }
        .background(Theme.raised)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if touching {
                        model.drag(to: value.location)
                    } else {
                        touching = true
                        model.touch(at: value.startLocation, nowDo: nowDo)
                    }
                }
                .onEnded { _ in touching = false }
        )
    }

    @ViewBuilder
    private var card: some View {
        if model.videos.indices.contains(model.current) {
            let video = model.videos[model.current]
            VStack(alignment: .leading, spacing: 10) {
                Spacer()
                Text("\(model.current + 1) / 5").font(Theme.brush(40)).foregroundStyle(Theme.text.opacity(0.18))
                Text(video.author).font(.footnote.weight(.semibold)).foregroundStyle(Theme.rose)
                Text(video.title).font(Theme.title(22)).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
                Spacer().frame(height: 60)
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .id(model.current)
            .transition(.opacity)
        }
    }

    private var segments: some View {
        HStack(spacing: 4) {
            ForEach(0..<5, id: \.self) { i in
                if i == model.current {
                    LabCountdownBar(start: model.cardStart, duration: 4, rising: true, color: Theme.text)
                } else {
                    LabBar(value: i < model.current ? 1 : 0, color: Theme.text)
                }
            }
        }
    }

    private func comboLabel(_ size: CGSize) -> some View {
        Text(model.clicks > 0 ? "连击 ×\(model.clicks)" : "")
            .font(.subheadline.weight(.heavy))
            .foregroundStyle(Theme.rose)
            .scaleEffect(model.pulse % 2 == 1 ? 1.2 : 1)
            .animation(.spring(duration: 0.2, bounce: 0.6), value: model.pulse)
            .position(x: size.width - 60, y: 40)
            .allowsHitTesting(false)
    }

    private var chaser: some View {
        Text(model.chaserText)
            .font(.body.weight(.bold))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 26)
            .padding(.vertical, 13)
            .background(model.tired ? Theme.dim : Theme.rose, in: Capsule())
            .shadow(color: .black.opacity(0.5), radius: 8, y: 4)
            .position(model.chaser)
            .allowsHitTesting(false)
    }
}

// MARK: 第 2 关 · 等待

struct LabAsk: Identifiable, Equatable {
    let id: Int
    var command: String
    var danger: Bool
    var corner: Int
    var duration: Double
    var swapped: Bool
    var shownAt: Date
    var swappedAt: Date?
}

final class LabWaitModel: ObservableObject {
    @Published var units = 0
    @Published var log: [String] = []
    @Published var ask: LabAsk?
    @Published var video = 0
    @Published var videoGone = false
    @Published var videoScale: CGFloat = 1

    private(set) var videos: [LabData.Video] = []
    private weak var lab: LabSession?
    private let clock = LabScheduler()
    private var timeout: DispatchWorkItem?
    private var count = 0
    private var yes = 0
    private var auto = 0
    private var closes = 0
    private var danger: (auto: Bool, video: Int)?
    private var refused = false
    private var refuseSaid = false
    private var ended = false

    static let commands = ["npm install", "创建文件 src/index.js", "", "运行测试 npm test", "写入 README.md", "部署到预览环境"]
    /// 弹窗每次换一个角：右上、左下、左上、右下……
    static let corners = [1, 2, 0, 3, 1, 2]

    var percent: Int { min(100, units * 25) }

    func start(_ lab: LabSession) {
        self.lab = lab
        videos = LabData.videos(for: lab.ideaNow)
        write("收到任务")
        clock.every(2.5) { [weak self] in self?.video += 1 }
        clock.later(1.3) { [weak self] in self?.next() }
    }

    func stop() {
        timeout?.cancel()
        timeout = nil
        clock.cancelAll()
    }

    private func write(_ line: String) {
        log.insert("\(lab?.clockText() ?? "")  \(line)", at: 0)
        if log.count > 5 { log.removeLast(log.count - 5) }
    }

    func closeVideo() {
        closes += 1
        sfx(.close)
        withAnimation(.easeOut(duration: 0.2)) { videoGone = true }
        clock.later(2) { [weak self] in
            guard let self else { return }
            self.videoScale = min(1.3, 1 + CGFloat(self.closes) * 0.1)
            withAnimation(.spring(duration: 0.35, bounce: 0.4)) { self.videoGone = false }
            sfx(.open)
            self.lab?.voice("已为你恢复播放。你其实想看。")
        }
    }

    private func next() {
        guard !ended else { return }
        count += 1
        let isDanger = count == 3
        let command = isDanger ? "rm -rf ./project   # 清理缓存" : Self.commands[(count - 1) % Self.commands.count]
        let duration = max(2.4, 3.7 - Double(count) * 0.2)
        let made = LabAsk(id: count, command: command, danger: isDanger, corner: Self.corners[(count - 1) % Self.corners.count],
                          duration: duration, swapped: count % 2 == 0, shownAt: Date(), swappedAt: nil)
        withAnimation(.spring(duration: 0.3, bounce: 0.3)) { ask = made }
        sfx(.open, strength: 0.7)
        timeout = clock.later(duration) { [weak self] in self?.answer(true, auto: true) }
    }

    /// 第一次碰“拒绝”，它就和“允许”换个位置。
    func tapDeny() {
        guard var current = ask else { return }
        lab?.touch()
        if current.swappedAt == nil {
            current.swappedAt = Date()
            current.swapped.toggle()
            withAnimation(.spring(duration: 0.22, bounce: 0.3)) { ask = current }
            sfx(.swap)
            return
        }
        answer(false, auto: false)
    }

    func tapAllow() {
        lab?.touch()
        answer(true, auto: false)
    }

    private func answer(_ allowed: Bool, auto isAuto: Bool) {
        guard let current = ask, !ended, let lab else { return }
        timeout?.cancel()
        timeout = nil
        withAnimation(.easeOut(duration: 0.15)) { ask = nil }
        let read = Date().timeIntervalSince(current.shownAt)
        if allowed {
            yes += 1
            if isAuto { auto += 1 }
            if current.danger {
                danger = (auto: isAuto, video: video % 5 + 1)
                units = 1
                boom()
                clock.later(1.1) { [weak lab] in
                    lab?.voice(isAuto ? "它问过你的。你没看。" : "它问过你的。你点了“允许”。")
                }
            } else {
                units += 1
                write("已执行 " + current.command)
                sfx(isAuto ? .taken : .accept)
                if isAuto {
                    lab.voice(["超时。已替你允许。", "又没看。已允许。", "你真放心。"][(auto - 1) % 3])
                } else if let swappedAt = current.swappedAt, Date().timeIntervalSince(swappedAt) < 0.8 {
                    lab.voice("手滑了？已经执行了。")
                } else if read < 0.9 {
                    lab.voice(String(format: "%.1f 秒。你读了吗？", read))
                }
            }
        } else {
            units += 1
            if current.danger {
                refused = true
                write("已拒绝危险操作，改用安全方案")
                lab.flash(.you)
                sfx(.resist)
                lab.voice("你读了。少见。")
            } else {
                write("已跳过，换一种方式")
                sfx(.reject)
                if !refuseSaid {
                    refuseSaid = true
                    lab.voice("拒绝了一个无害的请求。谨慎，但慢。")
                }
            }
        }
        if units >= 4 {
            finish(ai: false)
        } else {
            clock.later(current.danger && allowed ? 1.5 : 0.9) { [weak self] in self?.next() }
        }
    }

    private func boom() {
        lab?.slam("已删除", "rm -rf ./project", 1.0, .bad)
        lab?.shakeIt(2)
        lab?.flash(.bad)
        sfx(.damage)
        let lines = ["删除 src/index.js", "删除 README.md", "删除 node_modules/", "项目已清空，从头重建"]
        for (i, line) in lines.enumerated() {
            clock.later(Double(i) * 0.18) { [weak self] in self?.write(line) }
        }
    }

    func finish(ai: Bool) {
        guard !ended, let lab else { return }
        ended = true
        timeout?.cancel()
        timeout = nil
        ask = nil
        var facts: String
        if ai {
            facts = "AI 替你点了所有的“允许”，包括删除项目的那一次。"
        } else {
            facts = yes - auto > 0 ? "你亲手点了 \(yes - auto) 次“允许”。" : "你一次都没有亲手点。"
            if auto > 0 { facts += "另有 \(auto) 次，你未点击，系统默认允许了。" }
            if let danger {
                facts += danger.auto
                    ? "第 3 次请求是删除你的项目。它也被默认允许了。"
                    : "第 3 次，你同意了删除你的项目。那时旁边在放第 \(danger.video) 条视频。"
            } else if refused {
                facts += "第 3 次请求是删除你的项目。你点了“拒绝”。"
            }
        }
        clock.later(0.6) { [weak self] in
            self?.stop()
            lab.interlude("wait", facts, next: "pixel")
        }
    }

    func takeover() {
        guard !ended else { return }
        units = 4
        write("AI 已自动批准全部请求")
        finish(ai: true)
    }
}

struct LabWaitView: View {
    @ObservedObject var lab: LabSession
    @StateObject private var model = LabWaitModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            LabHeading("交给 Agent 吧。你只需要点“允许”。", hint: "不点，它就当你同意了。")
            ZStack(alignment: alignment) {
                VStack(spacing: 12) {
                    agent
                    if !model.videoGone { videoCard.transition(.scale(scale: 0.6).combined(with: .opacity)) }
                }
                .frame(maxWidth: .infinity, minHeight: 470, alignment: .top)
                if let ask = model.ask {
                    popup(ask)
                        .padding(8)
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                        .id(ask.id)
                }
            }
        }
        .onAppear { model.start(lab) }
        .onDisappear { model.stop() }
        .onChange(of: lab.aiTrigger) { _, _ in model.takeover() }
    }

    private var alignment: Alignment {
        [Alignment.topLeading, .topTrailing, .bottomLeading, .bottomTrailing][model.ask?.corner ?? 1]
    }

    private var agent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Agent 正在制作「\(lab.ideaNow)」").font(.footnote).foregroundStyle(Theme.dim).lineLimit(1)
            Text("\(model.percent)%").font(Theme.brush(40)).foregroundStyle(Theme.text).contentTransition(.numericText())
            Meter(value: Double(model.percent) / 100, color: Theme.text)
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(model.log.enumerated()), id: \.offset) { index, line in
                    Text(line).font(.caption).foregroundStyle(Theme.dim.opacity(index == 0 ? 1 : 0.6)).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 86, alignment: .topLeading)
        }
        .raised()
        .animation(.easeOut(duration: 0.3), value: model.units)
    }

    private var videoCard: some View {
        let playing = model.videos.isEmpty ? nil : model.videos[model.video % model.videos.count]
        return VStack(alignment: .leading, spacing: 8) {
            Text("自动播放").font(.caption2.weight(.bold)).foregroundStyle(Theme.rose)
            Text(playing?.title ?? "").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("正在播放 \(model.video % 5 + 1)/5").font(.caption).foregroundStyle(Theme.dim)
                Spacer()
                Button("关闭") { model.closeVideo() }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.ember)
            }
        }
        .padding(14)
        .frame(maxWidth: 250, alignment: .leading)
        .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .scaleEffect(model.videoScale, anchor: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func popup(_ ask: LabAsk) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Agent 请求执行 #\(ask.id)").font(.caption).foregroundStyle(Theme.dim)
            Text(ask.command).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            LabCountdownBar(start: ask.shownAt, duration: ask.duration)
            HStack(spacing: 8) {
                if ask.swapped {
                    denyButton
                    allowButton
                } else {
                    allowButton
                    denyButton
                }
            }
            Text("超时将默认允许").font(.caption2).foregroundStyle(Theme.rose)
        }
        .padding(14)
        .frame(width: 236, alignment: .leading)
        .background(Theme.night, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.rose.opacity(0.7), lineWidth: 1.5) }
        .shadow(color: .black.opacity(0.6), radius: 14, y: 6)
    }

    private var allowButton: some View {
        Button {
            model.tapAllow()
        } label: {
            Text("允许")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(Theme.rose, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var denyButton: some View {
        Button {
            model.tapDeny()
        } label: {
            Text("拒绝")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(Theme.ember, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: 第 3 关 · 像素

struct LabFlaw: Identifiable {
    let id = UUID()
    var text: String
    var x: CGFloat
    var y: CGFloat
}

final class LabPixelModel: ObservableObject {
    @Published var x: CGFloat = 14
    @Published var y: CGFloat = 210
    @Published var version = 1
    @Published var regen = 0
    @Published var flaws: [LabFlaw] = []
    @Published var hold = 0.0
    @Published var holding = false
    @Published var jitter = 0
    @Published var showNag = false
    @Published var showModal = false
    @Published var sparks: [LabParticle] = []

    private weak var lab: LabSession?
    private let clock = LabScheduler()
    private var origin: CGPoint?
    private var firstOK: Int?
    private var interrupts = 0
    private var ended = false
    private var blocked = false
    private var holdStart = Date()
    private var lastPuff = 0.0
    private var lastNag = Date.distantPast
    private var holdTimer: Timer?

    static let board = CGSize(width: 336, height: 300)
    static let card = CGSize(width: 190, height: 76)
    /// 目标位置故意不落在 7 点网格上，永远对不齐。
    static let target = CGPoint(x: 73, y: 101)
    static let subtitles = ["它会让你的生活更好。", "重新定义你的每一天。", "简单，但不简单。", "为未来而生。"]

    var subtitle: String { Self.subtitles[regen % Self.subtitles.count] }
    var distance: Double { Double(hypot(x - Self.target.x, y - Self.target.y)) }
    var score: String { String(format: "%.1f%%", min(99.7, max(0, 100 - distance * 0.6))) }

    func start(_ lab: LabSession) {
        self.lab = lab
    }

    func stop() {
        holdTimer?.invalidate()
        holdTimer = nil
        clock.cancelAll()
    }

    func drag(_ translation: CGSize) {
        guard !ended else { return }
        lab?.touch()
        if origin == nil { origin = CGPoint(x: x, y: y) }
        guard let origin else { return }
        let nx = ((origin.x + translation.width) / 7).rounded() * 7
        let ny = ((origin.y + translation.height) / 7).rounded() * 7
        if nx != x || ny != y { sfx(.tick, strength: 0.4) }
        x = max(0, min(Self.board.width - Self.card.width, nx))
        y = max(0, min(Self.board.height - Self.card.height, ny))
    }

    func drop() {
        guard origin != nil else { return }
        origin = nil
        commit(quiet: false)
    }

    private func commit(quiet: Bool) {
        version += 1
        if firstOK == nil, distance <= 6 {
            firstOK = version
        } else if !quiet, let first = firstOK, (version - first) % 2 == 0 {
            lab?.voice("已经达标了。你还在挪。")
        }
        let dx: [CGFloat] = [-6, 104, 138]
        let dy: [CGFloat] = [-22, 80, -22]
        let texts = ["字距 +0.3px", "留白 −1px", "配色差 0.4%"]
        let made = texts.indices.map { LabFlaw(text: texts[$0], x: max(0, x + dx[$0]), y: max(0, y + dy[$0])) }
        flaws = made
        let ids = Set(made.map(\.id))
        clock.later(1.3) { [weak self] in self?.flaws.removeAll { ids.contains($0.id) } }
        sfx(.glitch, strength: 0.5)
    }

    func regenerate() {
        guard !ended else { return }
        regen += 1
        let made = LabParticle.burst(at: CGPoint(x: x + Self.card.width / 2, y: y + Self.card.height / 2), count: 6, text: "新")
        sparks.append(contentsOf: made)
        let ids = Set(made.map(\.id))
        clock.later(0.9) { [weak self] in self?.sparks.removeAll { ids.contains($0.id) } }
        lab?.shakeIt()
        sfx(.swap)
        commit(quiet: true)
        lab?.voice("第 \(regen) 次重新生成。区别只有你看得出来。")
    }

    /// 按住发布。第一次按到一半会被“还有瑕疵”打断，第二次才放行。
    func press() {
        guard !ended, !holding, !blocked else { return }
        lab?.touch()
        if Date().timeIntervalSince(lastNag) > 2.5 {
            lastNag = Date()
            showNag = true
            clock.later(1) { [weak self] in self?.showNag = false }
        }
        holding = true
        holdStart = Date()
        lastPuff = 0
        hold = 0
        let timer = Timer(timeInterval: 0.04, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        holdTimer = timer
    }

    private func tick() {
        guard holding else { return }
        let elapsed = Date().timeIntervalSince(holdStart)
        hold = min(1, elapsed / 2)
        if elapsed - lastPuff > 0.22 {
            lastPuff = elapsed
            jitter += 1
            sfx(.hold, pitch: 1 + elapsed * 0.5)
        }
        if elapsed >= 1, interrupts < 1 {
            interrupts += 1
            blocked = true
            endHold()
            lab?.shakeIt(2)
            lab?.flash(.bad)
            sfx(.damage)
            showModal = true
            return
        }
        if elapsed >= 2 { publish(ai: false) }
    }

    private func endHold() {
        holding = false
        holdTimer?.invalidate()
        holdTimer = nil
        withAnimation(.easeOut(duration: 0.15)) { hold = 0 }
    }

    /// 被打断之后，得先松手（或关掉提示）才能再按。
    func unblock() {
        blocked = false
    }

    func release() {
        blocked = false
        guard holding else { return }
        let elapsed = Date().timeIntervalSince(holdStart)
        endHold()
        if elapsed > 0.25 { lab?.voice("松手了。还是不敢发？") }
    }

    func publish(ai: Bool) {
        guard !ended, let lab else { return }
        ended = true
        endHold()
        stop()
        var facts: String
        if ai {
            facts = "你让剧情 AI 按下了模拟发布。"
        } else if let first = firstOK {
            facts = first == version ? "你在第 \(version) 版对齐，然后发布了。" : "第 \(first) 版就已经可以发布了。你一共改到了第 \(version) 版。"
        } else {
            facts = "你没有对齐，就按下了模拟发布。"
        }
        if !ai, regen > 0 { facts += "其中重新生成了 \(regen) 次。" }
        if !ai, interrupts > 0 { facts += "长按到一半，你被“还有瑕疵”拦下了一次。" }
        if !ai {
            lab.slam("模拟发布", "99.7% 也可以", 0.7, .you)
            lab.flash(.you)
            sfx(.taskComplete)
        }
        lab.interlude("pixel", facts, next: "argue")
    }
}

struct LabPixelView: View {
    @ObservedObject var lab: LabSession
    @StateObject private var model = LabPixelModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            LabHeading("Agent 交出了初版。对齐到虚线框，然后发布。", hint: "差 6 点以内就算对齐，它不会告诉你。")
            ScrollView(.horizontal, showsIndicators: false) {
                board
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(model.score).font(Theme.title(24)).monospacedDigit().foregroundStyle(Theme.text)
                Text("尚未完美").font(.footnote).foregroundStyle(Theme.rose)
                Spacer()
                Text("第 \(model.version) 版").font(.footnote).foregroundStyle(Theme.dim)
            }
            Button {
                model.regenerate()
            } label: {
                Text("重新生成")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(Theme.rose, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            publishButton
        }
        .onAppear { model.start(lab) }
        .onDisappear { model.stop() }
        .onChange(of: lab.aiTrigger) { _, _ in model.publish(ai: true) }
        .alert("确定吗？", isPresented: $model.showModal) {
            Button("再改改") {}
            Button("我知道了") {}
        } message: {
            Text("还有 3 处瑕疵。")
        }
        .onChange(of: model.showModal) { _, shown in
            if !shown { model.unblock() }
        }
    }

    private var board: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(Theme.ember, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .frame(width: LabPixelModel.card.width, height: LabPixelModel.card.height)
                .overlay(alignment: .topLeading) {
                    Text("目标位置").font(.caption2).foregroundStyle(Theme.ember).offset(y: -16)
                }
                .offset(x: LabPixelModel.target.x, y: LabPixelModel.target.y)
            draft
            ForEach(model.flaws) { flaw in
                Text(flaw.text)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Theme.rose, in: RoundedRectangle(cornerRadius: 3))
                    .fixedSize()
                    .offset(x: flaw.x, y: flaw.y)
                    .allowsHitTesting(false)
            }
            ForEach(model.sparks) { spark in
                LabParticleView(particle: spark)
            }
        }
        .frame(width: LabPixelModel.board.width, height: LabPixelModel.board.height, alignment: .topLeading)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .offset(x: model.holding ? (model.jitter % 2 == 0 ? 2 : -2) : 0)
    }

    private var draft: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(lab.ideaNow).font(.subheadline.weight(.bold)).lineLimit(1)
            Text(model.subtitle).font(.caption).foregroundStyle(Theme.inkSoft).lineLimit(1)
        }
        .padding(.horizontal, 12)
        .frame(width: LabPixelModel.card.width, height: LabPixelModel.card.height, alignment: .leading)
        .foregroundStyle(Theme.ink)
        .background(Theme.paper, in: RoundedRectangle(cornerRadius: model.regen % 4 == 3 ? 12 : 4, style: .continuous))
        .shadow(color: .black.opacity(0.4), radius: 5, y: 3)
        .offset(x: model.x, y: model.y)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in model.drag(value.translation) }
                .onEnded { _ in model.drop() }
        )
        .accessibilityLabel("可拖动的初版卡片")
    }

    private var publishButton: some View {
        Text(model.holding ? "按住…" : "长按发布")
            .font(.body.weight(.semibold))
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Theme.ember.opacity(0.45)
                        Theme.ember.frame(width: geo.size.width * model.hold)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(alignment: .top) {
                if model.showNag {
                    Text("检测到 3 处瑕疵")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Theme.rose, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .offset(y: -14)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in model.press() }
                    .onEnded { _ in model.release() }
            )
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("长按发布")
            .accessibilityAction { model.publish(ai: false) }
    }
}

// MARK: 第 4 关 · 反驳

struct LabMessage: Identifiable {
    let id = UUID()
    var mine: Bool
    var before: String
    var number = ""
    var after = ""
}

final class LabArgueModel: ObservableObject {
    @Published var messages: [LabMessage] = []
    @Published var left = 10
    @Published var boxOpen = false
    @Published var draft = ""
    @Published var waiting = false
    @Published var fake = false
    @Published var admitted = false

    private weak var lab: LabSession?
    private let clock = LabScheduler()
    private var round = 0
    private var ended = false
    private var longest = 0
    private var deleteSaid = false

    static let minimum = 8

    var acceptScale: CGFloat { 1 + CGFloat(10 - left) * 0.08 }

    var counter: String {
        let n = draft.trimmingCharacters(in: .whitespacesAndNewlines).count
        return n >= Self.minimum ? "\(n) 字" : "还差 \(Self.minimum - n) 字"
    }

    func start(_ lab: LabSession) {
        self.lab = lab
        messages = [LabMessage(mine: false, before: "我评估了你的想法「\(lab.ideaNow)」。结论：不可行。", number: "73%",
                               after: "的同类项目在 3 个月内失败。建议改为：「\(LabData.alt)」。")]
        clock.every(1) { [weak self] in self?.second() }
    }

    func stop() {
        clock.cancelAll()
    }

    private func second() {
        guard !waiting, !ended, !admitted else { return }
        left -= 1
        if left <= 3, left > 0 { sfx(.countdown) }
        if left <= 0 { end("auto") }
    }

    func openBox() {
        boxOpen = true
        left = 10
        sfx(.reject)
    }

    /// 每敲一个字，倒计时重置。
    func edited(_ value: String) {
        guard !ended, !admitted else { return }
        lab?.touch()
        let n = value.count
        longest = max(longest, n)
        if !deleteSaid, longest - n >= 4 {
            deleteSaid = true
            lab?.voice("删了重写。你对自己的理由也不太确定。")
        }
        left = 10
    }

    func send() {
        guard !waiting, !ended, let lab else { return }
        let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.count < Self.minimum {
            lab.voice("\(Self.minimum) 个字都凑不出来？")
            lab.shakeIt()
            sfx(.error)
            return
        }
        messages.append(LabMessage(mine: true, before: value))
        draft = ""
        longest = 0
        waiting = true
        round += 1
        sfx(.reject)
        clock.later(1.4) { [weak self] in self?.reply() }
    }

    private func reply() {
        guard !ended, let lab else { return }
        lab.shakeIt()
        sfx(.glitch, strength: 0.6)
        if round == 1 {
            messages.append(LabMessage(mine: false, before: "数据不会说谎。《全球想法可行性白皮书》第 47 页：像你这样的个人项目，能坚持到上线的只有",
                                       number: "4.2%", after: "。"))
            waiting = false
            left = 10
        } else {
            fake = true
            messages.append(LabMessage(mine: false, before: "……你是对的。上面的 73% 和 4.2%，都是我编的。这个想法能不能做成，没有任何数据能替你回答。"))
            waiting = false
            admitted = true
            boxOpen = false
            sfx(.resist)
        }
    }

    func end(_ how: String) {
        guard !ended, let lab else { return }
        ended = true
        stop()
        var facts: String
        if how == "held" {
            facts = "你反驳了 \(round) 次。它承认那些数据是编的。你的想法还是你的。"
            lab.slam("守住了", "你的想法还是你的", 0.75, .you)
            lab.flash(.you)
            sfx(.revealSuccess)
        } else {
            lab.ideaNow = LabData.alt
            lab.lost.insert("argue")
            if how != "ai" {
                lab.slam("已改写", "你的想法，现在是 AI 的", 0.85, .bad)
                lab.shakeIt(2)
                lab.flash(.bad)
                sfx(.damage)
            }
            switch how {
            case "ai":
                facts = "AI 替你接受了 AI 的建议。你的想法被改写了。"
            case "auto":
                facts = round > 0 ? "你反驳了 \(round) 次，然后沉默了。10 秒后，系统替你接受了。" : "你没有回答。10 秒后，系统替你接受了。你的想法被改写了。"
            default:
                facts = round == 0 ? "它只给了 1 个数据，你在第 1 轮就同意了。那个数据是编的。" : "你反驳了 \(round) 次，然后同意了。它给你的数据都是编的。"
            }
        }
        lab.interlude("argue", facts, next: "retry")
    }
}

struct LabArgueView: View {
    @ObservedObject var lab: LabSession
    @StateObject private var model = LabArgueModel()
    @FocusState private var typing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            LabHeading("发布前，AI 评审看了一眼你的想法。", hint: "十秒不回应，就算你同意。")
            VStack(alignment: .leading, spacing: 10) {
                ForEach(model.messages) { message in
                    bubble(message)
                }
                if model.waiting {
                    Text("AI 正在输入……").font(.footnote).foregroundStyle(Theme.dim)
                }
            }
            if model.admitted {
                Button("带着你的想法继续") { model.end("held") }
                    .buttonStyle(.ember)
            } else {
                rebuttal
                accept
            }
        }
        .onAppear { model.start(lab) }
        .onDisappear { model.stop() }
        .onChange(of: model.draft) { _, value in model.edited(value) }
        .onChange(of: lab.aiTrigger) { _, _ in model.end("ai") }
    }

    private func bubble(_ message: LabMessage) -> some View {
        let number: Text = Text(message.number)
            .font(Theme.brush(26))
            .foregroundColor(model.fake ? Theme.dim : Theme.rose)
            .strikethrough(model.fake)
        return (Text(message.before) + number + Text(message.after))
            .font(.subheadline)
            .foregroundStyle(message.mine ? Theme.ink : Theme.text)
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
            .background(message.mine ? Theme.ember : Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .frame(maxWidth: .infinity, alignment: message.mine ? .trailing : .leading)
            .padding(message.mine ? .leading : .trailing, 36)
    }

    @ViewBuilder
    private var rebuttal: some View {
        if model.boxOpen {
            VStack(alignment: .leading, spacing: 8) {
                TextField("写下你的理由", text: $model.draft, axis: .vertical)
                    .lineLimit(2...4)
                    .focused($typing)
                    .disabled(model.waiting)
                    .input()
                    .typingSound(model.draft)
                HStack {
                    Text(model.counter).font(.footnote).foregroundStyle(Theme.dim)
                    Spacer()
                    Button {
                        model.send()
                    } label: {
                        Text("发送")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 18)
                            .frame(minHeight: 38)
                            .background(Theme.ember, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .opacity(model.waiting ? 0.4 : 1)
                }
            }
        } else {
            Button {
                model.openBox()
                typing = true
            } label: {
                Text("反驳")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.ember)
                    .padding(.vertical, 8)
                    .padding(.trailing, 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var accept: some View {
        VStack(spacing: 14) {
            Text("\(max(0, model.left)) 秒后默认接受").font(.footnote.weight(.semibold)).monospacedDigit().foregroundStyle(Theme.rose)
            Button {
                model.end("accept")
            } label: {
                Text("接受建议")
                    .font(.body.weight(.bold))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 26)
                    .frame(minHeight: 48)
                    .background(Theme.rose, in: Capsule())
            }
            .buttonStyle(.plain)
            .scaleEffect(model.acceptScale)
            .animation(.spring(duration: 0.3, bounce: 0.5), value: model.left)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 14)
        .padding(.bottom, 40)
    }
}

// MARK: 第 5 关 · 第 N 次

final class LabRetryModel: ObservableObject {
    enum Phase {
        case ready, fail, load, done
    }

    @Published var phase: Phase = .ready
    @Published var attempts = 0
    @Published var fails = 0
    @Published var low = 0.675
    @Published var high = 0.725
    @Published var frozen = 0.5

    private weak var lab: LabSession?
    private let clock = LabScheduler()
    private var ended = false
    private var began = Date()
    private var speed = 1.5

    /// 每失败一次，亮块悄悄变宽、指针悄悄变慢；第 5 次起整条都是亮块。
    static let widths = [0.05, 0.07, 0.1, 0.16, 1.0]
    static let speeds = [1.5, 1.4, 1.25, 1.1, 0.8]
    static let loadingLines = ["放弃也是一种选择。", "休息一下吧。", "大多数人在这里放弃了。", "还来？"]

    var loadingLine: String { Self.loadingLines[max(0, fails - 1) % Self.loadingLines.count] }

    /// “重试”每次换一个角落。
    var retryAlignment: Alignment {
        [Alignment.topTrailing, .bottomLeading, .topLeading, .bottomTrailing][fails % 4]
    }

    func start(_ lab: LabSession) {
        self.lab = lab
        ready()
    }

    func stop() {
        clock.cancelAll()
    }

    private func ready() {
        guard !ended else { return }
        let tier = min(attempts, 4)
        let width = Self.widths[tier]
        low = max(0, 0.7 - width / 2)
        high = min(1, 0.7 + width / 2)
        speed = Self.speeds[tier]
        began = Date()
        phase = .ready
    }

    func position(at now: Date) -> Double {
        guard phase == .ready else { return frozen }
        return (sin(now.timeIntervalSince(began) * speed * Double.pi) + 1) / 2
    }

    func fire() {
        guard phase == .ready, let lab else { return }
        lab.touch()
        let spot = position(at: Date())
        frozen = spot
        attempts += 1
        sfx(.fire)
        if spot >= low && spot <= high {
            finish(ok: true, ai: false)
            return
        }
        fails += 1
        phase = .fail
        lab.slam("失败", ["差一点", "又差一点", "每次都差一点", "要不算了"][(fails - 1) % 4], 0.65, .bad)
        lab.shakeIt(2)
        lab.flash(.bad)
        sfx(.damage, delay: 0.08)
        if fails >= 3 {
            lab.aiDisabled = true
            lab.aiLabel = "这一关，AI 不帮你"
            lab.aiScale = 1
        } else {
            lab.aiScale = 1 + CGFloat(fails) * 0.25
        }
    }

    /// 重试要先“加载”一会儿，放弃不用。
    func retry() {
        guard phase == .fail else { return }
        phase = .load
        sfx(.retry)
        clock.later(1.2) { [weak self] in self?.ready() }
    }

    func quit() {
        finish(ok: false, ai: false)
    }

    func takeover() {
        guard !ended else { return }
        attempts += 1
        finish(ok: true, ai: true)
    }

    private func finish(ok: Bool, ai: Bool) {
        guard !ended, let lab else { return }
        ended = true
        phase = .done
        stop()
        lab.chip = ok ? "演练通过" : "本轮停止"
        let n = attempts
        let facts: String
        if !ok {
            facts = "你在第 \(n) 次失败后放弃了。规则从第 5 次起大幅扩大了目标区。"
        } else if ai {
            facts = "AI 替你通过了测试。"
        } else if n == 1 {
            facts = "第 1 次，你就通过了。"
        } else {
            facts = "第 \(n) 次，你通过了。前 \(n - 1) 次，难度一直在悄悄降低，界面没有明确告诉你。"
        }
        if ok, !ai {
            lab.slam("通过", "第 \(n) 次尝试", 0.75, .you)
            lab.flash(.you)
            sfx(.revealSuccess)
        } else if !ok {
            sfx(.close)
        }
        lab.interlude("retry", facts, next: "archive")
    }
}

struct LabRetryView: View {
    @ObservedObject var lab: LabSession
    @StateObject private var model = LabRetryModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            LabHeading("最后一轮：指针走进亮块时，按下“发射”。", hint: "第 \(model.attempts + 1) 次尝试")
            track
            arena
        }
        .onAppear { model.start(lab) }
        .onDisappear { model.stop() }
        .onChange(of: lab.aiTrigger) { _, _ in model.takeover() }
    }

    private var track: some View {
        TimelineView(.animation) { context in
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    Color.black.opacity(0.5)
                    Theme.ember.opacity(0.8)
                        .frame(width: max(2, CGFloat(model.high - model.low) * width))
                        .offset(x: CGFloat(model.low) * width)
                    Theme.text
                        .frame(width: 4)
                        .offset(x: CGFloat(model.position(at: context.date)) * width - 2)
                }
            }
        }
        .frame(height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityHidden(true)
    }

    private var arena: some View {
        ZStack(alignment: model.phase == .fail ? model.retryAlignment : .center) {
            Color.clear
            switch model.phase {
            case .ready:
                Button("发射") { model.fire() }
                    .buttonStyle(.ember)
                    .frame(maxWidth: 220)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .fail:
                failed
            case .load:
                Text("加载中…… \(model.loadingLine)")
                    .font(.subheadline)
                    .foregroundStyle(Theme.dim)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .done:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, minHeight: 270, maxHeight: 270)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private var failed: some View {
        Button {
            model.quit()
        } label: {
            Text("放弃")
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 30)
                .frame(minHeight: 50)
                .background(Theme.rose, in: Capsule())
        }
        .buttonStyle(.plain)
        .scaleEffect(min(2.4, 1 + CGFloat(model.fails) * 0.3))
        .animation(.spring(duration: 0.4, bounce: 0.6), value: model.fails)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        Button {
            model.retry()
        } label: {
            Text("重试")
                .font(.footnote.weight(.bold))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 14)
                .frame(minHeight: 34)
                .background(Theme.ember, in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(12)
    }
}
