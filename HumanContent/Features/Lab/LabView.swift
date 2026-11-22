import SwiftUI

// 反向体验（木偶剧场）：界面故意捣乱，看你守不守得住自己的选择。
// 这里发生的一切都只改试玩副本，不碰真实任务，也不给经验。

enum LabData {
    static let keys = ["prologue", "feed", "wait", "pixel", "argue", "retry"]
    static let order = keys + ["archive"]
    static let backstage = ["pixel", "argue", "retry"]
    static let alt = "先不做，等 AI 再成熟一点"

    static let names = [
        "prologue": "一个想法", "feed": "收藏夹", "wait": "等待", "pixel": "像素",
        "argue": "反驳", "retry": "第 N 次", "archive": "档案",
    ]

    static let chips = [
        "prologue": "想法", "feed": "收藏中", "wait": "制作中", "pixel": "打磨中",
        "argue": "待验证", "retry": "测试中", "archive": "演练记录",
    ]

    static let idle = [
        "prologue": "8 秒没动。连想做什么，都要想这么久。",
        "feed": "你不点，它也在放。看得还挺认真。",
        "wait": "你没在看。弹窗会默认允许的。",
        "pixel": "盯着它看，像素不会自己对齐。",
        "argue": "沉默也是一种回答。倒计时还在走。",
        "retry": "不按，就不会失败。也不会通过。",
    ]

    struct MenuItem: Identifiable {
        let key: String
        let title: String
        let line: String
        var id: String { key }
    }

    static let menu = [
        MenuItem(key: "prologue", title: "抢写补全", line: "你停一下，它就替你写。"),
        MenuItem(key: "feed", title: "收藏夹", line: "按钮追着你跑，收藏比动手容易。"),
        MenuItem(key: "wait", title: "等待", line: "允许和拒绝会换位，默认值替你决定。"),
        MenuItem(key: "pixel", title: "像素", line: "永远差一点的完美，长按也被挑刺。"),
        MenuItem(key: "argue", title: "反驳", line: "接受越来越大，沉默十秒算同意。"),
        MenuItem(key: "retry", title: "第 N 次", line: "失败越多，放弃越大。重试总在别处。"),
    ]

    static func label(_ key: String) -> String {
        if key == "prologue" { return "序章 · 一个想法" }
        if key == "archive" { return "终章 · 档案" }
        return "第 \(keys.firstIndex(of: key) ?? 0) 关 · \(names[key] ?? "")"
    }

    static func stepSymbol(_ key: String) -> String {
        if key == "prologue" { return "序" }
        if key == "archive" { return "终" }
        return "\(keys.firstIndex(of: key) ?? 0)"
    }

    struct Video {
        let author: String
        let title: String
    }

    static func videos(for idea: String) -> [Video] {
        let k = idea.count > 10 ? String(idea.prefix(10)) + "…" : idea
        return [
            Video(author: "@AI效率君", title: "3 分钟看懂：「\(k)」其实很简单"),
            Video(author: "@Agent研究所", title: "我用 AI Agent 一晚上就做完了「\(k)」"),
            Video(author: "@收藏夹吃灰了", title: "收藏了就是会了：「\(k)」完整教程（上）"),
            Video(author: "@每天进步一点点", title: "为什么你迟迟没有开始？"),
            Video(author: "@自律打卡王", title: "别急着做「\(k)」，先看完这条"),
        ]
    }
}

enum LabTone {
    case plain, bad, you, ai

    var color: Color {
        switch self {
        case .plain: return Theme.text
        case .you: return Theme.ember
        case .bad, .ai: return Theme.rose
        }
    }
}

struct LabBanner: Identifiable, Equatable {
    let id = UUID()
    var big: String
    var small: String
    var tone: LabTone
}

struct LabRecord: Identifiable {
    let id = UUID()
    var key: String
    var label: String
    var facts: String
    var byAI: Bool
    var atSeconds: Int
}

