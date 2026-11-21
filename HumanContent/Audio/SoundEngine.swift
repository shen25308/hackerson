import AVFoundation
import SwiftUI
import UIKit

/// 播放合成音效。每个音效第一次用到时渲染成缓冲并缓存，之后直接播。
final class SoundEngine: ObservableObject {
    static let shared = SoundEngine()

    @Published var enabled: Bool { didSet { save(); applyVolume(); if !enabled { stopAll() } else { startAmbienceIfNeeded() } } }
    @Published var volume: Double { didSet { save(); applyVolume() } }
    @Published var ambience: Bool { didSet { save(); if ambience { startAmbienceIfNeeded() } else { stopAmbience() } } }
    @Published var haptics: Bool { didSet { save() } }

    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private let ambiencePlayer = AVAudioPlayerNode()
    private var nextPlayer = 0
    private var cache: [String: AVAudioPCMBuffer] = [:]
    private var lastPlayed: [Cue: TimeInterval] = [:]
    private var ambienceBuffer: AVAudioPCMBuffer?
    private let format: AVAudioFormat
    private let renderQueue = DispatchQueue(label: "sound.render", qos: .userInitiated)
    private var active = true
    private let defaults = UserDefaults.standard

    private init() {
        let saved = UserDefaults.standard
        enabled = saved.object(forKey: "sound.enabled") as? Bool ?? true
        volume = saved.object(forKey: "sound.volume") as? Double ?? 0.5
        ambience = saved.bool(forKey: "sound.ambience")
        haptics = saved.object(forKey: "sound.haptics") as? Bool ?? true
        format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        for _ in 0..<10 {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            players.append(node)
        }
        engine.attach(ambiencePlayer)
        engine.connect(ambiencePlayer, to: engine.mainMixerNode, format: format)
        applyVolume()
        NotificationCenter.default.addObserver(self, selector: #selector(configurationChanged),
                                               name: .AVAudioEngineConfigurationChange, object: engine)
        NotificationCenter.default.addObserver(self, selector: #selector(interrupted(_:)),
                                               name: AVAudioSession.interruptionNotification, object: nil)
        prewarm()
    }

    private func save() {
        defaults.set(enabled, forKey: "sound.enabled")
        defaults.set(volume, forKey: "sound.volume")
        defaults.set(ambience, forKey: "sound.ambience")
        defaults.set(haptics, forKey: "sound.haptics")
    }

    private func applyVolume() {
        engine.mainMixerNode.outputVolume = enabled ? Float(min(1, volume * 1.6)) : 0
    }

