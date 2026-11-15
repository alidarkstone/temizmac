import Foundation

/// Salt-okunur sistem denetimi. Hiçbir şeyi değiştirmez; raporu dosyaya yazar. Ağa çıkmaz.
enum Audit {
    static let dir = SafetyGuard.home.appendingPathComponent("Library/Logs/Magicstone")

    static func run(progress: ((String) -> Void)? = nil) -> (text: String, file: URL) {
        var r: [String] = []
        func sh(_ c: String) -> String {
            Maintenance.runUser(c).1.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        func section(_ t: String) { r.append("\n== \(t) ==") ; progress?(t) }

        r.append("Magicstone Denetim Raporu — \(ISO8601DateFormatter().string(from: Date()))")
        r.append("Bu rapor salt-okunurdur; hiçbir ayar değiştirilmedi.")

        section("Sistem")
        r.append(sh("/usr/bin/sw_vers"))
        r.append("Model: " + sh("/usr/sbin/sysctl -n hw.model"))
        r.append("Bellek: " + sh("/usr/sbin/sysctl -n hw.memsize | /usr/bin/awk '{printf \"%.0f GB\", $1/1073741824}'"))
        r.append("Çalışma süresi:" + sh("/usr/bin/uptime"))

        section("Güvenlik (dokunulmaz, yalnızca durum)")
        r.append("SIP: " + sh("/usr/bin/csrutil status"))
        r.append("FileVault: " + sh("/usr/bin/fdesetup status"))
        r.append("Gatekeeper: " + sh("/usr/sbin/spctl --status"))
        r.append("Güvenlik duvarı: " + sh("/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate"))

        section("Disk")
        r.append(sh("/bin/df -h /"))
        if let d = DiskInfo.current() {
            r.append(String(format: "Doluluk: %%%.0f", d.usedRatio * 100) + (d.usedRatio > 0.85 ? "  ⚠︎ %85 üstü yavaşlatır" : ""))
        }
        r.append("Yerel Time Machine anlık görüntüleri: " + sh("/usr/bin/tmutil listlocalsnapshots / | /usr/bin/grep -c com.apple || true"))

        section("Güç")
        r.append(sh("/usr/bin/pmset -g | /usr/bin/head -25"))

        section("Önbellek boyutları")
        for c in Categories.all {
            let total = c.roots.reduce(Int64(0)) { $0 + DiskScanner.allocatedSize(of: $1) }
            r.append("\(c.title): \(total.human)")
        }

        section("Gizlilik / performans ayarları")
        var off = 0
        for t in Performance.tweaks {
            let ok = Performance.isApplied(t)
            if !ok { off += 1 }
            r.append("[\(ok ? "✓" : " ")] \(t.title)")
        }
        r.append("Önerilen ama uygulanmamış: \(off)/\(Performance.tweaks.count)")

        section("Üçüncü taraf başlangıç ajanları")
        let agents = Performance.agents()
        for a in agents { r.append("\(a.enabled ? "AÇIK  " : "KAPALI") \(a.id)") }
        let launch = LaunchAgents.scan().filter(\.orphaned)
        r.append("Yetim (programı silinmiş) ajan: \(launch.count)")
        for l in launch { r.append("  - \(l.label) → \(l.program ?? "?")") }

        section("Eski uygulama kalıntıları")
        let o = OrphanScanner.scan()
        let sureSize = o.sure.reduce(Int64(0)) { $0 + $1.size }
        r.append("Kesin: \(o.sure.count) öğe (\(sureSize.human)), kontrol edilecek: \(o.maybe.count)")
        for i in o.sure.prefix(30) { r.append("  - \(i.displayPath) (\(i.size.human))") }

        section("En çok bellek kullananlar")
        for p in Performance.topProcesses(byMemory: true, limit: 8) {
            r.append(String(format: "%6.0f MB  %%%.1f CPU  %@", p.memMB, p.cpu, p.name))
        }

        section("Tut listesi")
        r.append(KeepList.all.isEmpty ? "(boş)" : KeepList.all.sorted().joined(separator: "\n"))

        r.append("\nÖneri: Uygulamalar güncellemede ajanlarını geri getirebilir; denetimi haftada bir tekrarlayın.")

        let text = r.joined(separator: "\n")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmm"
        let file = dir.appendingPathComponent("denetim-\(f.string(from: Date())).txt")
        try? text.write(to: file, atomically: true, encoding: .utf8)
        return (text, file)
    }
}
