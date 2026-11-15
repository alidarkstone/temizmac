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
                r.skipped.append((item.url, friendly(error)))
            }
        }
        AuditLog.write(report: r, dryRun: dryRun, permanent: permanent)
        return r
    }
}

extension Cleaner {
    /// root sahipli uygulamalar için: önce Finder (parola isteyebilir, "Geri Koy" çalışır),
    /// olmazsa macOS yönetici parolası penceresiyle ~/.Trash içine taşı.
    static func recycleViaWorkspace(_ url: URL) throws {
        let path = url.path
        if runAppleScript("""
            tell application "Finder" to delete (POSIX file \(asLiteral(path)) as alias)
            """) == nil, !FileManager.default.fileExists(atPath: path) { return }

        let trash = SafetyGuard.home.appendingPathComponent(".Trash")
        var dest = trash.appendingPathComponent(url.lastPathComponent)
        if FileManager.default.fileExists(atPath: dest.path) {
            let stamp = Int(Date().timeIntervalSince1970)
            dest = trash.appendingPathComponent("\(url.deletingPathExtension().lastPathComponent) \(stamp).\(url.pathExtension)")
        }
        let err = runAppleScript("""
            do shell script "/bin/mv " & quoted form of \(asLiteral(path)) & " " & quoted form of \(asLiteral(dest.path)) with administrator privileges
            """)
        if FileManager.default.fileExists(atPath: path) {
            throw CocoaError(.fileWriteUnknown, userInfo: [
                NSLocalizedDescriptionKey: err ?? "Yönetici izni verilmedi."])
        }
    }

    private static func asLiteral(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// Başarılıysa nil, değilse hata mesajı döner. NSAppleScript ana iş parçacığında çalışmalı.
    private static func runAppleScript(_ source: String) -> String? {
        let work = { () -> String? in
            var info: NSDictionary?
            _ = NSAppleScript(source: source)?.executeAndReturnError(&info)
            return info.map { ($0[NSAppleScript.errorMessage] as? String) ?? "AppleScript hatası" }
        }
        return Thread.isMainThread ? work() : DispatchQueue.main.sync(execute: work)
    }

    static func friendly(_ error: Error) -> String {
        if let r = error as? SafetyGuard.Rejection { return r.description }
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain, [513, 257].contains(ns.code) {
            return "İzin yok (yönetici izni gerekli veya reddedildi)."
        }
        return ns.localizedDescription
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
