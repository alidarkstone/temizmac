import Foundation

/// Silme işlemlerinden önce her yolu doğrulayan güvenlik katmanı.
/// Kural: yalnızca kullanıcının ev dizini altında, izinli köklerde,
/// symlink olmayan ve korumalı listede bulunmayan yollar silinebilir.
enum SafetyGuard {
    static let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL

    /// Asla dokunulmayacak yollar (ev dizinine göre).
    static let protectedRelative: [String] = [
        "Library/Keychains",
        "Library/Mail",
        "Library/Messages",
        "Library/Mobile Documents",      // iCloud Drive
        "Library/Application Support/MobileSync", // iPhone yedekleri
        "Library/Containers/com.apple.mail",
        "Library/Preferences/com.apple.security",
        "Library/Cookies",
        "Library/Accounts",
        "Library/Photos",
        "Pictures/Photos Library.photoslibrary",
        ".ssh", ".gnupg"
    ]

    /// Oturum/senkron önbellekleri: adında bunlar geçen öğeler temizlik listesine girmez.
    static let sensitiveNameFragments = ["cloudkit", "akd", "password", "keychain", "auth", "token",
                                         "credential", "com.apple.ak", "icloud"]

    static func looksSensitive(_ url: URL) -> Bool {
        let n = url.lastPathComponent.lowercased()
        return sensitiveNameFragments.contains { n.contains($0) }
    }

    /// Uygulama kaldırırken yönetici izniyle dokunulabilecek sistem konumları.
    static let systemLeftoverRoots: [URL] = [
        "/Library/Application Support", "/Library/Caches", "/Library/Preferences",
        "/Library/LaunchAgents", "/Library/LaunchDaemons", "/Library/PrivilegedHelperTools",
        "/Library/Logs", "/private/var/db/receipts"
    ].map { URL(fileURLWithPath: $0) }

    static var protectedURLs: [URL] {
        protectedRelative.map { home.appendingPathComponent($0).standardizedFileURL }
    }

    enum Rejection: Error, CustomStringConvertible {
        case outsideHome(String), protected(String), symlink(String), isRoot(String), missing(String)
        var description: String {
            switch self {
            case .outsideHome(let p): return "Ev dizini dışında: \(p)"
            case .protected(let p): return "Korumalı yol: \(p)"
            case .symlink(let p): return "Sembolik bağ atlandı: \(p)"
            case .isRoot(let p): return "Kök dizin silinemez: \(p)"
            case .missing(let p): return "Bulunamadı: \(p)"
            }
        }
    }

    /// `allowedRoots` verilirse yol bu köklerden birinin *altında* olmalıdır (kökün kendisi değil).
    static func validate(_ url: URL, allowedRoots: [URL]? = nil, allowApplications: Bool = false) throws {
        let u = url.standardizedFileURL
        let path = u.path

        guard FileManager.default.fileExists(atPath: path) else { throw Rejection.missing(path) }

        if let vals = try? u.resourceValues(forKeys: [.isSymbolicLinkKey]), vals.isSymbolicLink == true {
            throw Rejection.symlink(path)
        }

        let inHome = isStrictDescendant(u, of: home)
        let inApps = allowApplications && isStrictDescendant(u, of: URL(fileURLWithPath: "/Applications"))
        let inSys = allowApplications && systemLeftoverRoots.contains { isStrictDescendant(u, of: $0) }
        guard inHome || inApps || inSys else { throw Rejection.outsideHome(path) }
        // Apple'a ait kapsayıcılar / sistem öğeleri asla.
        if u.lastPathComponent.lowercased().contains("com.apple") { throw Rejection.protected(path) }

        for p in protectedURLs where u == p || isStrictDescendant(u, of: p) || isStrictDescendant(p, of: u) {
            throw Rejection.protected(path)
        }

        if let roots = allowedRoots {
            let std = roots.map { $0.standardizedFileURL }
            if std.contains(u) { throw Rejection.isRoot(path) }
            guard std.contains(where: { isStrictDescendant(u, of: $0) }) || inApps || inSys else {
                throw Rejection.outsideHome(path)
            }
        }
    }

    static func isStrictDescendant(_ child: URL, of parent: URL) -> Bool {
        let c = child.standardizedFileURL.pathComponents
        let p = parent.standardizedFileURL.pathComponents
        return c.count > p.count && Array(c.prefix(p.count)) == p
    }
}
