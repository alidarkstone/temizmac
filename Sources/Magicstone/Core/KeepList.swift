import Foundation

/// "Dokunma" listesi: kullanıcının tuttuğu yollar bir daha listelenmez ve asla taşınmaz.
enum KeepList {
    static let url = SafetyGuard.home.appendingPathComponent("Library/Application Support/Magicstone/keep.txt")
    private static let lock = NSLock()
    private static var cache: Set<String>?

    static var all: Set<String> {
        lock.lock(); defer { lock.unlock() }
        if let c = cache { return c }
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let set = Set(text.split(separator: "\n").map(String.init).filter { !$0.isEmpty })
        cache = set
        return set
    }

    static func contains(_ u: URL) -> Bool { all.contains(u.standardizedFileURL.path) }

    static func add(_ u: URL) {
        var s = all
        s.insert(u.standardizedFileURL.path)
        save(s)
    }

    static func remove(_ path: String) {
        var s = all
        s.remove(path)
        save(s)
    }

    private static func save(_ s: Set<String>) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? (s.sorted().joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        lock.lock(); cache = s; lock.unlock()
    }
}
