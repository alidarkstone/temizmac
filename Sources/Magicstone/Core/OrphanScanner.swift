import Foundation
import AppKit

/// Daha önce kaldırılmış uygulamalardan kalan klasör/kayıtları bulur.
/// Yalnızca ters-DNS biçimli (com.firma.uygulama) adlar değerlendirilir; Apple ve sistem öğeleri hariç.
enum OrphanScanner {
    struct Result { var sure: [FileItem]; var maybe: [FileItem] }

    static let userSubdirs = [
        "Application Support", "Caches", "Preferences", "Preferences/ByHost", "Logs",
        "Saved Application State", "Containers", "Group Containers", "HTTPStorages", "WebKit",
        "LaunchAgents", "Application Scripts"
    ]
    static let systemDirs = [
        "/Library/Application Support", "/Library/Caches", "/Library/Preferences",
        "/Library/LaunchAgents", "/Library/LaunchDaemons", "/Library/PrivilegedHelperTools",
        "/private/var/db/receipts"
    ]
    /// Uygulama olmayan ama kalıcı tercih/kayıt tutan bilinen sistem bileşenleri.
    static let excludedPrefixes = [
        "com.apple", "group.com.apple", "org.cups", "com.openssh", "org.openssh", "org.python",
        "com.adobe.acc", "com.magicstone", "local.magicstone"
    ]

    // MARK: Kurulu paket kimlikleri

    static func installedBundleIDs() -> Set<String> {
        var ids = Set<String>()
        let roots = ["/Applications", "/System/Applications", "/System/Library/CoreServices",
                     "/Library/PreferencePanes", "/Library/Input Methods",
                     SafetyGuard.home.appendingPathComponent("Applications").path,
                     SafetyGuard.home.appendingPathComponent("Library/PreferencePanes").path]
        let exts: Set<String> = ["app", "appex", "prefPane", "plugin", "bundle", "xpc", "framework", "service"]
        for root in roots {
            let e = FileManager.default.enumerator(at: URL(fileURLWithPath: root),
                                                   includingPropertiesForKeys: nil,
                                                   options: [.skipsHiddenFiles], errorHandler: { _, _ in true })
            while let u = e?.nextObject() as? URL {
                if (e?.level ?? 0) > 6 { e?.skipDescendants(); continue }
                guard exts.contains(u.pathExtension) else { continue }
                if let b = Bundle(url: u)?.bundleIdentifier { ids.insert(b.lowercased()) }
            }
        }
        // Spotlight: diskin herhangi bir yerinde kurulu uygulamalar (tek sorgu, yerel)
        let (_, found) = Maintenance.runUser("/usr/bin/mdfind \"kMDItemContentType == 'com.apple.application-bundle'\"")
        for path in found.split(separator: "\n") {
            if let b = Bundle(path: String(path))?.bundleIdentifier { ids.insert(b.lowercased()) }
        }
        // Çalışan süreçler (komut satırı araçları, ajanlar)
        for app in NSWorkspace.shared.runningApplications {
            if let b = app.bundleIdentifier { ids.insert(b.lowercased()) }
        }
        return ids
    }

    // MARK: Ad → paket kimliği

