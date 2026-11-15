import SwiftUI
import AppKit

struct PerformanceView: View {
    @EnvironmentObject var s: AppState
    @State private var tweaks = Performance.tweaks
    @State private var chosen = Set<String>()
    @State private var saved = Set<String>()      // önceki değeri saklı olanlar (geri alınabilir)
    @State private var agents: [Performance.Agent] = []
    @State private var procs: [Performance.Proc] = []
    @State private var byMemory = true
    @State private var busy = false
    @State private var confirmApply = false

    private var chosenEffects: [String] {
        tweaks.filter { chosen.contains($0.id) }.compactMap { t in t.sideEffect.map { "• \(t.title): \($0)" } }
    }

    private var groups: [String] { tweaks.reduce(into: [String]()) { if !$0.contains($1.group) { $0.append($1.group) } } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Performans").font(.title2.bold())
                    Text("Her değişikliğin önceki değeri saklanır; \"Geri Al\" ile eski haline döner.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Geri Al") { Task { await revert() } }
                    .disabled(busy || saved.isEmpty)
                Button(s.dryRun ? "Önizle" : "Seçilenleri Uygula") { confirmApply = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(busy || chosen.isEmpty)
            }.padding()

            List {
                ForEach(groups, id: \.self) { g in
                    Section(g) {
                        ForEach(tweaks.filter { $0.group == g }) { t in
                            HStack {
                                Toggle("", isOn: Binding(get: { chosen.contains(t.id) },
                                                         set: { on in if on { chosen.insert(t.id) } else { chosen.remove(t.id) } }))
                                    .labelsHidden()
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(t.title)
                                        if t.admin { Badge(text: "Yönetici", color: .orange) }
                                        if t.applied { Badge(text: "Uygulandı", color: .green) }
                                    }
                                    Text(t.detail).font(.caption).foregroundStyle(.secondary)
                                    if let fx = t.sideEffect {
                                        Text("Yan etki: \(fx)").font(.caption2).foregroundStyle(.orange)
                                    }
                                }
                            }
                        }
                    }
                }

                Section("Üçüncü taraf başlangıç ajanları") {
                    if agents.isEmpty { Text("Üçüncü taraf ajan yok").foregroundStyle(.secondary) }
                    ForEach($agents) { $a in
                        let binding = $a
                        Toggle(isOn: Binding(get: { binding.wrappedValue.enabled }, set: { v in
                            let ag = binding.wrappedValue
                            Task {
                                let ok = await Task.detached { Performance.setAgent(ag, enabled: v) }.value
                                if ok { binding.wrappedValue.enabled = v }
                            }
                        })) {
                            VStack(alignment: .leading) {
                                HStack(spacing: 6) {
                                    Text(a.id).lineLimit(1)
                                    if a.parentMissing { Badge(text: "Uygulaması yok", color: .red) }
                                }
                                Text(a.plist.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            }
                        }
                        .toggleStyle(.switch)
                    }
                    Text("Kapatılan ajan silinmez; anahtarı tekrar açarak geri alabilirsiniz. Apple ajanları listelenmez.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section {
                    Picker("", selection: $byMemory) {
                        Text("Bellek").tag(true); Text("İşlemci").tag(false)
                    }.pickerStyle(.segmented).labelsHidden()
                    ForEach(procs) { p in
                        HStack {
                            Text(p.name).lineLimit(1)
                            Spacer()
                            Text(String(format: "%%%.1f CPU", p.cpu)).monospacedDigit().foregroundStyle(.secondary)
                            Text(String(format: "%.0f MB", p.memMB)).monospacedDigit().frame(width: 80, alignment: .trailing)
                            if let app = NSRunningApplication(processIdentifier: p.id), app.activationPolicy == .regular {
                                Button("Çık") { app.terminate(); Task { try? await Task.sleep(nanoseconds: 800_000_000); await loadProcs() } }
                                    .buttonStyle(.borderless)
                            } else {
                                Color.clear.frame(width: 24)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("En çok kaynak kullananlar")
                        Spacer()
                        Button("Yenile") { Task { await loadProcs() } }.buttonStyle(.link)
                    }
                }

                Section("Elle") {
                    HStack {
                        Text("Giriş öğeleri ve arka plan izinleri")
                        Spacer()
                        Button("Ayarları Aç") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
                        }
                    }
                    HStack {
                        Text("Spotlight'tan ağır klasörleri hariç tut (node_modules, sanal makineler)")
                        Spacer()
                        Button("Ayarları Aç") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Spotlight-Settings.extension")!)
                        }
                    }
                }
            }
        }
        .task { await loadAll() }
        .confirmationDialog("\(chosen.count) ayar uygulansın mı?", isPresented: $confirmApply) {
            Button(s.dryRun ? "Önizle" : "Uygula") { Task { await apply() } }
        } message: {
            Text(chosenEffects.isEmpty
                 ? "Bilinen yan etkisi yok. Önceki değerler saklanır; Geri Al ile dönebilirsiniz."
                 : "Yan etkiler:\n" + chosenEffects.joined(separator: "\n") + "\n\nÖnceki değerler saklanır; Geri Al ile dönebilirsiniz.")
        }
        .onChange(of: byMemory) { _ in Task { await loadProcs() } }
    }

    private func loadAll() async {
        let list = tweaks
        let applied = await Task.detached { list.map { Performance.isApplied($0) } }.value
        for i in tweaks.indices { tweaks[i].applied = applied[i] }
        saved = Set(Performance.loadState().keys)
        agents = await Task.detached { Performance.agents() }.value
        await loadProcs()
    }

    private func loadProcs() async {
        let m = byMemory
        procs = await Task.detached { Performance.topProcesses(byMemory: m) }.value
    }

    private func apply() async {
        let list = tweaks.filter { chosen.contains($0.id) }
        if s.dryRun {
            s.lastReport = "Önizleme: \(list.count) ayar uygulanacaktı. Uygulamak için Önizleme'yi kapatın."
            return
        }
        busy = true
        let errs = await Task.detached { Performance.apply(list) }.value
        s.lastReport = errs.isEmpty ? "\(list.count) ayar uygulandı. Bazıları için oturumu kapatıp açmak gerekebilir."
                                    : "Bazı ayarlar uygulanamadı: \(errs.first!)"
        chosen.removeAll()
        busy = false
        await loadAll()
    }

    private func revert() async {
        let list = tweaks.filter { saved.contains($0.id) }
        if s.dryRun {
            s.lastReport = "Önizleme: \(list.count) ayar eski haline dönecekti."
            return
        }
        busy = true
        let errs = await Task.detached { Performance.revert(list) }.value
        s.lastReport = errs.isEmpty ? "\(list.count) ayar eski haline döndürüldü." : "Geri alma hatası: \(errs.first!)"
        busy = false
        await loadAll()
    }
}
