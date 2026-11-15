import Foundation

struct LaunchItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let label: String
    let program: String?
    let programExists: Bool
    /// true: ~/Library/LaunchAgents (kullanıcı, kaldırılabilir). false: /Library (salt görüntüleme).
    let isUser: Bool
    var selected: Bool = false

    var orphaned: Bool { program != nil && !programExists }
}

/// Arka planda çalışan başlatma öğeleri (LaunchAgents / LaunchDaemons).
enum LaunchAgents {
    static let userDir = SafetyGuard.home.appendingPathComponent("Library/LaunchAgents")
    static let systemDirs = [URL(fileURLWithPath: "/Library/LaunchAgents"),
                             URL(fileURLWithPath: "/Library/LaunchDaemons")]

    static func scan() -> [LaunchItem] {
        var out: [LaunchItem] = []
        for (dir, isUser) in [(userDir, true)] + systemDirs.map({ ($0, false) }) {
            guard let list = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            else { continue }
            for u in list where u.pathExtension == "plist" {
                let dict = NSDictionary(contentsOf: u) as? [String: Any] ?? [:]
                let label = dict["Label"] as? String ?? u.deletingPathExtension().lastPathComponent
                if label.hasPrefix("com.apple.") { continue }
                let program = (dict["Program"] as? String) ?? (dict["ProgramArguments"] as? [String])?.first
                let exists = program.map { FileManager.default.fileExists(atPath: $0) } ?? true
                // Yetim öğeleri varsayılan olarak seç (yalnızca kullanıcı öğeleri).
                out.append(LaunchItem(url: u, label: label, program: program, programExists: exists,
                                      isUser: isUser, selected: isUser && program != nil && !exists))
            }
        }
        return out.sorted { ($0.orphaned ? 0 : 1, $0.label) < ($1.orphaned ? 0 : 1, $1.label) }
    }

    /// Kullanıcı ajanını durdurur ve plist'i Çöp Sepeti'ne taşır.
    static func remove(_ items: [LaunchItem], dryRun: Bool) -> CleanReport {
        let user = items.filter(\.isUser)
        if !dryRun {
            for i in user { bootout(i.url) }
        }
        let files = user.map { i -> FileItem in
            let size = (try? i.url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { $0 } ?? 0
            return FileItem(url: i.url, size: Int64(size), modified: nil, selected: true)
        }
        return Cleaner.clean(files, allowedRoots: [userDir], dryRun: dryRun)
    }

    private static func bootout(_ plist: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = ["bootout", "gui/\(getuid())", plist.path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
    }
}