    /// "TEAMID.com.firma.app", "group.com.firma.app", "com.firma.app.plist", "com.firma.app.<UUID>.plist" → "com.firma.app"
    static func bundleID(fromName raw: String) -> String? {
        var n = raw.lowercased()
        for ext in [".plist", ".savedstate", ".binarycookies", ".bom", ".db", ".log"] where n.hasSuffix(ext) {
            n = String(n.dropLast(ext.count))
        }
        var parts = n.split(separator: ".").map(String.init)
        // ByHost: son bileşen donanım UUID'si
        if let last = parts.last, last.count >= 12, last.allSatisfy({ $0.isHexDigit || $0 == "-" }) { parts.removeLast() }
        // Group Containers önekleri
        if let first = parts.first, first == "group" || (first.count == 10 && first.allSatisfy({ $0.isLetter || $0.isNumber }) && first.contains(where: { $0.isNumber })) {
            parts.removeFirst()
        }
        guard parts.count >= 3,
              ["com", "org", "net", "io", "de", "co", "app", "me", "dev", "ru", "jp", "fr", "uk", "nl", "tr", "ch", "at", "se", "us"].contains(parts[0]),
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { c in c.isLetter || c.isNumber || c == "-" || c == "_" } })
        else { return nil }
        return parts.joined(separator: ".")
    }

    // MARK: Tarama

    static func scan() -> Result {
        let installed = installedBundleIDs()
        // Güncelleyiciler firmanın "kurulu ürünü" sayılmaz (Office silinince MS AutoUpdate tek başına kalabilir).
        let vendors = Set(installed.filter { !isUpdater($0) }.map { $0.split(separator: ".").prefix(2).joined(separator: ".") })
        let weekAgo = Date().addingTimeInterval(-7 * 86400)
        let lib = SafetyGuard.home.appendingPathComponent("Library")
        let dirs = userSubdirs.map { lib.appendingPathComponent($0) } + systemDirs.map { URL(fileURLWithPath: $0) }

        var sure: [FileItem] = [], maybe: [FileItem] = []
        var seen = Set<String>()
        let fm = FileManager.default
        // pkgutil: dosyaları artık diskte olmayan Apple dışı paket kayıtları
        let receipts = URL(fileURLWithPath: "/private/var/db/receipts")
        let deadPkgs = orphanPackageIDs()
        if let list = try? fm.contentsOfDirectory(at: receipts, includingPropertiesForKeys: nil) {
            for u in list {
                let id = u.deletingPathExtension().lastPathComponent.lowercased()
                guard deadPkgs.contains(id), (try? SafetyGuard.validate(u, allowApplications: true)) != nil else { continue }
                seen.insert(u.path)
                sure.append(FileItem(url: u, size: DiskScanner.allocatedSize(of: u), modified: nil, selected: true))
            }
        }

        for dir in dirs where dir.path != receipts.path {
            guard let list = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])
            else { continue }
            for u in list {
                if Task.isCancelled { return Result(sure: sure, maybe: maybe) }
                guard u.lastPathComponent != "ByHost", !seen.contains(u.path),
                      let bid = bundleID(fromName: u.lastPathComponent),
                      !excludedPrefixes.contains(where: { bid.hasPrefix($0) }),
                      !isInstalled(bid, installed: installed),
                      (try? SafetyGuard.validate(u, allowApplications: true)) != nil
                else { continue }
                seen.insert(u.path)
                let mod = (try? u.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                let vendor = bid.split(separator: ".").prefix(2).joined(separator: ".")
                // Kesin: aynı firmanın kurulu başka ürünü yok ve son 7 günde değişmemiş.
                let confident = !vendors.contains(vendor) && (mod ?? .distantPast) < weekAgo
                let item = FileItem(url: u, size: DiskScanner.allocatedSize(of: u), modified: mod, selected: confident)
                if confident { sure.append(item) } else { maybe.append(item) }
            }
        }
        return Result(sure: sure.sorted { $0.size > $1.size }, maybe: maybe.sorted { $0.size > $1.size })
    }

    /// `pkgutil --pkgs` içinden, üst düzey dosyalarının hiçbiri artık var olmayan paketler.
    static func orphanPackageIDs() -> Set<String> {
        let (_, pkgs) = Maintenance.runUser("/usr/sbin/pkgutil --pkgs")
        var dead = Set<String>()
        for id in pkgs.split(separator: "\n").map(String.init) {
            let lid = id.lowercased()
            if excludedPrefixes.contains(where: { lid.hasPrefix($0) }) { continue }
            let (_, info) = Maintenance.runUser("/usr/sbin/pkgutil --pkg-info \(Performance.q(id))")
            var volume = "/", location = ""
            for line in info.split(separator: "\n") {
                if line.hasPrefix("volume: ") { volume = String(line.dropFirst(8)) }
                if line.hasPrefix("location: ") { location = String(line.dropFirst(10)) }
            }
            let base = URL(fileURLWithPath: volume).appendingPathComponent(location)
            // Ortak sistem dizinleri (Library, usr…) kanıt sayılmaz; somut alt yollara bak.
            let (_, all) = Maintenance.runUser("/usr/sbin/pkgutil --files \(Performance.q(id)) | /usr/bin/awk -F/ 'NF<=3' | /usr/bin/head -400")
            let generic: Set<String> = ["Library", "usr", "private", "etc", "var", "opt", "Applications", "System", "Users",
                                        "Library/Application Support", "Library/LaunchDaemons", "Library/LaunchAgents",
                                        "Library/PrivilegedHelperTools", "Library/Preferences", "usr/local", "usr/local/bin",
                                        "usr/local/lib", "Library/Frameworks", "Library/Extensions", "Library/Audio",
                                        "Library/Audio/Plug-Ins", "Library/Internet Plug-Ins", "Library/PreferencePanes"]
            let specific = all.split(separator: "\n").map(String.init).filter { !generic.contains($0) && !$0.isEmpty }
            guard !specific.isEmpty else { continue }
            let anyExists = specific.contains { FileManager.default.fileExists(atPath: base.appendingPathComponent($0).path) }
            if !anyExists { dead.insert(lid) }
        }
        return dead
    }

    static func isUpdater(_ bid: String) -> Bool {
        let b = bid.lowercased()
        return ["keystone", "updater", "autoupdate", "update.agent", "softwareupdate", "java-updater", "steamclean"]
            .contains { b.contains($0) }
    }

    private static func isInstalled(_ bid: String, installed: Set<String>) -> Bool {
        if installed.contains(bid) { return true }
        // com.firma.app.helper ↔ com.firma.app
        if installed.contains(where: { bid.hasPrefix($0 + ".") || $0.hasPrefix(bid + ".") }) { return true }
        // LaunchServices başka bir yerde kurulu bir kopya biliyor mu?
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid),
           FileManager.default.fileExists(atPath: url.path) { return true }
        return false
    }
}
