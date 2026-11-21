import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

/// 山庄的背景音乐：自带一段 30 秒试听循环，也可以换成自己导入的音频。
final class MusicPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = MusicPlayer()

    enum Source: String {
        case bundled, local, none
    }

    static let officialURL = URL(string: "https://music.apple.com/cn/song/1695861086")!
    static let maxBytes = 40 * 1024 * 1024
    static let importTypes: [UTType] = [.mp3, .mpeg4Audio, .wav, .aiff]

    @Published private(set) var source: Source = .none
    @Published private(set) var filename = ""
    @Published private(set) var playing = false
    @Published private(set) var message = ""
    @Published var enabled: Bool { didSet { defaults.set(enabled, forKey: "music.enabled"); sync() } }
    @Published var volume: Double { didSet { defaults.set(volume, forKey: "music.volume"); player?.volume = Float(volume) } }

    private var player: AVAudioPlayer?
    private var active = true
    private var muted = false
    private let defaults = UserDefaults.standard

    private var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Music", isDirectory: true)
    }

    private override init() {
        let saved = UserDefaults.standard
        enabled = saved.object(forKey: "music.enabled") as? Bool ?? true
        volume = saved.object(forKey: "music.volume") as? Double ?? 0.3
        super.init()
        restore()
    }

    var hasSource: Bool { source != .none }
    var bundledURL: URL? { Bundle.main.url(forResource: "bgm_default", withExtension: "m4a") }

    var status: String {
        if muted { return "全部声音已关闭" }
        if !hasSource { return "还没有音源" }
        if volume == 0 { return "音乐音量为 0" }
        if playing { return source == .bundled ? "正在循环默认试听" : "正在循环播放" }
        return enabled ? "等待播放" : "已暂停"
    }

    private func restore() {
        let choice = defaults.string(forKey: "music.source") ?? "auto"
        if choice == "none" { return }
        if choice != "bundled", let name = defaults.string(forKey: "music.file") {
            let url = folder.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path), load(url) {
                source = .local
                filename = defaults.string(forKey: "music.title") ?? name
                return
            }
        }
        useBundled(remember: false)
    }

    private func load(_ url: URL) -> Bool {
        guard let made = try? AVAudioPlayer(contentsOf: url) else { return false }
        made.numberOfLoops = -1
        made.volume = Float(volume)
        made.delegate = self
        made.prepareToPlay()
        player?.stop()
        player = made
        return true
    }

    @discardableResult
    private func useBundled(remember: Bool) -> Bool {
        guard let url = bundledURL, load(url) else {
            source = .none
            filename = ""
            return false
        }
        source = .bundled
        filename = "默认试听 · 30 秒循环"
        if remember { defaults.set("bundled", forKey: "music.source") }
        return true
    }

    private func sync() {
        guard let player else {
            playing = false
            return
        }
        if enabled, active, !muted {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try? AVAudioSession.sharedInstance().setActive(true)
            if !player.isPlaying { player.play() }
        } else if player.isPlaying {
            player.pause()
        }
        playing = player.isPlaying
    }

    func play() {
        message = ""
        guard hasSource else {
            message = "先恢复默认试听，或导入一段音频。"
            return
        }
        if enabled { sync() } else { enabled = true }
    }

    func pause() {
        if enabled { enabled = false } else { sync() }
    }

    func toggle() {
        if playing { pause() } else { play() }
    }

    /// 导入一段本地音频并开始循环。
    func importFile(_ url: URL) {
        message = ""
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size > 0 else {
            message = "这个文件读不到，请换一个。"
            return
        }
        guard size <= Self.maxBytes else {
            message = "请选择不超过 40 MB 的音频。"
            return
        }
        let ext = url.pathExtension.isEmpty ? "m4a" : url.pathExtension.lowercased()
        let name = "current.\(ext)"
        let target = folder.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for old in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] {
                try? FileManager.default.removeItem(at: old)
            }
            try FileManager.default.copyItem(at: url, to: target)
        } catch {
            message = "没能保存这段音频，请再试一次。"
            return
        }
        guard load(target) else {
            try? FileManager.default.removeItem(at: target)
            message = "这段音频放不了，请换成 MP3 或 M4A。"
            if source == .local { useBundled(remember: true) }
            return
        }
        source = .local
        filename = url.lastPathComponent
        defaults.set("local", forKey: "music.source")
        defaults.set(name, forKey: "music.file")
        defaults.set(filename, forKey: "music.title")
        if enabled { sync() } else { enabled = true }
    }

    func restoreDefault() {
        message = ""
        if useBundled(remember: true) {
            sync()
        } else {
            message = "默认试听不可用。"
        }
    }

    func remove() {
        player?.stop()
        player = nil
        playing = false
        source = .none
        filename = ""
        defaults.set("none", forKey: "music.source")
        message = ""
    }

    /// 进后台暂停，回前台接着放。
    func setActive(_ value: Bool) {
        active = value
        sync()
    }

    /// 跟随“全部声音”的总开关。
    func setMuted(_ value: Bool) {
        muted = value
        sync()
    }
}
