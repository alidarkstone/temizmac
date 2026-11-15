import Foundation

struct InstalledApp: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let name: String
    let bundleID: String?
    let size: Int64
}

/// Uygulama kaldırıcı: .app paketini ve kullanıcı + sistem kitaplığındaki tüm artıklarını bulur.
enum Uninstaller {
    static let appDirs = [URL(fileURLWithPath: "/Applications"),
                          SafetyGuard.home.appendingPathComponent("Applications")]

    static func installedApps() -> [InstalledApp] {
        let fm = FileManager.default
        var out: [InstalledApp] = []
        for dir in appDirs {
            guard let list = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for u in list where u.pathExtension == "app" {
                let bid = Bundle(url: u)?.bundleIdentifier
                if let bid, bid.hasPrefix("com.apple.") { continue } // sistem uygulamalarını gösterme
                out.append(InstalledApp(url: u, name: u.deletingPathExtension().lastPathComponent,
                                        bundleID: bid, size: DiskScanner.allocatedSize(of: u)))
            }
        }
        return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Kullanıcı kitaplığında aranan alt klasörler.
    static let userSubdirs = [
        "Application Support", "Caches", "Preferences", "Preferences/ByHost", "Logs",
        "Saved Application State", "Containers", "Group Containers", "HTTPStorages", "WebKit",
        "LaunchAgents", "Application Scripts", "Internet Plug-Ins", "PreferencePanes",
        "Services", "QuickLook", "Spotlight", "Screen Savers", "Logs/DiagnosticReports"
    ]

    /// Sistem kitaplığında aranan klasörler (kaldırmak için yönetici izni gerekir).
    static let systemDirs = [
        "/Library/Application Support", "/Library/Caches", "/Library/Preferences",
        "/Library/LaunchAgents", "/Library/LaunchDaemons", "/Library/PrivilegedHelperTools",
        "/Library/Logs", "/private/var/db/receipts"
    ]

    /// Uygulamanın kod imzasındaki geliştirici ekip kimliği (ör. "ABCDE12345").
    static func teamID(of app: URL) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        p.arguments = ["-dv", "--verbose=2", app.path]
        let pipe = Pipe()
        p.standardError = pipe
        p.standardOutput = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        for line in text.split(separator: "\n") where line.hasPrefix("TeamIdentifier=") {
            let v = String(line.dropFirst("TeamIdentifier=".count))
            return v == "not set" ? nil : v
        }
        return nil
    }

    /// Eşleşme gücü: bundle ID ile eşleşenler güvenlidir ve seçili gelir;
    /// yalnızca adla / ekip kimliğiyle eşleşenler kontrol için seçilmeden listelenir.
    private enum Match { case strong, weak }

    private static func match(_ fileName: String, bid: String?, team: String?, name: String) -> Match? {
        let n = fileName.lowercased()
        let base = (n as NSString).deletingPathExtension
        if let b = bid?.lowercased(), b.count >= 4 {
            if base == b || n.hasPrefix(b + ".") || n.hasPrefix(b + "-") || n.hasPrefix(b + "_") { return .strong }
            // Group Containers: "TEAMID.com.firma.uygulama", "group.com.firma.uygulama"
            if n.hasSuffix("." + b) || n.contains("." + b + ".") { return .strong }
        }
        if let t = team?.lowercased(), n.hasPrefix(t + ".") { return .weak }
        let nm = name.lowercased()
        if nm.count >= 4, base == nm || n.hasPrefix(nm + ".") || n.hasPrefix(nm + " ") { return .weak }
        return nil
    }

    static func leftovers(for app: InstalledApp) -> [FileItem] {
        let fm = FileManager.default
        let lib = SafetyGuard.home.appendingPathComponent("Library")
        let team = teamID(of: app.url)
        var dirs: [URL] = userSubdirs.map { lib.appendingPathComponent($0) }
        dirs += systemDirs.map { URL(fileURLWithPath: $0) }

        var seen = Set<String>()
        var out: [FileItem] = []
        for dir in dirs {
            guard let list = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for u in list {
                guard let m = match(u.lastPathComponent, bid: app.bundleID, team: team, name: app.name),
                      !seen.contains(u.path),
                      (try? SafetyGuard.validate(u, allowApplications: true)) != nil else { continue }
                // ByHost klasörünün kendisini değil, içindeki eşleşen dosyaları al.
                if u.lastPathComponent == "ByHost" { continue }
                seen.insert(u.path)
                out.append(FileItem(url: u, size: DiskScanner.allocatedSize(of: u),
                                    modified: nil, selected: m == .strong))
            }
        }
        return out.sorted { ($0.selected ? 0 : 1, -$0.size) < ($1.selected ? 0 : 1, -$1.size) }
    }
}
