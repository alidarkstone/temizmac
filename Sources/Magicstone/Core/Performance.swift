import Foundation
import AppKit

/// Geri alınabilir sistem ayarı. Önceki değer saklanır; "Geri Al" onu geri yazar (yoksa anahtarı siler).
struct Tweak: Identifiable, Hashable {
    enum Kind: String { case bool, float, int }
    let id: String
    let group: String
    let title: String
    let detail: String
    let domain: String
    let key: String
    let kind: Kind
    let value: String
    var admin: Bool = false
    var restart: String? = nil   // ör. "Dock", "Finder"
    var sideEffect: String? = nil
    var applied: Bool = false
}

enum Performance {
    static let tweaks: [Tweak] = [
        Tweak(id: "reduceMotion", group: "Görsel efektler", title: "Hareketi azalt",
              detail: "Masaüstü geçişlerinde kayma yerine solma kullanılır.",
              domain: "com.apple.universalaccess", key: "reduceMotion", kind: .bool, value: "true", sideEffect: "Masaüstü geçişleri kayma yerine solarak olur."),
        Tweak(id: "reduceTransparency", group: "Görsel efektler", title: "Saydamlığı azalt",
              detail: "Bulanık arka planlar kapanır; GPU yükü azalır.",
              domain: "com.apple.universalaccess", key: "reduceTransparency", kind: .bool, value: "true", sideEffect: "Menü çubuğu, Dock ve kenar çubukları opak (düz renk) görünür."),
        Tweak(id: "windowAnim", group: "Görsel efektler", title: "Pencere açılış animasyonunu kapat",
              detail: "Yeni pencereler anında açılır.",
              domain: "NSGlobalDomain", key: "NSAutomaticWindowAnimationsEnabled", kind: .bool, value: "false"),
        Tweak(id: "resizeTime", group: "Görsel efektler", title: "Pencere boyutlandırmayı hızlandır",
              detail: "Kaydet/Aç panelleri gecikmesiz açılır.",
              domain: "NSGlobalDomain", key: "NSWindowResizeTime", kind: .float, value: "0.001"),
        Tweak(id: "finderAnim", group: "Görsel efektler", title: "Finder animasyonlarını kapat",
              detail: "Bilgi Al ve klasör geçişleri animasyonsuz.",
              domain: "com.apple.finder", key: "DisableAllAnimations", kind: .bool, value: "true", restart: "Finder"),
        Tweak(id: "dockLaunch", group: "Dock", title: "Açılışta zıplamayı kapat",
              detail: "Uygulama başlarken Dock simgesi zıplamaz.",
              domain: "com.apple.dock", key: "launchanim", kind: .bool, value: "false", restart: "Dock"),
        Tweak(id: "dockDelay", group: "Dock", title: "Dock gizleme gecikmesini kaldır",
              detail: "Otomatik gizlenen Dock anında görünür.",
              domain: "com.apple.dock", key: "autohide-delay", kind: .float, value: "0", restart: "Dock"),
        Tweak(id: "exposeSpeed", group: "Dock", title: "Mission Control'ü hızlandır",
              detail: "Mission Control animasyonu kısalır.",
              domain: "com.apple.dock", key: "expose-animation-duration", kind: .float, value: "0.1", restart: "Dock"),
        Tweak(id: "analytics", group: "Gizlilik (telemetri)", title: "Apple'a analiz verisi gönderme",
              detail: "Mac Analizleri'ni paylaş seçeneğini kapatır.",
              domain: "/Library/Application Support/CrashReporter/DiagnosticMessagesHistory",
              key: "AutoSubmit", kind: .bool, value: "false", admin: true, sideEffect: "Apple, sizin Mac'inizdeki hatalardan haberdar olmaz; yalnızca gizlilik kazancı, işlev kaybı yok."),
        Tweak(id: "thirdParty", group: "Gizlilik (telemetri)", title: "Geliştiricilerle çökme verisi paylaşma",
              detail: "Uygulama geliştiricilerine kilitlenme raporu gönderilmez.",
              domain: "/Library/Application Support/CrashReporter/DiagnosticMessagesHistory",
              key: "ThirdPartyDataSubmit", kind: .bool, value: "false", admin: true, sideEffect: "Geliştiriciler çökme raporlarınızı görmez; hata düzeltmeleri gecikebilir."),
        Tweak(id: "lookupSuggestions", group: "Gizlilik (telemetri)", title: "Spotlight/Sorgula önerilerini kapat",
              detail: "Arama sorguları öneri için Apple'a gönderilmez.",
              domain: "com.apple.lookup.shared", key: "LookupSuggestionsDisabled", kind: .bool, value: "true", sideEffect: "Spotlight'ta web/Siri önerileri görünmez; yerel arama çalışmaya devam eder."),
        Tweak(id: "personalAds", group: "Gizlilik (telemetri)", title: "Kişiselleştirilmiş Apple reklamlarını kapat",
              detail: "Apple reklam kişiselleştirmesi devre dışı.",
              domain: "com.apple.AdLib", key: "allowApplePersonalizedAdvertising", kind: .bool, value: "false", sideEffect: "App Store/News reklamları sizinle daha az ilgili olur; reklam sayısı azalmaz.")
    ]

