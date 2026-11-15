import Foundation
import AppKit

/// macOS bakım görevleri. Tamamı yerel komutlardır; ağa çıkılmaz.
struct MaintenanceTask: Identifiable, Hashable {
    enum Status: Hashable { case idle, running, done, failed(String), preview }
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let needsAdmin: Bool
    let command: String
    var enabled: Bool
    var status: Status = .idle
}

enum Maintenance {
    static let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

    static let all: [MaintenanceTask] = [
        MaintenanceTask(id: "ram", title: "Belleği serbest bırak",
                        detail: "Boşaltılabilir RAM'i ve disk önbelleğini temizler (purge).",
                        symbol: "memorychip", needsAdmin: true,
                        command: "/usr/sbin/purge", enabled: true),
        MaintenanceTask(id: "dns", title: "DNS önbelleğini temizle",
                        detail: "Bozuk/eski ad çözümleme kayıtlarını siler.",
                        symbol: "network", needsAdmin: true,
                        command: "/usr/bin/dscacheutil -flushcache; /usr/bin/killall -HUP mDNSResponder", enabled: true),
        MaintenanceTask(id: "periodic", title: "Bakım betiklerini çalıştır",
                        detail: "Günlük/haftalık/aylık sistem bakım betikleri (log döndürme, geçici dosyalar).",
                        symbol: "calendar.badge.clock", needsAdmin: true,
                        command: "[ -x /usr/sbin/periodic ] && /usr/sbin/periodic daily weekly monthly || true", enabled: true),
        MaintenanceTask(id: "launchservices", title: "Launch Services'i yeniden oluştur",
                        detail: "\"Birlikte Aç\" menüsündeki yinelenen/silinmiş uygulamaları düzeltir.",
                        symbol: "square.stack.3d.up", needsAdmin: false,
                        command: "\(lsregister) -kill -r -domain local -domain system -domain user", enabled: true),
        MaintenanceTask(id: "quicklook", title: "Quick Look önbelleğini sıfırla",
                        detail: "Önizleme küçük resimlerini ve eklentilerini yeniler.",
                        symbol: "eye", needsAdmin: false,
                        command: "/usr/bin/qlmanage -r cache; /usr/bin/qlmanage -r", enabled: true),
        MaintenanceTask(id: "fonts", title: "Yazı tipi önbelleklerini temizle",
                        detail: "Bozuk yazı tipi görüntülemesini düzeltir. Yeniden başlatma önerilir.",
                        symbol: "textformat", needsAdmin: true,
                        command: "/usr/bin/atsutil databases -remove; /usr/bin/atsutil server -shutdown; /usr/bin/atsutil server -ping", enabled: false),
        MaintenanceTask(id: "spotlight", title: "Spotlight dizinini yeniden oluştur",
                        detail: "Arama sonuçları eksik/yanlışsa. Saatlerce arka planda sürebilir.",
                        symbol: "magnifyingglass", needsAdmin: true,
                        command: "/usr/bin/mdutil -E /", enabled: false),
        MaintenanceTask(id: "verify", title: "Başlangıç diskini doğrula",
                        detail: "Salt-okunur dosya sistemi denetimi; hiçbir şey değiştirmez. Birkaç dakika sürebilir.",
                        symbol: "checkmark.shield", needsAdmin: false,
                        command: "/usr/sbin/diskutil verifyVolume /", enabled: false)
    ]

    static let logURL = SafetyGuard.home.appendingPathComponent("Library/Logs/Cleanstone/maintenance.log")

    /// Kullanıcı yetkisiyle çalıştırır; (başarı, çıktı) döner.
    static func runUser(_ command: String) -> (Bool, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", command]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (false, error.localizedDescription) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus == 0, String(decoding: data, as: UTF8.self))
    }

    /// Yönetici görevlerini tek parola penceresiyle sırayla çalıştırır.
    /// Her görev kendi işaretçisini yazar; dönüş: görev id → başarı.
    static func runAdmin(_ tasks: [MaintenanceTask]) -> ([String: Bool], String?) {
        guard !tasks.isEmpty else { return ([:], nil) }
        let script = tasks.map { t in
            "( \(t.command) ) >/dev/null 2>&1 && echo OK:\(t.id) || echo FAIL:\(t.id)"
        }.joined(separator: "; ")
        var info: NSDictionary?
        var output = ""
        let work = {
            let src = "do shell script \(Cleaner.asLiteral(script)) with administrator privileges"
            let res = NSAppleScript(source: src)?.executeAndReturnError(&info)
            output = res?.stringValue ?? ""
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.sync(execute: work) }
        if let info {
            let msg = (info[NSAppleScript.errorMessage] as? String) ?? "Yönetici izni verilmedi."
            return (Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, false) }), msg)
        }
        var result: [String: Bool] = [:]
        for t in tasks { result[t.id] = output.contains("OK:\(t.id)") }
        return (result, nil)
    }

    static func log(_ line: String) {
        let fm = FileManager.default
        try? fm.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let ts = ISO8601DateFormatter().string(from: Date())
        guard let data = "\(ts) \(line)\n".data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: logURL) {
            h.seekToEndOfFile(); h.write(data); try? h.close()
        } else {
            try? data.write(to: logURL)
        }
    }
}
