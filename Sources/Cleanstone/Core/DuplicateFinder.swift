import Foundation
import CryptoKit

/// Aynı içeriğe sahip dosyalardan oluşan grup.
struct DuplicateGroup: Identifiable {
    let id = UUID()
    var files: [FileItem]

    /// Bir kopya dışındaki tüm kopyaların kapladığı alan.
    var wasted: Int64 {
        guard let first = files.first, files.count > 1 else { return 0 }
        return first.size * Int64(files.count - 1)
    }
}

/// Kopya dosya bulucu. Yalnızca okur; hiçbir şeyi silmez.
/// Aşamalar: boyuta göre grupla -> ilk 64 KB özeti -> tam SHA256.
enum DuplicateFinder {
    private static let keys: [URLResourceKey] = [
        .isRegularFileKey, .isSymbolicLinkKey, .isHiddenKey,
        .fileSizeKey, .contentModificationDateKey
    ]
    private static let chunkSize = 1 << 20      // 1 MB
    private static let headSize = 64 * 1024     // 64 KB

    static func find(in root: URL, minBytes: Int64, progress: ((String) -> Void)?) -> [DuplicateGroup] {
        let rootURL = root.standardizedFileURL
        let home = SafetyGuard.home
        var excludedURLs: [URL] = [home.appendingPathComponent("Library"),
                                   home.appendingPathComponent(".Trash")]
        excludedURLs.append(contentsOf: SafetyGuard.protectedURLs)
        let excluded: [String] = excludedURLs.map { $0.standardizedFileURL.path }

        if isExcluded(rootURL.path, excluded) { return [] }
        let threshold: Int64 = max(minBytes, 1)

        // 1) Dosyaları topla, boyuta göre grupla.
        var bySize: [Int64: [FileItem]] = [:]
        guard let e = FileManager.default.enumerator(at: rootURL,
                                                     includingPropertiesForKeys: keys,
                                                     options: [.skipsHiddenFiles, .skipsPackageDescendants],
                                                     errorHandler: { _, _ in true }) else { return [] }
        var seen = 0
        while let obj = e.nextObject() {
            if Task.isCancelled { return [] }
            guard let f = obj as? URL else { continue }
            let path = f.standardizedFileURL.path
            if isExcluded(path, excluded) { e.skipDescendants(); continue }
            if SafetyGuard.looksSensitive(f) { e.skipDescendants(); continue }
            guard let v = try? f.resourceValues(forKeys: Set(keys)) else { continue }
            if v.isSymbolicLink == true || v.isHidden == true { continue }
            guard v.isRegularFile == true else { continue }
            seen += 1
            if seen % 500 == 0 { progress?("\(seen) dosya tarandı…") }
            let size = Int64(v.fileSize ?? 0)
            guard size >= threshold else { continue }
            let item = FileItem(url: f, size: size, modified: v.contentModificationDate, selected: false)
            bySize[size, default: []].append(item)
        }
        progress?("\(seen) dosya tarandı")

        var sizeGroups: [[FileItem]] = []
        for (_, list) in bySize {
            let unique = dropHardLinks(list)
            if unique.count >= 2 { sizeGroups.append(unique) }
        }
        if Task.isCancelled { return [] }

        // 2) İlk 64 KB özeti.
        var headGroups: [[FileItem]] = []
        let totalSizeGroups = sizeGroups.count
        for (i, list) in sizeGroups.enumerated() {
            if Task.isCancelled { return [] }
            if i % 20 == 0 { progress?("Ön karşılaştırma: \(i)/\(totalSizeGroups)") }
            var byHead: [String: [FileItem]] = [:]
            for item in list {
                if Task.isCancelled { return [] }
                guard let h = sha256Hex(of: item.url, limit: headSize) else { continue }
                byHead[h, default: []].append(item)
            }
            for (_, g) in byHead where g.count >= 2 { headGroups.append(g) }
        }

        // 3) Tam SHA256.
        var result: [DuplicateGroup] = []
        let totalHeadGroups = headGroups.count
        for (i, list) in headGroups.enumerated() {
            if Task.isCancelled { return [] }
            progress?("Tam karşılaştırma: \(i + 1)/\(totalHeadGroups)")
            let fileSize = list.first?.size ?? 0
            if fileSize <= Int64(headSize) {
                // İlk 64 KB dosyanın tamamı; özet zaten tam.
                result.append(makeGroup(list))
                continue
            }
            var byFull: [String: [FileItem]] = [:]
            for item in list {
                if Task.isCancelled { return [] }
                guard let h = sha256Hex(of: item.url, limit: nil) else { continue }
                byFull[h, default: []].append(item)
            }
            for (_, g) in byFull where g.count >= 2 { result.append(makeGroup(g)) }
        }
        if Task.isCancelled { return [] }

        result.sort { $0.wasted > $1.wasted }
        return result
    }

    // MARK: - Yardımcılar

    private static func isExcluded(_ path: String, _ excluded: [String]) -> Bool {
        for p in excluded where path == p || path.hasPrefix(p + "/") { return true }
        return false
    }

    /// Aynı inode'a işaret eden sabit bağları tek kayda indirir (silmek yer kazandırmaz).
    private static func dropHardLinks(_ list: [FileItem]) -> [FileItem] {
        guard list.count >= 2 else { return list }
        var seenIDs = Set<String>()
        var out: [FileItem] = []
        for item in list {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: item.url.path),
               let ino = attrs[.systemFileNumber] as? NSNumber,
               let dev = attrs[.systemNumber] as? NSNumber {
                let key = "\(dev.int64Value):\(ino.int64Value)"
                if seenIDs.contains(key) { continue }
                seenIDs.insert(key)
            }
            out.append(item)
        }
        return out
    }

    /// En eski dosya korunur (seçilmez), diğerleri seçili gelir.
    private static func makeGroup(_ list: [FileItem]) -> DuplicateGroup {
        let sorted = list.sorted { a, b in
            switch (a.modified, b.modified) {
            case let (x?, y?):
                if x != y { return x < y }
                return a.url.path < b.url.path
            case (.some, .none): return true
            case (.none, .some): return false
            case (.none, .none): return a.url.path < b.url.path
            }
        }
        var files: [FileItem] = []
        for (i, item) in sorted.enumerated() {
            var copy = item
            copy.selected = (i != 0)
            files.append(copy)
        }
        return DuplicateGroup(files: files)
    }

    /// Dosyanın SHA256 özetini 1 MB'lık parçalarla okuyarak hesaplar.
    /// `limit` verilirse yalnızca ilk `limit` bayt okunur. Hata/iptal durumunda nil.
    private static func sha256Hex(of url: URL, limit: Int?) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        var remaining: Int = limit ?? Int.max
        var failed = false
        while remaining > 0 {
            if Task.isCancelled { return nil }
            let want = min(chunkSize, remaining)
            // 0: devam, 1: dosya sonu, 2: hata
            let status: Int = autoreleasepool { () -> Int in
                let data: Data?
                do {
                    data = try handle.read(upToCount: want)
                } catch {
                    return 2
                }
                guard let d = data, !d.isEmpty else { return 1 }
                hasher.update(data: d)
                remaining -= d.count
                return 0
            }
            if status == 2 { failed = true; break }
            if status == 1 { break }
        }
        if failed { return nil }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