    /// 静音键不影响这里的声音，也不会打断别的 App 正在放的音乐。
    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
    }

    @discardableResult
    private func start() -> Bool {
        guard active else { return false }
        if engine.isRunning { return true }
        configureSession()
        do {
            try engine.start()
            return true
        } catch {
            return false
        }
    }

    private func buffer(from source: StereoBuffer) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(source.left.count)
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let channels = buffer.floatChannelData else { return nil }
        buffer.frameLength = frames
        source.left.withUnsafeBufferPointer { src in
            if let base = src.baseAddress { channels[0].update(from: base, count: source.left.count) }
        }
        source.right.withUnsafeBufferPointer { src in
            if let base = src.baseAddress { channels[1].update(from: base, count: source.right.count) }
        }
        return buffer
    }

    private func rendered(_ cue: Cue, pitch: Double) -> AVAudioPCMBuffer? {
        let key = pitch == 1 ? cue.rawValue : "\(cue.rawValue)@\(Int(pitch * 100))"
        if let hit = cache[key] { return hit }
        guard let made = buffer(from: CueBook.render(cue, pitch: pitch)) else { return nil }
        cache[key] = made
        return made
    }

    /// 常用音效提前渲染，避免第一次点按时卡一下。
    private func prewarm() {
        let common: [Cue] = [.click, .nav, .open, .close, .type, .tick, .paper, .pin, .scan, .accept, .reject, .toggleOn, .toggleOff, .taskComplete, .xp]
        renderQueue.async { [weak self] in
            guard let self else { return }
            var made: [String: AVAudioPCMBuffer] = [:]
            for cue in common {
                if let b = self.buffer(from: CueBook.render(cue)) { made[cue.rawValue] = b }
            }
            DispatchQueue.main.async {
                for (k, v) in made where self.cache[k] == nil { self.cache[k] = v }
            }
        }
    }

    /// 播放一个音效。strength 是相对音量，delay 以秒计，pitch 是音高倍率。
    func play(_ cue: Cue, strength: Double = 1, delay: Double = 0, pitch: Double = 1, force: Bool = false) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.play(cue, strength: strength, delay: delay, pitch: pitch, force: force) }
            return
        }
        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { self.play(cue, strength: strength, pitch: pitch, force: force) }
            return
        }
        Haptics.play(for: cue, enabled: haptics)
        guard enabled, volume > 0, active else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if !force, let last = lastPlayed[cue], now - last < cue.wait { return }
        lastPlayed[cue] = now
        guard let buffer = rendered(cue, pitch: pitch), start() else { return }
        let node = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        node.volume = Float(min(1.2, max(0.05, strength)))
        node.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        if !node.isPlaying { node.play() }
    }

    func stopAll() {
        for node in players { node.stop() }
        stopAmbience()
    }

    private func startAmbienceIfNeeded() {
        guard enabled, ambience, active, !ambiencePlayer.isPlaying else { return }
        if ambienceBuffer == nil { ambienceBuffer = buffer(from: CueBook.ambience()) }
        guard let loop = ambienceBuffer, start() else { return }
        ambiencePlayer.scheduleBuffer(loop, at: nil, options: .loops, completionHandler: nil)
        ambiencePlayer.play()
    }

    private func stopAmbience() {
        ambiencePlayer.stop()
    }

    /// 进后台时停掉，回前台再接上。
    func setActive(_ value: Bool) {
        active = value
        if value {
            startAmbienceIfNeeded()
        } else {
            stopAll()
            engine.pause()
        }
    }

    @objc private func configurationChanged() {
        DispatchQueue.main.async {
            guard self.active else { return }
            self.ambiencePlayer.stop()
            _ = self.start()
            self.startAmbienceIfNeeded()
        }
    }

    @objc private func interrupted(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        DispatchQueue.main.async {
            if type == .ended, self.active {
                _ = self.start()
                self.startAmbienceIfNeeded()
            }
        }
    }
}

/// 在任何地方播一个音效。
func sfx(_ cue: Cue, strength: Double = 1, delay: Double = 0, pitch: Double = 1) {
    SoundEngine.shared.play(cue, strength: strength, delay: delay, pitch: pitch)
}

enum Haptics {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let soft = UIImpactFeedbackGenerator(style: .soft)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private static let notice = UINotificationFeedbackGenerator()
    private static let selection = UISelectionFeedbackGenerator()

    static func play(for cue: Cue, enabled: Bool) {
        guard enabled else { return }
        switch cue {
        case .hover, .type, .slide, .hold:
            break
        case .tick, .nav, .swap, .toggleOn, .toggleOff:
            selection.selectionChanged()
        case .click, .paper, .collect, .accept, .reject, .xp, .countdown:
            light.impactOccurred()
        case .open, .close, .scan, .whoosh, .heal, .tempt, .retry, .undo, .focusPause:
            soft.impactOccurred()
        case .pin, .snip, .focusStart, .drawShuffle, .fire:
            medium.impactOccurred()
        case .vote, .stamp, .lock, .glitch, .takeover:
            rigid.impactOccurred()
        case .damage:
            heavy.impactOccurred()
        case .taskComplete, .revealSuccess, .levelup, .streak, .unlock, .drawReveal, .settleSafe, .focusEnd, .resist:
            notice.notificationOccurred(.success)
        case .revealWrong, .taken:
            notice.notificationOccurred(.warning)
        case .error:
            notice.notificationOccurred(.error)
        }
    }
}
