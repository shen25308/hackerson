import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Combine)
import Combine
#endif

// 联机夜谈的房间客户端。协议与网页版相同：
// POST /api/rooms、POST /api/rooms/{code}/join、GET /api/rooms/{code}、
// POST /api/rooms/{code}/action、POST /api/rooms/{code}/leave。
// 服务返回的房间数据按字典逐项读取，缺字段时的取值与网页端保持一致。

// MARK: 房间快照

struct RoomPlayer: Identifiable, Equatable {
    var id: String
    var seat: Int
    var nickname: String
    var alive: Bool
    var bot: Bool
    var hasStatement: Bool
    var hasVoted: Bool
}

struct RoomStatement: Identifiable, Equatable {
    var index: Int
    var playerId: String?
    var seat: Int?
    var text: String
    var tier: Int?
    var optionId: String?
    var id: Int { index }
}

struct RoomBallot: Identifiable, Equatable {
    var index: Int
    var voterId: String?
    var targetId: String?
    var id: Int { index }
}

struct RoomHistory: Identifiable, Equatable {
    var index: Int
    var round: Int
    var statements: [RoomStatement]
    var votes: [RoomBallot]
    var id: Int { index }
}

struct RoomOption: Identifiable, Equatable {
    var id: String
    var tier: Int
    var label: String
    var detail: String
}

struct RoomResult: Equatable {
    /// "villagers" 或 "wolf"，沿用服务端的取值。
    var winner: String?
    var reason: String
    var keeperId: String?
    var roles: [String: String]
}

struct RoomSelf: Equatable {
    var id: String
    var role: String?
    var tier: Int
    var completedCount: Int
    var options: [RoomOption]
    var hints: [String]
    var canStart: Bool
    var canStatement: Bool
    var canVote: Bool
    var nextActionAt: Double
}

struct RoomSnapshot: Equatable {
    static let stages = ["ready", "statement", "vote", "reveal", "finished"]

    var code: String
    var stage: String
    var round: Int?
    var voteAttempt: Int?
    var hostId: String?
    var phaseEndsAt: Double?
    var players: [RoomPlayer]
    var statements: [RoomStatement]
    var history: [RoomHistory]
    var votes: [RoomBallot]
    var revealText: String?
    var result: RoomResult?
    var me: RoomSelf

    func player(_ id: String?) -> RoomPlayer? {
        guard let id else { return nil }
        return players.first { $0.id == id }
    }

    func seatLabel(_ id: String?) -> String {
        player(id).map { "\($0.seat)号" } ?? "?号"
    }

    /// 结局公开后每一席的身份；没公开时是 nil。
    func role(of p: RoomPlayer) -> String? {
        guard let result else { return nil }
        if let role = result.roles[p.id], !role.isEmpty { return role }
        return result.keeperId == p.id ? "wolf" : "villager"
    }

    /// 当前轮之前的公开记录。
    var earlierRounds: [RoomHistory] {
        guard let round else { return [] }
        return history.filter { $0.round < round }
    }

    /// 发言选项：服务给的，加上还没解锁的几手（只展示，不能选）。
    func strategyRows() -> [RoomOption] {
        var list = me.options
        for i in Strategy.names.indices where i > me.tier && !list.contains(where: { $0.tier == i }) {
            list.append(RoomOption(id: "locked-\(i)", tier: i, label: Strategy.names[i],
                                   detail: "做完 \(Strategy.thresholds[i]) 项任务后，下次入座生效。"))
        }
        return list
    }