    // MARK: Önceki değer deposu

    static let stateURL = SafetyGuard.home.appendingPathComponent("Library/Application Support/Magicstone/tweaks.plist")

    /// id → önceki değer ("" = anahtar yoktu)
    static func loadState() -> [String: String] {
        (NSDictionary(contentsOf: stateURL) as? [String: String]) ?? [:]
    }
    static func saveState(_ s: [String: String]) {
        try? FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        (s as NSDictionary).write(to: stateURL, atomically: true)
    }

    // MARK: defaults

    static func read(_ t: Tweak) -> String? {
        let (ok, out) = Maintenance.runUser("/usr/bin/defaults read \(q(t.domain)) \(q(t.key))")
        return ok ? out.trimmingCharacters(in: .whitespacesAndNewlines) : nil
    }

    static func isApplied(_ t: Tweak) -> Bool {
        guard let v = read(t) else { return false }
        switch t.kind {
        case .bool: return (v == "1") == (t.value == "true")
        case .float, .int: return Double(v) == Double(t.value)
        }
    }

    private static func writeCmd(_ t: Tweak, value: String, kind: Tweak.Kind) -> String {
        "/usr/bin/defaults write \(q(t.domain)) \(q(t.key)) -\(kind.rawValue) \(q(value))"
    }
    private static func deleteCmd(_ t: Tweak) -> String {
        "/usr/bin/defaults delete \(q(t.domain)) \(q(t.key))"
    }

    /// Ayarları uygular; önceki değerleri saklar. Dönüş: hata mesajları.
    static func apply(_ list: [Tweak]) -> [String] {
        var state = loadState()
        var userCmds: [(Tweak, String)] = [], adminCmds: [String] = []
        for t in list {
            if state[t.id] == nil {
                let prev = read(t)
                state[t.id] = prev.map { t.kind == .bool ? ($0 == "1" ? "true" : "false") : $0 } ?? ""
            }
            let c = writeCmd(t, value: t.value, kind: t.kind)
            if t.admin { adminCmds.append(c) } else { userCmds.append((t, c)) }
        }
        saveState(state)
        return execute(userCmds, adminCmds, restarts: Set(list.compactMap(\.restart)))
    }

    /// Önceki değerleri geri yükler.
    static func revert(_ list: [Tweak]) -> [String] {
        var state = loadState()
        var userCmds: [(Tweak, String)] = [], adminCmds: [String] = []
        for t in list {
            guard let prev = state[t.id] else { continue }
            let c = prev.isEmpty ? deleteCmd(t) : writeCmd(t, value: prev, kind: t.kind)
            if t.admin { adminCmds.append(c) } else { userCmds.append((t, c)) }
            state[t.id] = nil
        }
        saveState(state)
        return execute(userCmds, adminCmds, restarts: Set(list.compactMap(\.restart)))
    }

