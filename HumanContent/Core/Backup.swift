import Foundation

struct BackupError: Error, Equatable {
    let message: String
    static let unreadable = BackupError(message: "这份文件不是可读取的人类含量备份。")
    static let tooLarge = BackupError(message: "备份需要是 2 MB 以内的 JSON 文件。")
}

/// 导入前的结构检查，规则与网页版一致。
enum Backup {
    static let maxBytes = 2 * 1024 * 1024

    static func validate(_ data: Data) throws -> Ledger {
        guard data.count <= maxBytes else { throw BackupError.tooLarge }
        guard let raw = try? JSONSerialization.jsonObject(with: data), let v = J.obj(raw) else { throw BackupError.unreadable }
        func fail() -> BackupError { .unreadable }
        func str(_ x: Any?, _ max: Int) -> Bool { (J.str(x)?.count ?? Int.max) <= max }
        func optStr(_ x: Any?, _ max: Int) -> Bool { x == nil || str(x, max) }
        func num(_ x: Any?, _ max: Double = 1e12) -> Bool {
            guard let d = J.num(x) else { return false }
            return d >= 0 && d <= max
        }
        func ident(_ x: Any?) -> Bool {
            guard let s = J.str(x), (1...100).contains(s.count) else { return false }
            return s.unicodeScalars.allSatisfy { c in
                (c.value >= 48 && c.value <= 57) || (c.value >= 65 && c.value <= 90) || (c.value >= 97 && c.value <= 122) || c == "_" || c == "-"
            }
        }
        func date(_ x: Any?) -> Bool {
            guard let s = J.str(x), s.count == 10 else { return false }
            let p = s.split(separator: "-", omittingEmptySubsequences: false)
            guard p.count == 3, p[0].count == 4, p[1].count == 2, p[2].count == 2,
                  let y = Int(p[0]), let m = Int(p[1]), let d = Int(p[2]), (1...12).contains(m), d >= 1 else { return false }
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(identifier: "UTC") ?? cal.timeZone
            guard let first = cal.date(from: DateComponents(year: y, month: m, day: 1)),
                  let range = cal.range(of: .day, in: .month, for: first) else { return false }
            return d <= range.count
        }

        guard J.int(v["version"]) == 1, let role = J.str(v["role"]), RoleID(rawValue: role) != nil,
              let days = J.arr(v["days"]), !days.isEmpty, days.count <= 10000,
              let cards = J.arr(v["cards"]), let events = J.arr(v["events"]),
              ["hp", "xp", "attack", "magic", "streak", "draws", "lastSwitchXP"].allSatisfy({ num(v[$0]) }),
              (J.num(v["hp"]) ?? 101) <= 100, (J.num(v["lastSwitchXP"]) ?? 1) <= (J.num(v["xp"]) ?? 0)
        else { throw fail() }

        var seen = Set<String>()
        var previous = ""
        for raw in days {
            guard let d = J.obj(raw), date(d["id"]), let id = J.str(d["id"]), id > previous,
                  let tasks = J.arr(d["tasks"]), J.isBool(d["closed"]), num(d["loss"], 100), num(d["awarded"]),
                  optStr(d["reflection"], 1200) else { throw fail() }
            previous = id
            for rawTask in tasks {
                guard let t = J.obj(rawTask), ident(t["id"]), let tid = J.str(t["id"]), !seen.contains(tid),
                      let title = J.str(t["title"]), title.count <= 300,
                      !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      num(t["estimate"], 10080), (J.num(t["estimate"]) ?? 0) >= 1,
                      J.isBool(t["done"]), J.isBool(t["bonus"]), num(t["earned"]), num(t["healed"], 100),
                      t["actual"] is NSNull || num(t["actual"], 10080),
                      let rounds = J.obj(t["rounds"]),
                      t["topic"] == nil || [0, 1, 2].contains(J.int(t["topic"]) ?? -1),
                      t["seed"] == nil || [0, 1, 2].contains(J.int(t["seed"]) ?? -1),
                      t["prep"] == nil || num(t["prep"]),
                      ["original", "step", "context", "decision"].allSatisfy({ optStr(t[$0], 1200) })
                else { throw fail() }
                seen.insert(tid)
                for (n, rawRound) in rounds {
                    guard ["0", "1", "2"].contains(n), let r = J.obj(rawRound),
                          r["vote"] == nil || [0, 1, 2].contains(J.int(r["vote"]) ?? -1),
                          optStr(r["answer"], 300),
                          r["inspect"] == nil || J.isBool(r["inspect"])
                    else { throw fail() }
                    if let s = r["suspects"] {
                        guard let list = J.arr(s), list.count <= 3, list.allSatisfy({ [0, 1, 2].contains(J.int($0) ?? -1) }) else { throw fail() }
                    }
                    if let rep = r["replies"] {
                        guard let o = J.obj(rep), o.allSatisfy({ ["0", "1", "2"].contains($0.key) && str($0.value, 300) }) else { throw fail() }
                    }
                }
            }
        }
        for raw in cards {
            guard let c = J.obj(raw), ident(c["id"]), date(c["date"]), str(c["name"], 100), str(c["effect"], 100),
                  [0, 1, 2].contains(J.int(c["kind"]) ?? -1) else { throw fail() }
        }
        for raw in events {
            guard let e = J.obj(raw), ident(e["id"]), date(e["date"]), str(e["time"], 40), str(e["type"], 50), str(e["text"], 4000),
                  e["task"] == nil || e["task"] is NSNull || ident(e["task"]) else { throw fail() }
            if let recs = e["records"] {
                guard let list = J.arr(recs), list.count <= 12, list.allSatisfy({ item in
                    guard let o = J.obj(item) else { return false }
                    return ["level", "label", "text", "note"].allSatisfy { optStr(o[$0], 1200) }
                }) else { throw fail() }
            }
        }
        if let g = v["game"], J.obj(g) == nil { throw fail() }
        guard let ledger = Ledger(json: v) else { throw fail() }
        return ledger
    }

    static func filename(demo: Bool, today: String) -> String {
        "人类含量-\(demo ? "示例-" : "")\(today).json"
    }
}