    /// 解析并检查房间数据。返回 nil 表示数据不完整。
    static func parse(_ raw: Any?) -> (room: RoomSnapshot, serverTime: Double?)? {
        guard let r = J.obj(raw) else { return nil }
        let code = J.str(r["code"]) ?? J.int(r["code"]).map { String($0) } ?? ""
        guard OnlineRoom.isRoomCode(code), let stage = J.str(r["stage"]), stages.contains(stage),
              let rawPlayers = J.arr(r["players"]), (1...5).contains(rawPlayers.count),
              let selfObj = J.obj(r["self"]), let selfId = J.str(selfObj["id"]) else { return nil }

        var players: [RoomPlayer] = []
        for item in rawPlayers {
            guard let p = J.obj(item), let id = J.str(p["id"]), let name = J.str(p["nickname"]) else { return nil }
            players.append(RoomPlayer(id: id, seat: J.int(p["seat"]) ?? 0, nickname: name, alive: truthy(p["alive"]),
                                      bot: truthy(p["bot"]), hasStatement: truthy(p["hasStatement"]), hasVoted: truthy(p["hasVoted"])))
        }

        var statements: [RoomStatement] = []
        if truthy(r["statements"]) {
            guard let list = J.arr(r["statements"]) else { return nil }
            for item in list {
                guard let s = J.obj(item), J.str(s["text"]) != nil else { return nil }
            }
            statements = readStatements(list)
        }

        var history: [RoomHistory] = []
        for (i, item) in (J.arr(r["history"]) ?? []).enumerated() {
            guard let h = J.obj(item), let round = J.int(h["round"]), let list = J.arr(h["statements"]) else { continue }
            history.append(RoomHistory(index: i, round: round, statements: readStatements(list), votes: readBallots(h["votes"])))
        }

        var result: RoomResult?
        if let o = J.obj(r["result"]) {
            var roles: [String: String] = [:]
            for item in J.arr(o["roles"]) ?? [] {
                if let x = J.obj(item), let pid = J.str(x["playerId"]), let role = J.str(x["role"]) { roles[pid] = role }
            }
            result = RoomResult(winner: J.str(o["winner"]), reason: J.str(o["reason"]) ?? "", keeperId: J.str(o["wolfId"]), roles: roles)
        }

        var options: [RoomOption] = []
        for item in J.arr(selfObj["options"]) ?? [] {
            guard let o = J.obj(item), let id = J.str(o["id"]) else { continue }
            options.append(RoomOption(id: id, tier: Int(number(o["tier"])), label: J.str(o["label"]) ?? "", detail: J.str(o["detail"]) ?? ""))
        }
        var hints: [String] = []
        for item in J.arr(selfObj["hints"]) ?? [] {
            let o = J.obj(item)
            let text = J.str(item) ?? nonEmpty(J.str(o?["text"])) ?? J.str(o?["detail"]) ?? ""
            if !text.isEmpty { hints.append(text) }
        }
        let me = RoomSelf(id: selfId, role: J.str(selfObj["role"]), tier: Int(number(selfObj["tier"])),
                          completedCount: Int(number(selfObj["completedCount"])), options: options, hints: hints,
                          canStart: truthy(selfObj["canStart"]), canStatement: truthy(selfObj["canStatement"]),
                          canVote: truthy(selfObj["canVote"]), nextActionAt: number(selfObj["nextActionAt"]))

        let reveal = J.obj(r["reveal"])
        let room = RoomSnapshot(code: code, stage: stage, round: J.int(r["round"]), voteAttempt: J.int(r["voteAttempt"]),
                                hostId: J.str(r["hostId"]), phaseEndsAt: J.num(r["phaseEndsAt"]), players: players,
                                statements: statements, history: history, votes: readBallots(r["votes"]),
                                revealText: reveal.map { J.str($0["text"]) ?? "" }, result: result, me: me)
        let clock = J.num(r["serverTime"])
        return (room, clock == 0 ? nil : clock)
    }

    private static func readStatements(_ list: [Any]) -> [RoomStatement] {
        var out: [RoomStatement] = []
        for (i, item) in list.enumerated() {
            guard let s = J.obj(item) else { continue }
            let seat = J.int(s["seat"])
            out.append(RoomStatement(index: i, playerId: J.str(s["playerId"]), seat: seat == 0 ? nil : seat,
                                     text: J.str(s["text"]) ?? "", tier: J.int(s["tier"]), optionId: J.str(s["optionId"])))
        }
        return out
    }

    private static func readBallots(_ raw: Any?) -> [RoomBallot] {
        var out: [RoomBallot] = []
        for (i, item) in (J.arr(raw) ?? []).enumerated() {
            guard let v = J.obj(item) else { continue }
            out.append(RoomBallot(index: i, voterId: J.str(v["voterId"]), targetId: nonEmpty(J.str(v["targetId"]))))
        }
        return out
    }

    private static func nonEmpty(_ s: String?) -> String? {
        guard let s, !s.isEmpty else { return nil }
        return s
    }

    /// 与网页端的“真值”判断一致：true、非零数字、非空字符串、对象和数组。
    private static func truthy(_ v: Any?) -> Bool {
        if let b = J.bool(v) { return b }
        if let n = J.num(v) { return n != 0 }
        if let s = J.str(v) { return !s.isEmpty }
        return J.obj(v) != nil || J.arr(v) != nil
    }

