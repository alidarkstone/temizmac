import Foundation

/// Tek silme noktası. Varsayılan: Çöp Sepeti'ne taşı (geri alınabilir).
/// Kalıcı silme yalnızca Çöp Sepeti kategorisi için kullanılır.
enum Cleaner {
    static func clean(_ items: [FileItem], allowedRoots: [URL]?, permanent: Bool = false,
                      allowApplications: Bool = false, dryRun: Bool) -> CleanReport {
        var r = CleanReport()
        let fm = FileManager.default
        for item in items {
            do {
                try SafetyGuard.validate(item.url, allowedRoots: allowedRoots,
                                         allowApplications: allowApplications)
                if dryRun {
                    r.trashed.append(item.url)
                } else if permanent {
                    try fm.removeItem(at: item.url)
                    r.trashed.append(item.url)
                } else {
                    var resulting: NSURL?
                    try fm.trashItem(at: item.url, resultingItemURL: &resulting)
                    r.trashed.append(item.url)
                }
                r.freedBytes += item.size
            } catch {
                r.skipped.append((item.url, "\(error)"))
            }
        }
        AuditLog.write(report: r, dryRun: dryRun, permanent: permanent)
        return r
    }
}

/// Yerel, düz metin işlem günlüğü: ~/Library/Logs/TemizMac/actions.log. Ağa hiçbir şey gönderilmez.
enum AuditLog {
    static let url = SafetyGuard.home.appendingPathComponent("Library/Logs/TemizMac/actions.log")

    static func write(report: CleanReport, dryRun: Bool, permanent: Bool) {
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let mode = dryRun ? "DRY-RUN" : (permanent ? "DELETE" : "TRASH")
        let ts = ISO8601DateFormatter().string(from: Date())
        var lines = report.trashed.map { "\(ts) \(mode) \($0.path)" }
        lines += report.skipped.map { "\(ts) SKIP \($0.0.path) — \($0.1)" }
        guard !lines.isEmpty, let data = (lines.joined(separator: "\n") + "\n").data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(data); try? h.close()
        } else {
            try? data.write(to: url)
        }
    }
}
