import SwiftUI
import AppKit

struct MaintenanceView: View {
    @EnvironmentObject var s: AppState
    @State private var tasks = Maintenance.all
    @State private var running = false
    @State private var summary: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bakım").font(.title2.bold())
                    Text("Sistemin biriktirdiği önbellek ve veritabanlarını yeniler. Yönetici parolası bir kez istenir.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await run() }
                } label: {
                    Label(running ? "Çalışıyor…" : (s.dryRun ? "Önizle" : "Bakımı Başlat"), systemImage: "wrench.and.screwdriver")
                        .frame(minWidth: 140)
                }
                .controlSize(.large).buttonStyle(.borderedProminent)
                .disabled(running || !tasks.contains(where: \.enabled))
            }.padding()

            List {
                Section {
                    ForEach($tasks) { $t in
                        HStack(alignment: .top, spacing: 10) {
                            Toggle("", isOn: $t.enabled).labelsHidden().disabled(running)
                            Image(systemName: t.symbol).frame(width: 20).foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(t.title)
                                    if t.needsAdmin { Badge(text: "Yönetici", color: .orange) }
                                }
                                Text(t.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            StatusIcon(status: t.status)
                        }
                        .padding(.vertical, 2)
                    }
                }
                Section("Elle gözden geçirin") {
                    HStack {
                        Image(systemName: "person.crop.circle.badge.checkmark").frame(width: 20)
                        Text("Giriş öğeleri (oturum açınca başlayan uygulamalar)")
                        Spacer()
                        Button("Ayarları Aç") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
                        }
                    }
                    Text("Arka plan ajanları için soldaki \"Başlangıç Öğeleri\" bölümünü kullanın.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                if let summary { Text(summary).font(.callout.bold()) }
                Text("Not: Bakım ve temizlik birçok yavaşlık sebebini giderir, ancak sıfır kurulumla birebir aynı sonucu garanti edemez. Donanım yaşı, disk doluluğu ve kurulu yazılımlar da etkilidir. En iyi sonuç için bakımdan sonra Mac'i yeniden başlatın.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding()
        }
    }

    private func run() async {
        running = true; summary = nil
        let dry = s.dryRun
        for i in tasks.indices { tasks[i].status = tasks[i].enabled ? .running : .idle }
        let selected = tasks.filter(\.enabled)
        Maintenance.log("---- Bakım başladı (\(dry ? "önizleme" : "gerçek")) ----")

        if dry {
            for t in selected {
                Maintenance.log("PREVIEW \(t.id): \(t.command)")
                set(t.id, .preview)
            }
            summary = "Önizleme: \(selected.count) görev çalıştırılacaktı. Gerçekten çalıştırmak için Önizleme'yi kapatın."
            running = false
            return
        }

        var ok = 0
        let admin = selected.filter(\.needsAdmin)
        if !admin.isEmpty {
            let (res, err) = await Task.detached { Maintenance.runAdmin(admin) }.value
            for t in admin {
                let success = res[t.id] == true
                if success { ok += 1 }
                Maintenance.log("\(success ? "OK" : "FAIL") \(t.id)\(err.map { " — \($0)" } ?? "")")
                set(t.id, success ? .done : .failed(err ?? "Başarısız"))
            }
        }
        for t in selected where !t.needsAdmin {
            let (success, out) = await Task.detached { Maintenance.runUser(t.command) }.value
            if success { ok += 1 }
            Maintenance.log("\(success ? "OK" : "FAIL") \(t.id) \(out.prefix(500))")
            set(t.id, success ? .done : .failed(String(out.suffix(200))))
        }
        Maintenance.log("---- Bitti: \(ok)/\(selected.count) ----")
        summary = "Bakım tamamlandı: \(ok)/\(selected.count) görev başarılı. Mac'i yeniden başlatmanız önerilir."
        running = false
        s.refreshDisk()
    }

    private func set(_ id: String, _ st: MaintenanceTask.Status) {
        if let i = tasks.firstIndex(where: { $0.id == id }) { tasks[i].status = st }
    }
}

private struct StatusIcon: View {
    let status: MaintenanceTask.Status
    var body: some View {
        switch status {
        case .idle: EmptyView()
        case .running: ProgressView().controlSize(.small)
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .preview: Image(systemName: "eye.circle").foregroundStyle(.blue)
        case .failed(let m): Image(systemName: "xmark.octagon.fill").foregroundStyle(.red).help(m)
        }
    }
}