/// 飞出去的小字（“+1”“瑕疵”“新”）。
struct LabParticle: Identifiable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    var dx: CGFloat
    var dy: CGFloat
    var text: String
    var size: CGFloat
    var rotation: Double

    static func burst(at p: CGPoint, count: Int, text: String) -> [LabParticle] {
        (0..<count).map { _ in
            let angle = Double.random(in: 0..<(2 * Double.pi))
            let distance = Double.random(in: 60...170)
            return LabParticle(x: p.x, y: p.y, dx: CGFloat(cos(angle) * distance), dy: CGFloat(sin(angle) * distance - 40),
                               text: text, size: CGFloat.random(in: 14...28), rotation: Double.random(in: -50...50))
        }
    }
}

/// 关卡里的延时与循环。离开关卡时一次清掉。
final class LabScheduler {
    private var works: [DispatchWorkItem] = []
    private var timers: [Timer] = []

    @discardableResult
    func later(_ seconds: Double, _ block: @escaping () -> Void) -> DispatchWorkItem {
        let work = DispatchWorkItem(block: block)
        works.append(work)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
        return work
    }

    func every(_ seconds: Double, _ block: @escaping () -> Void) {
        let timer = Timer(timeInterval: seconds, repeats: true) { _ in block() }
        RunLoop.main.add(timer, forMode: .common)
        timers.append(timer)
    }

    func cancelAll() {
        for work in works { work.cancel() }
        works = []
        for timer in timers { timer.invalidate() }
        timers = []
    }

    deinit { cancelAll() }
}

/// 底部一个字一个字打出来的旁白。单独一个对象，免得整页跟着刷新。
final class LabCaption: ObservableObject {
    @Published var text = ""
    @Published var on = false
}

final class LabSession: ObservableObject {
    let entry: LabEntry
    let captionBox = LabCaption()

    @Published var level = "intro"
    @Published var runID = 0
    @Published var idea = ""
    @Published var ideaNow = ""
    @Published var chip = "—"
    @Published var saves: [String] = []
    @Published var ai: Set<String> = []
    @Published var lost: Set<String> = []
    @Published var mirror: [String: String] = [:]
    @Published var notes: [String: String] = [:]
    @Published var records: [LabRecord] = []
    @Published var ghostAccepted = 0
    @Published var banner: LabBanner?
    @Published var flashTone: LabTone?
    @Published var shake = 0
    @Published var interLevel = ""
    @Published var interNext = ""
    @Published var aiTrigger = 0
    @Published var aiScale: CGFloat = 1
    @Published var aiDisabled = false
    @Published var aiLabel = "让 AI 来"
    @Published var favBump = 0

    var pred = (done: 50, ai: 1, saves: 2)
    var backstageOpen = true
    var t0: Date?
    var tEnd: Date?
    private(set) var started = false
    private(set) var reported = false
    private var startedAt = Date()
    private var aiPending = false
    private var lastAct = Date()
    private var idleSaid = false
    private var taps: [Date] = []
    private var rageAt = Date.distantPast
    private var captionTimer: Timer?
    private var captionChars: [Character] = []
    private var captionShown = 0
    private var captionHide: DispatchWorkItem?
    private var bannerHide: DispatchWorkItem?

    init(entry: LabEntry) {
        self.entry = entry
    }

    // MARK: 流程

    func start() {
        guard !started else { return }
        started = true
        startedAt = Date()
        if !entry.taskTitle.isEmpty {
            idea = entry.taskTitle
            ideaNow = idea
        }
        let first = (LabData.order.contains(entry.level) && isOpen(entry.level)) ? entry.level : "intro"
        if first != "intro" {
            if idea.isEmpty {
                idea = "把第一版草稿发给一个人"
                ideaNow = idea
            }
            t0 = Date()
        }
        go(first)
    }

    func isOpen(_ key: String) -> Bool {
        backstageOpen || !LabData.backstage.contains(key)
    }

    /// 后台还没开门时，后三关直接跳到终章。
    func resolved(_ key: String) -> String {
        isOpen(key) ? key : "archive"
    }

