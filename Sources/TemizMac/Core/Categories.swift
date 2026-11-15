import Foundation

enum Categories {
    private static func h(_ p: String) -> URL { SafetyGuard.home.appendingPathComponent(p) }

    static let all: [CleanCategory] = [
        CleanCategory(id: "caches", title: "Kullanıcı Önbellekleri", symbol: "internaldrive",
                      detail: "~/Library/Caches — uygulamalar yeniden oluşturur.",
                      roots: [h("Library/Caches")]),
        CleanCategory(id: "logs", title: "Günlük Dosyaları", symbol: "doc.text",
                      detail: "~/Library/Logs",
                      roots: [h("Library/Logs")]),
        CleanCategory(id: "xcode", title: "Xcode Artıkları", symbol: "hammer",
                      detail: "DerivedData, eski Archives, iOS DeviceSupport, simülatör önbellekleri.",
                      roots: [h("Library/Developer/Xcode/DerivedData"),
                              h("Library/Developer/Xcode/Archives"),
                              h("Library/Developer/Xcode/iOS DeviceSupport"),
                              h("Library/Developer/CoreSimulator/Caches")]),
        CleanCategory(id: "devcaches", title: "Geliştirici Önbellekleri", symbol: "shippingbox",
                      detail: "npm, Homebrew, pip, Yarn, Gradle önbellekleri.",
                      roots: [h(".npm/_cacache"), h("Library/Caches/Homebrew"),
                              h("Library/Caches/pip"), h("Library/Caches/Yarn"),
                              h(".gradle/caches")]),
        CleanCategory(id: "trash", title: "Çöp Sepeti", symbol: "trash",
                      detail: "~/.Trash — bu kategori kalıcı olarak siler.",
                      roots: [h(".Trash")]),
        CleanCategory(id: "downloads", title: "Eski İndirmeler", symbol: "arrow.down.circle",
                      detail: "~/Downloads içinde 90 günden eski dosyalar. Varsayılan: seçili değil.",
                      roots: [h("Downloads")])
    ]
}
