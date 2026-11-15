import Foundation

/// Salt-okunur tarayıcı. Hiçbir şeyi silmez (dry-run varsayılandır).
enum DiskScanner {
    private static let keys: [URLResourceKey] = [
        .isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey,
        .fileAllocatedSizeKey, .contentModificationDateKey, .isPackageKey
    ]

    /// Bir dosya/dizinin diskte kapladığı toplam boyut. Symlink'leri izlemez.
    static func allocatedSize(of url: URL) -> Int64 {
        guard let v = try? url.resourceValues(forKeys: Set(keys)) else { return 0 }
        if v.isSymbolicLink == true { return 0 }
        if v.isDirectory != true {
            return Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
        }
        var total: Int64 = 0
        let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys,
                                               options: [], errorHandler: { _, _ in true })
        while let f = e?.nextObject() as? URL {
            if Task.isCancelled { break }
            guard let fv = try? f.resourceValues(forKeys: Set(keys)),
                  fv.isSymbolicLink != true, fv.isDirectory != true else { continue }
            total += Int64(fv.totalFileAllocatedSize ?? fv.fileAllocatedSize ?? 0)
        }
        return total
    }

    static func scan(_ cat: CleanCategory) -> [FileItem] {
        let fm = FileManager.default
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: Date())!
        var items: [FileItem] = []
        for root in cat.roots where fm.fileExists(atPath: root.path) {
            guard let children = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: keys,
                                                             options: []) else { continue }
            for c in children {
                if c.lastPathComponent == ".DS_Store" && cat.id != "trash" { continue }
                guard (try? SafetyGuard.validate(c, allowedRoots: cat.roots)) != nil else { continue }
                if cat.id != "trash", SafetyGuard.looksSensitive(c) { continue }
                let mod = (try? c.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                if cat.id == "downloads" {
                    guard let m = mod, m < cutoff else { continue }
                }
                let size = allocatedSize(of: c)
                guard size > 0 else { continue }
                items.append(FileItem(url: c, size: size, modified: mod,
                                      selected: cat.id != "downloads"))
            }
        }
        return items.sorted { $0.size > $1.size }
    }

    /// Ev dizininde eşik değerinden büyük dosyaları bulur.
    static func largeFiles(under root: URL = SafetyGuard.home, minBytes: Int64,
                           progress: ((Int) -> Void)? = nil) -> [FileItem] {
        let skip: Set<String> = ["Library", ".Trash"]
        var out: [FileItem] = []
        var seen = 0
        let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                                               options: [.skipsPackageDescendants],
                                               errorHandler: { _, _ in true })
        while let f = e?.nextObject() as? URL {
            if Task.isCancelled { break }
            if e?.level == 1, skip.contains(f.lastPathComponent) { e?.skipDescendants(); continue }
            if SafetyGuard.protectedURLs.contains(f.standardizedFileURL) { e?.skipDescendants(); continue }
            guard let v = try? f.resourceValues(forKeys: Set(keys)),
                  v.isSymbolicLink != true else { continue }
            seen += 1
            if seen % 2000 == 0 { progress?(seen) }
            let size: Int64
            if v.isPackage == true { size = allocatedSize(of: f) }
            else if v.isDirectory == true { continue }
            else { size = Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0) }
            if size >= minBytes {
                out.append(FileItem(url: f, size: size, modified: v.contentModificationDate, selected: false))
            }
        }
        return out.sorted { $0.size > $1.size }
    }
}