    private static func number(_ v: Any?) -> Double {
        if let n = J.num(v) { return n }
        if let s = J.str(v), let n = Double(s), n.isFinite { return n }
        return 0
    }
}

// MARK: 会话与动作

enum RoomLink: String {
    case disconnected, connecting, connected, offline
}

struct RoomSession: Equatable {
    var base: String
    var code: String
    var playerId: String
    var token: String
    var nickname: String
    var traceSession: String
}

struct RoomAction: Equatable {
    var type: String
    var optionId: String?
    var targetId: String?
    var nonce: String

    var json: JSON {
        var o: JSON = ["type": type, "nonce": nonce]
        if let optionId { o["optionId"] = optionId }
        if let targetId { o["targetId"] = targetId }
        return o
    }
}

/// 一次动作提交时的事实，用来在成功确认后写入行为回声。
struct RoomFacts: Equatable {
    var session: String
    var round: Int
    var roundRaw: Int?
    var voteAttempt: Int
    var completedCount: Int
    var unlockedTier: Int
    var strategyTier: Int?
    var strategyId: String?
    var strategyLabel: String?
    var targetSeat: Int?
}

enum RoomEvent {
    /// 建房或入座成功。
    case connected
    /// 校验、连接或动作失败（错误文字在 `error` 里）。
    case failed
    /// 已退出房间。
    case left
    /// 动作提交成功："start"、"statement" 或 "vote"。
    case acted(String)
    /// 房间进入了新的阶段。
    case stageChanged(stage: String, winner: String?)
    /// 服务确认了本人的一次发言或指认。只有这时才算数。
    case confirmed(RoomAction, RoomFacts)
}

struct RoomFailure: Error, Equatable {
    var message: String
    var httpStatus: Int?
    var cancelled = false

    static let timeout = RoomFailure(message: "连接超时，请检查服务地址和网络。")
    static let unreachable = RoomFailure(message: "连接失败，请检查服务是否运行、地址与网络。")
    static let unreadable = RoomFailure(message: "服务返回了无法读取的数据。")
}

// MARK: 客户端

final class OnlineRoom: ObservableObject {
    static let shared = OnlineRoom()

    @Published private(set) var session: RoomSession?
    @Published private(set) var room: RoomSnapshot?
    @Published private(set) var state: RoomLink = .disconnected
    @Published private(set) var error = ""
    @Published private(set) var busy = false
    @Published private(set) var pending: RoomAction?
    /// 连接表单里填的内容，换页后还在。
    @Published var draftBase = ""
    @Published var draftNickname = ""
    @Published var draftCode = ""

    /// 最近一次成功同步的时刻。
    private(set) var lastSync: Date?
    /// 最近一次同步时服务端的时钟（毫秒）。
    private(set) var serverTime: Double?
    /// 连接、动作、阶段变化的通知，总在主线程调用。
    var onEvent: ((RoomEvent) -> Void)?

