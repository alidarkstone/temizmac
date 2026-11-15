import Foundation
import AppKit

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
                    do {
                        var resulting: NSURL?
                        try fm.trashItem(at: item.url, resultingItemURL: &resulting)
                    } catch where allowApplications && item.url.path.hasPrefix("/Applications/") {
                        // root sahipli uygulamalar (App Store vb.): Finder üzerinden, gerekirse parola sorar.
                        try recycleViaWorkspace(item.url)
                    }
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

extension Cleaner {
    static func recycleViaWorkspace(_ url: URL) throws {
        let sem = DispatchSemaphore(value: 0)
        var failure: Error?
        DispatchQueue.main.async {
            NSWorkspace.shared.recycle([url]) { _, err in failure = err; sem.signal() }
        }
        sem.wait()
        if let failure { throw failure }
        if FileManager.default.fileExists(atPath: url.path) {
            throw CocoaError(.fileWriteNoPermission, userInfo: [NSFilePathErrorKey: url.path])
        }
    }
}

/// Yerel, düz metin işlem günlüğü: ~/Library/Logs/Cleanstone/actions.log. Ağa hiçbir şey gönderilmez.
enum AuditLog {
    static let url = SafetyGuard.home.appendingPathComponent("Library/Logs/Cleanstone/actions.log")

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
