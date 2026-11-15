import Foundation

struct FileItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let size: Int64
    let modified: Date?
    var selected: Bool = true

    var name: String { url.lastPathComponent }
    var displayPath: String {
        url.path.replacingOccurrences(of: SafetyGuard.home.path, with: "~")
    }
}

struct CleanCategory: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let detail: String
    /// Taranacak kök dizinler. Kökler silinmez, yalnızca içerikleri.
    let roots: [URL]
    /// true: kökün doğrudan çocuklarını tek öğe olarak listele (ör. her uygulamanın cache klasörü).
    var listChildren: Bool = true
}

struct CleanReport {
    var trashed: [URL] = []
    var skipped: [(URL, String)] = []
    var freedBytes: Int64 = 0
}

extension Int64 {
    var human: String { ByteCountFormatter.string(fromByteCount: self, countStyle: .file) }
}
