import Foundation
#if canImport(Combine)
import Combine
#endif

/// 行动计时。可以跨页面累计，暂停的时间不算；数字只代表你开过的计时，不代表任务完成。
final class FocusTimer: ObservableObject {
    struct State: Equatable {
        var taskId: String
        var date: String
        var demo: Bool
        var accumulated: TimeInterval
        var startedAt: Date
        var running: Bool
        var finished: Bool
    }

    @Published private(set) var state: State?
    /// 每秒变一次，用来驱动界面刷新。
    @Published private(set) var beat = 0

    private let defaults: UserDefaults
    private let key = "focus-v1"
    private var ticker: Timer?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let o = defaults.dictionary(forKey: key),
           let taskId = o["taskId"] as? String, let date = o["date"] as? String, date == Clock.dayID(),
           let accumulated = o["accumulated"] as? Double, let startedAt = o["startedAt"] as? Double {
            state = State(taskId: taskId, date: date, demo: false, accumulated: max(0, accumulated),
                          startedAt: Date(timeIntervalSince1970: startedAt),
                          running: o["running"] as? Bool ?? false, finished: o["finished"] as? Bool ?? false)
        }
    }

    func startTicking() {
        guard ticker == nil else { return }
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
    }

    private func save() {
        guard let s = state, !s.demo else {
            if state == nil { defaults.removeObject(forKey: key) }
            return
        }
        defaults.set(["taskId": s.taskId, "date": s.date, "accumulated": s.accumulated,
                      "startedAt": s.startedAt.timeIntervalSince1970, "running": s.running, "finished": s.finished] as [String: Any],
                     forKey: key)
    }

    /// 已累计的秒数。跨过当天零点后不再增加。
    func elapsed(now: Date = Date()) -> TimeInterval {
        guard let s = state else { return 0 }
        guard s.running else { return max(0, s.accumulated) }
        let cap = s.demo ? now : min(now, Clock.endOfDay(s.date) ?? now)
        return max(0, s.accumulated + max(0, cap.timeIntervalSince(s.startedAt)))
    }

    func isActive(for taskId: String) -> Bool {
        guard let s = state else { return false }
        return s.taskId == taskId && !s.finished
    }

    var activeTask: String? {
        guard let s = state, !s.finished else { return nil }
        return s.taskId
    }

    /// 给登记用时的建议：计过时就按分钟取整，至少 1 分钟。
    func suggestion(for taskId: String) -> Int? {
        guard let s = state, s.taskId == taskId, elapsed() > 0 else { return nil }
        return max(1, Int((elapsed() / 60).rounded()))
    }

    func focusedMinutes(for taskId: String) -> Int {
        guard let s = state, s.taskId == taskId else { return 0 }
        return Int(elapsed() / 60)
    }

    func start(_ taskId: String, date: String, demo: Bool) {
        if let s = state, s.taskId == taskId, s.date == date, !s.finished {
            resume()
            return
        }
        state = State(taskId: taskId, date: date, demo: demo, accumulated: 0, startedAt: Date(), running: true, finished: false)
        save()
    }

    func pause() {
        guard var s = state, s.running else { return }
        s.accumulated = elapsed()
        s.running = false
        state = s
        save()
    }

    func resume() {
        guard var s = state, !s.running, !s.finished else { return }
        s.startedAt = Date()
        s.running = true
        state = s
        save()
    }

    /// 结束这段计时，返回累计秒数。
    @discardableResult
    func stop() -> TimeInterval {
        guard var s = state else { return 0 }
        s.accumulated = elapsed()
        s.running = false
        s.finished = true
        state = s
        save()
        return s.accumulated
    }

    func clear() {
        state = nil
        defaults.removeObject(forKey: key)
    }

    func tick(now: Date = Date()) {
        if var s = state, !s.demo, !s.finished, s.date != Clock.dayID(now) {
            s.accumulated = elapsed(now: now)
            s.running = false
            s.finished = true
            state = s
            save()
        }
        if state?.running == true { beat &+= 1 }
    }

    static func format(_ seconds: TimeInterval) -> String {
        let s = Int(seconds), h = s / 3600
        let tail = String(format: "%02d:%02d", (s / 60) % 60, s % 60)
        return h > 0 ? String(format: "%02d:", h) + tail : tail
    }
}