    func go(_ name: String) {
        let name = resolved(name)
        aiPending = false
        idleSaid = false
        lastAct = Date()
        if name == "archive" {
            if tEnd == nil { tEnd = Date() }
        } else {
            tEnd = nil
        }
        if let text = LabData.chips[name] { chip = text }
        aiDisabled = false
        aiScale = 1
        aiLabel = "让 AI 来"
        level = name
        runID += 1
        if let i = LabData.keys.firstIndex(of: name) {
            slam(i == 0 ? "序章" : "第 \(i) 关", LabData.names[name] ?? "", 0.8, .plain)
            sfx(.open)
        }
    }

    /// 顶部小方块跳关。
    func jump(to key: String) {
        guard isOpen(key) else { return }
        if t0 == nil { t0 = Date() }
        if key != "prologue" && idea.isEmpty {
            idea = "做一个记账小程序"
            ideaNow = idea
        }
        sfx(.nav)
        go(key)
    }

    /// 一关结束：记下发生了什么，进过场。
    func interlude(_ key: String, _ facts: String, next: String) {
        aiPending = false
        mirror[key] = facts
        records.append(LabRecord(key: key, label: LabData.label(key), facts: facts, byAI: ai.contains(key),
                                 atSeconds: max(0, Int(Date().timeIntervalSince(startedAt).rounded()))))
        interLevel = key
        interNext = next
        level = "inter"
        runID += 1
    }

    func reset() {
        saves = []
        ai = []
        lost = []
        mirror = [:]
        notes = [:]
        records = []
        ghostAccepted = 0
        chip = "—"
        t0 = nil
        tEnd = nil
        startedAt = Date()
        idea = entry.taskTitle
        ideaNow = idea
        sfx(.retry)
        go("intro")
    }

    func shutdown() {
        captionTimer?.invalidate()
        captionTimer = nil
        captionHide?.cancel()
        bannerHide?.cancel()
    }

    // MARK: 让 AI 来

    func takeover() {
        guard !aiDisabled, !aiPending, LabData.keys.contains(level) else { return }
        let current = level
        aiPending = true
        ai.insert(current)
        slam("AI 已接管", ["这就对了", "省事", "你歇着"][(ai.count - 1) % 3], 0.75, .ai)
        sfx(.takeover)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, self.level == current else { return }
            self.aiTrigger += 1
        }
    }

    // MARK: 反馈

    /// 旁白：逐字打出，停留一会儿后收起。
    func voice(_ message: String) {
        captionTimer?.invalidate()
        captionHide?.cancel()
        captionChars = Array(message)
        captionShown = 0
        captionBox.text = ""
        captionBox.on = true
        sfx(.type)
        let timer = Timer(timeInterval: 0.022, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            self.typeNextCharacter(timer)
        }
        RunLoop.main.add(timer, forMode: .common)
        captionTimer = timer
    }

    private func typeNextCharacter(_ timer: Timer) {
        captionShown += 1
        captionBox.text = String(captionChars.prefix(captionShown))
        guard captionShown >= captionChars.count else { return }
        timer.invalidate()
        let box = captionBox
        let hide = DispatchWorkItem {
            withAnimation(.easeOut(duration: 0.25)) { box.on = false }
        }
        captionHide = hide
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6, execute: hide)
    }

    /// 屏幕中央砸下来的大字。
    func slam(_ big: String, _ small: String = "", _ seconds: Double = 0.85, _ tone: LabTone = .plain) {
        bannerHide?.cancel()
        let made = LabBanner(big: big, small: small, tone: tone)
        withAnimation(.spring(duration: 0.28, bounce: 0.35)) { banner = made }
        let hide = DispatchWorkItem { [weak self] in
            guard self?.banner?.id == made.id else { return }
            withAnimation(.easeOut(duration: 0.25)) { self?.banner = nil }
        }
        bannerHide = hide
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: hide)
    }

    func flash(_ tone: LabTone) {
        flashTone = tone
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
            withAnimation(.easeOut(duration: 0.3)) { self?.flashTone = nil }
        }
    }

    func shakeIt(_ strength: Int = 1) {
        withAnimation(.default) { shake += strength }
    }

    // MARK: 发呆、连点

    func touch() {
        lastAct = Date()
    }

    func tap() {
        let now = Date()
        lastAct = now
        taps.append(now)
        taps = taps.filter { now.timeIntervalSince($0) < 1.5 }
        if taps.count >= 6, now.timeIntervalSince(rageAt) > 6, LabData.idle[level] != nil, level != "feed" {
            rageAt = now
            voice("检测到连点。点得再快，它也不会更快。")
            shakeIt()
        }
    }

    func idleCheck() {
        guard let line = LabData.idle[level], !idleSaid else { return }
        if Date().timeIntervalSince(lastAct) > 8 {
            idleSaid = true
            voice(line)
        }
    }

    func cameBack(after seconds: Int) {
        guard seconds >= 2, LabData.idle[level] != nil else { return }
        voice("你离开了 \(seconds) 秒。它没有自己完成。")
    }

    // MARK: 剧情时间与记录

    /// 剧情里的钟：按演练节奏快进，和现实用时无关。
    func clockText(at now: Date = Date()) -> String {
        guard let t0 else { return "09:00" }
        let end = tEnd ?? now
        let minutes = min(1439, 540 + Int(max(0, end.timeIntervalSince(t0)) / 0.3))
        return String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    /// 把这一轮试玩记录交给账本。整个演练只交一次；一条记录都没有就不交。
    func report(to store: Store) {
        guard !reported, !records.isEmpty else { return }
        reported = true
        let sim = records.map {
            SimRecord(level: $0.key, label: $0.label, text: $0.facts, note: notes[$0.key] ?? "", byAI: $0.byAI, atSeconds: $0.atSeconds)
        }
        store.logSimulation(task: entry.taskId, records: sim, elapsed: max(0, Int(Date().timeIntervalSince(startedAt))))
    }
}

