import Foundation

struct InstalledApp: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let name: String
    let bundleID: String?
    let size: Int64
}

/// Uygulama kaldırıcı: .app paketini ve ~/Library altındaki artıklarını bulur.
enum Uninstaller {
    static let appDirs = [URL(fileURLWithPath: "/Applications"),
                          SafetyGuard.home.appendingPathComponent("Applications")]

    static func installedApps() -> [InstalledApp] {
        let fm = FileManager.default
        var out: [InstalledApp] = []
        for dir in appDirs {
            guard let list = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for u in list where u.pathExtension == "app" {
                let b = Bundle(url: u)
                let bid = b?.bundleIdentifier
                if let bid, bid.hasPrefix("com.apple.") { continue } // sistem uygulamalarını gösterme
                out.append(InstalledApp(url: u, name: u.deletingPathExtension().lastPathComponent,
                                        bundleID: bid, size: DiskScanner.allocatedSize(of: u)))
            }
        }
        return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// ~/Library altındaki bilinen konumlarda bundle ID veya uygulama adıyla eşleşen artıklar.
    static func leftovers(for app: InstalledApp) -> [FileItem] {
        let lib = SafetyGuard.home.appendingPathComponent("Library")
        let subdirs = ["Application Support", "Caches", "Preferences", "Logs", "Saved Application State",
                       "Containers", "HTTPStorages", "WebKit", "LaunchAgents", "Application Scripts"]
        var needles = [app.name.lowercased()]
        if let b = app.bundleID?.lowercased() { needles.append(b) }
        // Çok kısa adlar yanlış eşleşmeye yol açar.
        needles = needles.filter { $0.count >= 4 }

        let fm = FileManager.default
        var out: [FileItem] = []
        for sd in subdirs {
            let dir = lib.appendingPathComponent(sd)
            guard let list = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for u in list {
                let n = u.lastPathComponent.lowercased()
                let base = (n as NSString).deletingPathExtension
                let match = needles.contains { base == $0 || n.hasPrefix($0 + ".") || n.hasPrefix($0 + "-") }
                guard match, (try? SafetyGuard.validate(u, allowedRoots: [lib])) != nil else { continue }
                // Kullanıcı verisi içerebilecek klasörler varsayılan olarak seçili gelmez.
                let userData = ["Application Support", "Containers"].contains(sd)
                out.append(FileItem(url: u, size: DiskScanner.allocatedSize(of: u),
                                    modified: nil, selected: !userData))
            }
        }
        return out.sorted { $0.size > $1.size }
    }
}