    private static func execute(_ user: [(Tweak, String)], _ admin: [String], restarts: Set<String>) -> [String] {
        var errors: [String] = []
        for (t, c) in user {
            let (ok, out) = Maintenance.runUser(c)
            Maintenance.log("\(ok ? "OK" : "FAIL") tweak \(t.id): \(c)")
            if !ok { errors.append("\(t.title): \(out.trimmingCharacters(in: .whitespacesAndNewlines))") }
        }
        if !admin.isEmpty {
            let script = admin.joined(separator: "; ")
            let err = Cleaner.runAppleScript("do shell script \(Cleaner.asLiteral(script)) with administrator privileges")
            Maintenance.log("\(err == nil ? "OK" : "FAIL") admin tweaks: \(script)")
            if let err { errors.append(err) }
        }
        for p in restarts { _ = Maintenance.runUser("/usr/bin/killall \(q(p))") }
        return errors
    }

    static func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    // MARK: Üçüncü taraf başlangıç ajanları (launchctl disable — geri alınabilir)

    struct Agent: Identifiable, Hashable {
        let id: String      // label
        let plist: URL
        var enabled: Bool
        /// Güncelleyici olup ait olduğu uygulama artık kurulu değilse true.
        var parentMissing: Bool = false
    }

    static func agents() -> [Agent] {
        let uid = getuid()
        let (_, out) = Maintenance.runUser("/bin/launchctl print-disabled gui/\(uid)")
        var disabled = Set<String>()
        for line in out.split(separator: "\n") {
            let l = line.trimmingCharacters(in: .whitespaces)
            guard l.hasPrefix("\""), l.contains("=> disabled") || l.contains("=> true") else { continue }
            if let end = l.dropFirst().firstIndex(of: "\"") { disabled.insert(String(l[l.index(after: l.startIndex)..<end])) }
        }
        let dirs = [LaunchAgents.userDir, URL(fileURLWithPath: "/Library/LaunchAgents")]
        let installed = OrphanScanner.installedBundleIDs().filter { !OrphanScanner.isUpdater($0) }
        var out2: [Agent] = []
        for dir in dirs {
            guard let list = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for u in list where u.pathExtension == "plist" {
                let label = (NSDictionary(contentsOf: u)?["Label"] as? String) ?? u.deletingPathExtension().lastPathComponent
                if label.hasPrefix("com.apple.") { continue }
                var missing = false
                if OrphanScanner.isUpdater(label) {
                    let l = label.lowercased()
                    if l.hasPrefix("com.oracle.java") {
                        missing = !FileManager.default.fileExists(atPath: "/Library/Internet Plug-Ins/JavaAppletPlugin.plugin")
                    } else {
                        let vendor = l.split(separator: ".").prefix(2).joined(separator: ".")
                        missing = !installed.contains { $0.hasPrefix(vendor + ".") }
                    }
                }
                out2.append(Agent(id: label, plist: u, enabled: !disabled.contains(label), parentMissing: missing))
            }
        }
        return out2.sorted { $0.id < $1.id }
    }

    static func setAgent(_ a: Agent, enabled: Bool) -> Bool {
        let target = "gui/\(getuid())"
        let cmd = enabled
            ? "/bin/launchctl enable \(target)/\(q(a.id)); /bin/launchctl bootstrap \(target) \(q(a.plist.path)) 2>/dev/null; true"
            : "/bin/launchctl disable \(target)/\(q(a.id)); /bin/launchctl bootout \(target)/\(q(a.id)) 2>/dev/null; true"
        let (ok, _) = Maintenance.runUser(cmd)
        Maintenance.log("\(ok ? "OK" : "FAIL") agent \(enabled ? "enable" : "disable") \(a.id)")
        return ok
    }

    // MARK: Kaynak tüketen süreçler

    struct Proc: Identifiable, Hashable {
        let id: Int32
        let cpu: Double
        let memMB: Double
        let name: String
    }

    static func topProcesses(byMemory: Bool, limit: Int = 10) -> [Proc] {
        let (_, out) = Maintenance.runUser("/bin/ps -Aceo pid=,pcpu=,rss=,comm= \(byMemory ? "-m" : "-r")")
        var res: [Proc] = []
        for line in out.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count == 4, let pid = Int32(parts[0]), let cpu = Double(parts[1]), let rss = Double(parts[2])
            else { continue }
            res.append(Proc(id: pid, cpu: cpu, memMB: rss / 1024, name: String(parts[3])))
            if res.count >= limit { break }
        }
        return res
    }
}