    private let defaults: UserDefaults
    private let storageKey = "talk.session"
    private let network: URLSession
    private var inflight: [Int: (task: URLSessionDataTask, method: String)] = [:]
    private var counter = 0
    private var generation = 0
    private var readEpoch = 0
    private var polling = false
    private var active = false
    private var timer: DispatchWorkItem?
    private var pendingFacts: RoomFacts?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        network = URLSession(configuration: config)
        loadSession()
    }

    // MARK: 校验

    static func isRoomCode(_ code: String) -> Bool {
        code.unicodeScalars.count == 6 && code.unicodeScalars.allSatisfy { c in
            (c.value >= 65 && c.value <= 90) || (c.value >= 50 && c.value <= 57)
        }
    }

    /// 只接受服务的根地址，返回规范化后的 scheme://host[:port]。
    static func normalizeBase(_ value: String) throws -> String {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let c = URLComponents(string: text), let scheme = c.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = c.host, !host.isEmpty, c.user == nil, c.password == nil,
              (c.query ?? "").isEmpty, (c.fragment ?? "").isEmpty else {
            throw RoomFailure(message: "请填写 http:// 或 https:// 开头的服务地址。")
        }
        var path = c.path
        if path.hasSuffix("/") { path.removeLast() }
        if path.hasSuffix("/api") { path.removeLast(4) }
        guard path.isEmpty else { throw RoomFailure(message: "请填写服务的根地址，例如 https://你的服务地址。") }
        var name = host.lowercased()
        if name.contains(":") && !name.hasPrefix("[") { name = "[" + name + "]" }
        var origin = scheme + "://" + name
        if let port = c.port, !((scheme == "http" && port == 80) || (scheme == "https" && port == 443)) {
            origin += ":\(port)"
        }
        return origin
    }

    private static func isTraceSession(_ s: String) -> Bool {
        (1...100).contains(s.unicodeScalars.count) && s.unicodeScalars.allSatisfy { c in
            (c.value >= 48 && c.value <= 57) || (c.value >= 65 && c.value <= 90) || (c.value >= 97 && c.value <= 122)
                || c == "_" || c == "." || c == ":" || c == "-"
        }
    }

    // MARK: 本机凭证

    private func loadSession() {
        guard let o = defaults.dictionary(forKey: storageKey),
              let code = o["code"] as? String, OnlineRoom.isRoomCode(code),
              let token = o["token"] as? String, !token.isEmpty, token.count < 500,
              let playerId = o["playerId"] as? String,
              let base = o["base"] as? String, (try? OnlineRoom.normalizeBase(base)) == base else { return }
        var trace = o["traceSession"] as? String ?? ""
        let kept = OnlineRoom.isTraceSession(trace)
        if !kept { trace = newID() }
        let nickname = o["nickname"] as? String ?? ""
        session = RoomSession(base: base, code: code, playerId: playerId, token: token, nickname: nickname, traceSession: trace)
        if !kept { saveSession() }
        draftBase = base
        draftNickname = nickname
    }

    private func saveSession() {
        guard let s = session else {
            defaults.removeObject(forKey: storageKey)
            return
        }
        defaults.set(["base": s.base, "code": s.code, "playerId": s.playerId, "token": s.token,
                      "nickname": s.nickname, "traceSession": s.traceSession], forKey: storageKey)
    }

    /// 丢掉房间和凭证，回到未连接。进出示例、导入备份时也要调用。
    func resetSession() {
        generation += 1
        timer?.cancel()
        timer = nil
        for entry in inflight.values { entry.task.cancel() }
        inflight.removeAll()
        polling = false
        pendingFacts = nil
        lastSync = nil
        serverTime = nil
        if session != nil { session = nil }
        if room != nil { room = nil }
        if state != .disconnected { state = .disconnected }
        if !error.isEmpty { error = "" }
        if busy { busy = false }
        if pending != nil { pending = nil }
        saveSession()
    }

    // MARK: 时钟

    /// 估算的服务端当前时刻（毫秒）。
    func serverNow(now: Date = Date()) -> Double {
        let ms = now.timeIntervalSince1970 * 1000
        return (serverTime ?? ms) + (lastSync.map { ms - $0.timeIntervalSince1970 * 1000 } ?? 0)
    }

    /// 当前阶段还剩几秒；没有倒计时或同步中断时是 nil。
    func secondsLeft(now: Date = Date()) -> Int? {
        guard let r = room, r.stage != "ready", r.stage != "finished", state == .connected, let end = r.phaseEndsAt else { return nil }
        let left = ((end - serverNow(now: now)) / 1000).rounded(.up)
        guard left.isFinite else { return nil }
        return Int(max(0, min(86_400, left)))
    }

    func clockText(now: Date = Date()) -> String {
        guard let r = room, r.stage != "ready", r.stage != "finished" else { return "" }
        if state != .connected { return "已暂停同步" }
        return secondsLeft(now: now).map { "\($0) 秒" } ?? ""
    }

    /// 现在能不能提交动作：连着、没在忙、没有悬着的动作、冷却已过。
    func canPlay(now: Date = Date()) -> Bool {
        guard let r = room else { return false }
        return state == .connected && !busy && pending == nil && r.me.nextActionAt <= serverNow(now: now)
    }

    // MARK: 轮询

    /// 页面可见时传 true 开始轮询，隐藏时传 false 停下。
    func start(active value: Bool = true) {
        active = value
        if value {
            schedule()
        } else {
            timer?.cancel()
            timer = nil
            abortReads()
        }
    }

    func stop() {
        start(active: false)
    }

    private func abortReads() {
        readEpoch += 1
        for entry in inflight.values where entry.method == "GET" { entry.task.cancel() }
    }

    private func schedule() {
        timer?.cancel()
        timer = nil
        guard session != nil, room != nil, active else { return }
        let work = DispatchWorkItem { [weak self] in self?.poll() }
        timer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    private func poll(then done: (() -> Void)? = nil) {
        guard session != nil, !busy, !polling, active else {
            schedule()
            done?()
            return
        }
        polling = true
        let g = generation, epoch = readEpoch
        request(endpoint(""), auth: true) { [weak self] result in
            guard let self else { return }
            if g == self.generation, epoch == self.readEpoch {
                do {
                    try self.accept(result.get())
                } catch {
                    if self.active {
                        let message = (error as? RoomFailure)?.message ?? RoomFailure.unreachable.message
                        if self.state != .offline { self.state = .offline }
                        if self.error != message { self.error = message }
                    }
                }
            }
            if g == self.generation {
                self.polling = false
                self.schedule()
            }
            done?()
        }
    }

    /// 重新向服务读取房间。恢复凭证后、或连接中断时调用。
    func reconnect(then done: (() -> Void)? = nil) {
        guard session != nil, !busy else {
            done?()
            return
        }
        if !error.isEmpty { error = "" }
        poll(then: done)
    }

    /// 上次动作结果没确认时，恢复连接后用同一个凭证重发，服务不会重复计入。
    func retryPending() {
        guard pending != nil, session != nil, !busy else { return }
        reconnect { [weak self] in
            guard let self, let p = self.pending, self.state == .connected else { return }
            self.act(p.type, optionId: p.optionId, targetId: p.targetId)
        }
    }

    // MARK: 建房、入座、动作、退出

    /// 用表单里的地址和昵称建房；join 为 true 时用房间码入座。
    func connect(join: Bool, completedCount: Int) {
        guard !busy else { return }
        let nickname = draftNickname.trimmingCharacters(in: .whitespacesAndNewlines)
        let code = draftCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let base: String
        do {
            base = try OnlineRoom.normalizeBase(draftBase)
            if nickname.isEmpty { throw RoomFailure(message: "先给自己起个名字。") }
            if join && !OnlineRoom.isRoomCode(code) { throw RoomFailure(message: "房间码需要六位大写字母或数字（2—9）。") }
        } catch {
            self.error = (error as? RoomFailure)?.message ?? RoomFailure.unreachable.message
            onEvent?(.failed)
            return
        }
        busy = true
        state = .connecting
        self.error = ""
        generation += 1
        let g = generation
        let name = String(nickname.prefix(20))
        let target = base + "/api/rooms" + (join ? "/" + code + "/join" : "")
        let body: JSON = ["nickname": name, "character": ["completedCount": max(0, completedCount)]]
        request(target, method: "POST", body: body) { [weak self] result in
            guard let self, g == self.generation else { return }
            do {
                let d = try result.get()
                guard let playerId = J.str(d["playerId"]), !playerId.isEmpty, let token = J.str(d["token"]), !token.isEmpty,
                      let parsed = RoomSnapshot.parse(d["room"]) else {
                    throw RoomFailure(message: "服务没有返回有效的房间凭证。")
                }
                self.session = RoomSession(base: base, code: parsed.room.code, playerId: playerId, token: token,
                                           nickname: name, traceSession: newID())
                self.saveSession()
                try self.accept(d)
                self.onEvent?(.connected)
            } catch {
                self.state = .disconnected
                self.error = (error as? RoomFailure)?.message ?? RoomFailure.unreachable.message
                self.onEvent?(.failed)
            }
            self.busy = false
            self.schedule()
        }
    }

    /// 提交一次动作：type 是 "start"、"statement"（带 optionId）或 "vote"（带 targetId）。
    func act(_ type: String, optionId: String? = nil, targetId: String? = nil) {
        guard session != nil, !busy, state == .connected, let r = room else { return }
        let me = r.me
        if pending == nil && me.nextActionAt > serverNow() { return }
        if (type == "start" && !me.canStart) || (type == "statement" && !me.canStatement) || (type == "vote" && !me.canVote) { return }
        abortReads()
        let body = pending ?? RoomAction(type: type, optionId: optionId, targetId: targetId, nonce: newID())
        if pending == nil { pendingFacts = facts(r, body) }
        let meta = pendingFacts
        pending = body
        busy = true
        let g = generation
        request(endpoint("/action"), method: "POST", body: body.json, auth: true) { [weak self] result in
            guard let self, g == self.generation else { return }
            do {
                try self.accept(result.get())
                if let meta, body.type == "statement" || body.type == "vote" { self.onEvent?(.confirmed(body, meta)) }
                self.pending = nil
                self.pendingFacts = nil
                self.onEvent?(.acted(body.type))
            } catch {
                let failure = error as? RoomFailure
                self.error = failure?.message ?? RoomFailure.unreachable.message
                self.state = failure?.httpStatus != nil ? .connected : .offline
                if failure?.httpStatus != nil {
                    self.pending = nil
                    self.pendingFacts = nil
                }
                self.onEvent?(.failed)
            }
            self.busy = false
            self.schedule()
        }
    }

    func leave() {
        guard !busy else { return }
        busy = true
        let g = generation
        let finish: () -> Void = { [weak self] in
            guard let self, g == self.generation else { return }
            self.resetSession()
            self.onEvent?(.left)
        }
        guard session != nil else {
            finish()
            return
        }
        request(endpoint("/leave"), method: "POST", body: [:], auth: true) { _ in finish() }
    }

    // MARK: 内部

    private func endpoint(_ path: String) -> String {
        guard let s = session else { return "" }
        return s.base + "/api/rooms/" + s.code + path
    }

    private func facts(_ r: RoomSnapshot, _ body: RoomAction) -> RoomFacts {
        let me = r.me
        let said = r.statements.first { $0.playerId == me.id }
        let option = body.optionId.flatMap { id in me.options.first { $0.id == id } }
        let speaking = body.type == "statement"
        let attempt = r.voteAttempt ?? 0
        return RoomFacts(session: session?.traceSession ?? "", round: r.round ?? 1, roundRaw: r.round,
                         voteAttempt: attempt == 0 ? 1 : attempt, completedCount: max(0, me.completedCount),
                         unlockedTier: min(3, max(0, me.tier)),
                         strategyTier: speaking ? option?.tier : said?.tier,
                         strategyId: speaking ? option?.id : said?.optionId,
                         strategyLabel: speaking ? option?.label : nil,
                         targetSeat: r.player(body.targetId)?.seat)
    }

    /// 接受一份新的房间数据。数据不完整时抛出错误，原有房间保持不变。
    private func accept(_ data: JSON) throws {
        guard let parsed = RoomSnapshot.parse(data["room"]) else {
            throw RoomFailure(message: "服务房间数据不完整，请检查服务版本。")
        }
        let old = room
        let next = parsed.room
        serverTime = parsed.serverTime
        lastSync = Date()
        if state != .connected { state = .connected }
        if !error.isEmpty { error = "" }
        if let p = pending {
            let me = next.player(next.me.id)
            let m = pendingFacts
            let settled: Bool
            switch p.type {
            case "start":
                settled = next.stage != "ready"
            case "statement":
                settled = me?.hasStatement == true || next.stage != "statement" || next.round != m?.roundRaw
            case "vote":
                settled = me?.hasVoted == true || next.stage != "vote" || next.round != m?.roundRaw || next.voteAttempt != m?.voteAttempt
            default:
                settled = false
            }
            if settled {
                pending = nil
                pendingFacts = nil
            }
        }
        if old != next { room = next }
        if let old, old.stage != next.stage {
            onEvent?(.stageChanged(stage: next.stage, winner: next.result?.winner))
        }
    }

    private func request(_ target: String, method: String = "GET", body: JSON? = nil, auth: Bool = false,
                         completion: @escaping (Result<JSON, RoomFailure>) -> Void) {
        guard let url = URL(string: target), url.host != nil else {
            DispatchQueue.main.async { completion(.failure(.unreachable)) }
            return
        }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.httpMethod = method
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        if auth, let token = session?.token {
            req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        }
        counter += 1
        let key = counter
        let task = network.dataTask(with: req) { [weak self] data, response, failure in
            let result = OnlineRoom.interpret(data, response, failure)
            DispatchQueue.main.async { [weak self] in
                self?.inflight[key] = nil
                completion(result)
            }
        }
        inflight[key] = (task, method)
        task.resume()
    }

    private static func interpret(_ data: Data?, _ response: URLResponse?, _ failure: Error?) -> Result<JSON, RoomFailure> {
        if let failure {
            let code = (failure as? URLError)?.code
            if code == .cancelled { return .failure(RoomFailure(message: RoomFailure.timeout.message, cancelled: true)) }
            return .failure(code == .timedOut ? .timeout : .unreachable)
        }
        guard let data, let parsed = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return .failure(.unreadable)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let object = J.obj(parsed) ?? [:]
        guard (200..<300).contains(status) else {
            let message = J.str(object["error"])
                ?? J.str(J.obj(object["error"])?["message"])
                ?? J.str(object["message"])
                ?? "服务拒绝了请求（\(status)）。"
            return .failure(RoomFailure(message: message, httpStatus: status))
        }
        return .success(object)
    }
}