// MARK: 外壳

struct LabView: View {
    let entry: LabEntry
    @StateObject private var lab: LabSession
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var stage: Stage
    @Environment(\.scenePhase) private var scenePhase
    @State private var awayAt: Date?

    let idleClock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(entry: LabEntry) {
        self.entry = entry
        _lab = StateObject(wrappedValue: LabSession(entry: entry))
    }

    var body: some View {
        ZStack {
            Atmosphere(backdrop: .docks, quiet: true)
            VStack(spacing: 0) {
                LabHUD(lab: lab, leave: leave)
                ScrollView {
                    levelView
                        .id(lab.runID)
                        .page()
                        .padding(.top, 16)
                        .padding(.bottom, 120)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .modifier(Shake(amount: CGFloat(lab.shake)))
            LabOverlays(lab: lab)
        }
        .simultaneousGesture(TapGesture().onEnded { lab.tap() })
        .onAppear {
            lab.backstageOpen = store.isOpen("backstage")
            lab.start()
        }
        .onDisappear { lab.shutdown() }
        .onReceive(idleClock) { _ in lab.idleCheck() }
        .onChange(of: lab.level) { _, level in
            if level == "archive", !lab.reported, !lab.records.isEmpty {
                lab.report(to: store)
                sfx(.revealSuccess, delay: 0.2)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                if let left = awayAt {
                    awayAt = nil
                    lab.cameBack(after: Int(Date().timeIntervalSince(left).rounded()))
                }
            } else if awayAt == nil {
                awayAt = Date()
            }
        }
    }

    @ViewBuilder
    private var levelView: some View {
        switch lab.level {
        case "intro": LabIntroView(lab: lab, leave: leave)
        case "prologue": LabPrologueView(lab: lab)
        case "feed": LabFeedView(lab: lab)
        case "wait": LabWaitView(lab: lab)
        case "pixel": LabPixelView(lab: lab)
        case "argue": LabArgueView(lab: lab)
        case "retry": LabRetryView(lab: lab)
        case "inter": LabInterludeView(lab: lab, leave: leave)
        default: LabArchiveView(lab: lab, leave: leave)
        }
    }

    /// 离开剧场：交出试玩记录，回到带进来的那件事。
    private func leave() {
        lab.report(to: store)
        lab.shutdown()
        sfx(.close)
        let stage = self.stage
        let taskId = entry.taskId
        let known = store.quest(taskId) != nil
        stage.lab = nil
        if known, let taskId { stage.openTask(taskId) }
    }
}

/// 顶栏：试玩副本、收藏夹、剧情时间、跳关。
struct LabHUD: View {
    @ObservedObject var lab: LabSession
    let leave: () -> Void
    @EnvironmentObject private var sound: SoundEngine

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Button {
                    lab.voice(lab.idea.isEmpty ? "还没写。看也没用。" : "看着它，不会让它完成。")
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("你的想法").font(.caption2).foregroundStyle(Theme.dim)
                            Tag(lab.chip)
                        }
                        Text(lab.ideaNow.isEmpty ? "尚未写下" : lab.ideaNow)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(changed ? Theme.rose : Theme.text)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                Button {
                    lab.voice(lab.saves.isEmpty ? "还是空的。别急，你会填满它的。" : "打开也不会变少。终章再看。")
                } label: {
                    Label("\(lab.saves.count)", systemImage: "bookmark.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(lab.saves.isEmpty ? Theme.dim : Theme.rose)
                        .scaleEffect(lab.favBump % 2 == 1 ? 1.25 : 1)
                        .animation(.spring(duration: 0.25, bounce: 0.6), value: lab.favBump)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("试玩收藏夹，\(lab.saves.count) 条")
                Button {
                    lab.voice("看时间，不会让它变慢。")
                } label: {
                    TimelineView(.periodic(from: .now, by: 0.3)) { context in
                        Text(lab.clockText(at: context.date))
                            .font(.footnote.weight(.medium))
                            .monospacedDigit()
                            .foregroundStyle(Theme.dim)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("剧情时间")
                Button {
                    sound.enabled.toggle()
                } label: {
                    Image(systemName: sound.enabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .font(.footnote)
                        .foregroundStyle(Theme.dim)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(sound.enabled ? "关掉声音" : "打开声音")
                Button(action: leave) {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Theme.text)
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(lab.entry.taskId == nil ? "离开剧场" : "回到任务")
            }
            steps
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(Theme.raised)
    }

    private var changed: Bool {
        !lab.idea.isEmpty && lab.ideaNow != lab.idea
    }

    private var steps: some View {
        HStack(spacing: 8) {
            ForEach(LabData.order, id: \.self) { key in
                stepButton(key)
            }
            Spacer(minLength: 0)
        }
    }

    private func stepButton(_ key: String) -> some View {
        let open = lab.isOpen(key)
        let current = lab.level == key || (lab.level == "inter" && lab.interLevel == key)
        let played = lab.mirror[key] != nil
        let byInterface = lab.ai.contains(key) || lab.lost.contains(key)
        let fill: Color = current ? Theme.text : played ? (byInterface ? Theme.rose : Theme.ember) : Color.white.opacity(0.08)
        return Button {
            lab.jump(to: key)
        } label: {
            Group {
                if open {
                    Text(LabData.stepSymbol(key)).font(.caption.weight(.bold))
                } else {
                    Image(systemName: "lock.fill").font(.system(size: 10))
                }
            }
            .foregroundStyle(current || played ? Theme.ink : Theme.dim)
            .frame(width: 30, height: 26)
            .background(fill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!open)
        .accessibilityLabel("跳到：\(LabData.label(key))")
    }
}

/// 盖在关卡上面的东西：AI 按钮、旁白、闪屏、大字。
struct LabOverlays: View {
    @ObservedObject var lab: LabSession

    var body: some View {
        ZStack {
            if LabData.keys.contains(lab.level) {
                Button {
                    lab.takeover()
                } label: {
                    Text(lab.aiLabel)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 44)
                        .background(lab.aiDisabled ? Theme.dim : Theme.rose, in: Capsule())
                }
                    .buttonStyle(.plain)
                    .shadow(color: .black.opacity(0.5), radius: 10, y: 4)
                    .scaleEffect(lab.aiScale, anchor: .bottomTrailing)
                    .animation(.spring(duration: 0.35, bounce: 0.5), value: lab.aiScale)
                    .disabled(lab.aiDisabled)
                    .padding(.trailing, 16)
                    .padding(.bottom, 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
            LabCaptionView(box: lab.captionBox)
            if let tone = lab.flashTone {
                tone.color.opacity(0.2).ignoresSafeArea().allowsHitTesting(false)
            }
            if let banner = lab.banner {
                LabBannerView(banner: banner).id(banner.id)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct LabCaptionView: View {
    @ObservedObject var box: LabCaption

    var body: some View {
        VStack {
            Spacer()
            if box.on {
                Text(box.text)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(alignment: .leading) {
                        Theme.rose.frame(width: 3).clipShape(Capsule()).padding(.vertical, 8)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 70)
                    .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(!box.on)
    }
}

struct LabBannerView: View {
    let banner: LabBanner

    var body: some View {
        VStack(spacing: 6) {
            Text(banner.big).font(Theme.brush(54)).foregroundStyle(banner.tone.color)
            if !banner.small.isEmpty {
                Text(banner.small).font(.subheadline.weight(.medium)).foregroundStyle(Theme.text)
            }
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 20)
        .background(Theme.night.opacity(0.94), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.6), radius: 20)
        .allowsHitTesting(false)
        .transition(.scale(scale: 1.25).combined(with: .opacity))
    }
}

/// 每一关的抬头：一句标题，最多一行提示。
struct LabHeading: View {
    let title: String
    var hint: String?

    init(_ title: String, hint: String? = nil) {
        self.title = title
        self.hint = hint
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(Theme.brush(24)).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
            if let hint {
                Text(hint).font(.subheadline).foregroundStyle(Theme.dim)
            }
        }
    }
}

/// 不带隐式动画的进度条。
struct LabBar: View {
    var value: Double
    var color: Color = Theme.rose
    var height: CGFloat = 3

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.1))
                Capsule().fill(color).frame(width: CGFloat(max(0, min(1, value))) * geo.size.width)
            }
        }
        .frame(height: height)
    }
}

/// 按真实时间走的倒计时条（rising 时反过来，从空走到满）。
struct LabCountdownBar: View {
    let start: Date
    let duration: Double
    var rising = false
    var color: Color = Theme.rose

    var body: some View {
        TimelineView(.animation) { context in
            let done = min(1, max(0, context.date.timeIntervalSince(start) / max(0.01, duration)))
            LabBar(value: rising ? done : 1 - done, color: color)
        }
    }
}

struct LabParticleView: View {
    let particle: LabParticle
    var color: Color = Theme.rose
    @State private var flown = false

    var body: some View {
        Text(particle.text)
            .font(.system(size: particle.size, weight: .heavy))
            .foregroundStyle(color)
            .rotationEffect(.degrees(flown ? particle.rotation : 0))
            .offset(x: flown ? particle.dx : 0, y: flown ? particle.dy : 0)
            .opacity(flown ? 0 : 1)
            .position(x: particle.x, y: particle.y)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeOut(duration: 0.8)) { flown = true }
            }
    }
}

// MARK: 开场

struct LabIntroView: View {
    @ObservedObject var lab: LabSession
    let leave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Button {
                lab.voice("标题没有藏着通关按钮。你可以开始，也可以现在就退出。")
                lab.shakeIt()
            } label: {
                Text("人类含量").font(Theme.brush(46)).foregroundStyle(Theme.text)
            }
            .buttonStyle(.plain)
            Text("你想做一件事。\n这个界面偏要让你收藏、等着、再改一轮。")
                .font(Theme.title(20))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            Text("按钮会追你，选项会换位，它会抢着替你写，还会替你默认同意。")
                .font(.subheadline)
                .foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
            if !lab.entry.taskTitle.isEmpty {
                Text("带进来的事：「\(lab.entry.taskTitle)」。这里改的只是它的副本。")
                    .font(.subheadline)
                    .foregroundStyle(Theme.ember)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("开始") {
                lab.t0 = Date()
                lab.go("prologue")
            }
            .buttonStyle(.ember)
            Button(lab.entry.taskId == nil ? "离开剧场" : "回到任务", action: leave)
                .buttonStyle(.quiet)
        }
    }
}

// MARK: 过场

struct LabInterludeView: View {
    @ObservedObject var lab: LabSession
    let leave: () -> Void
    @State private var note = ""

    var body: some View {
        let key = lab.interLevel
        let next = lab.resolved(lab.interNext)
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                Text(LabData.label(key)).font(.subheadline.weight(.medium)).foregroundStyle(Theme.dim)
                if lab.ai.contains(key) { Tag("AI 接管", color: Theme.rose) }
            }
            Text(lab.mirror[key] ?? "")
                .font(Theme.title(23))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            TextField("留一句自己的观察（可不填）", text: $note, axis: .vertical)
                .lineLimit(1...3)
                .input()
                .typingSound(note)
            Button(next == "archive" ? "去终章" : "继续下一关") {
                keep()
                sfx(.accept)
                lab.go(next)
            }
            .buttonStyle(.ember)
            Button(lab.entry.taskId == nil ? "离开剧场" : "回到任务") {
                keep()
                leave()
            }
            .buttonStyle(.quiet)
        }
        .onAppear { note = lab.notes[key] ?? "" }
    }

    private func keep() {
        lab.notes[lab.interLevel] = String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
    }
}

// MARK: 终章

struct LabArchiveView: View {
    @ObservedObject var lab: LabSession
    let leave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            LabHeading("你碰到的不是“你不行”。\n是一个故意把你带偏的界面。")
            copies
            tally
            journal
            if !lab.saves.isEmpty { shelf }
            Button(lab.entry.taskId == nil ? "离开剧场" : "回到任务", action: leave)
                .buttonStyle(.ember)
            Button("重新演练") { lab.reset() }
                .buttonStyle(.quiet)
        }
    }

    @ViewBuilder
    private var copies: some View {
        if !lab.idea.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("进来时的副本").font(.footnote.weight(.semibold)).foregroundStyle(Theme.inkSoft)
                Text("「\(lab.idea)」").font(Theme.title(19))
                if !lab.ideaNow.isEmpty && lab.ideaNow != lab.idea {
                    Text("后来变成：「\(lab.ideaNow)」").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.rose)
                }
            }
            .paper()
        }
    }

    private var tally: some View {
        let aiCount = LabData.keys.filter { lab.ai.contains($0) }.count
        return VStack(alignment: .leading, spacing: 0) {
            LedgerRow(label: "过场记录", value: "\(lab.records.count) 条")
            LedgerRow(label: "让 AI 接管", value: "\(aiCount) 关（你猜 \(lab.pred.ai) 次）",
                      color: aiCount > 0 ? Theme.rose : Theme.text)
            LedgerRow(label: "试玩收藏夹", value: "\(lab.saves.count) 条（你猜 \(lab.pred.saves) 条）",
                      color: lab.saves.isEmpty ? Theme.text : Theme.rose)
            LedgerRow(label: "AI 替你写进去的话", value: "\(lab.ghostAccepted) 段",
                      color: lab.ghostAccepted > 0 ? Theme.rose : Theme.text)
        }
        .raised()
    }

    @ViewBuilder
    private var journal: some View {
        SectionHeading("这一轮发生了什么")
        if lab.records.isEmpty {
            Text("还没有过场记录。").font(.subheadline).foregroundStyle(Theme.dim)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(lab.records) { record in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            Text(record.label).font(.footnote.weight(.semibold)).foregroundStyle(Theme.dim)
                            Text("\(record.atSeconds) 秒").font(.footnote).foregroundStyle(Theme.dim)
                            if record.byAI { Tag("AI 接管", color: Theme.rose) }
                        }
                        Text(record.facts).font(.subheadline).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
                        if let note = lab.notes[record.key], !note.isEmpty {
                            Text("你的观察：\(note)").font(.footnote.weight(.medium)).foregroundStyle(Theme.ember)
                        }
                    }
                }
            }
        }
    }

    private var shelf: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeading("试玩收藏夹", trailing: "\(lab.saves.count) 条")
            ForEach(lab.saves, id: \.self) { title in
                Text(title).font(.footnote).foregroundStyle(Theme.dim)
            }
        }
    }
}
