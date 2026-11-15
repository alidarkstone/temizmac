import SwiftUI
import AppKit

enum Pane: Hashable { case smart, audit, maintenance, performance, category(String), orphans, large, duplicates, uninstall, launch }

struct ContentView: View {
    @EnvironmentObject var s: AppState
    @State private var pane: Pane? = .smart

    var body: some View {
        NavigationSplitView {
            List(selection: $pane) {
                Label("Akıllı Tarama", systemImage: "sparkles").tag(Pane.smart)
                Label("Denetim", systemImage: "stethoscope").tag(Pane.audit)
                Label("Bakım", systemImage: "wrench.and.screwdriver").tag(Pane.maintenance)
                Label("Performans", systemImage: "speedometer").tag(Pane.performance)
                Section("Temizlik") {
                    ForEach(Categories.all) { c in
                        HStack {
                            Label(c.title, systemImage: c.symbol)
                            Spacer()
                            if s.scanning.contains(c.id) { ProgressView().controlSize(.small) }
                            else if s.results[c.id] != nil {
                                Text(s.total(c.id).human).foregroundStyle(.secondary).font(.caption)
                            }
                        }.tag(Pane.category(c.id))
                    }
                }
                Section("Kalıntılar") {
                    Label("Eski Uygulama Kalıntıları", systemImage: "archivebox").tag(Pane.orphans)
                }
                Section("Araçlar") {
                    Label("Büyük Dosyalar", systemImage: "doc.richtext").tag(Pane.large)
                    Label("Kopya Dosyalar", systemImage: "doc.on.doc").tag(Pane.duplicates)
                    Label("Uygulama Kaldırıcı", systemImage: "xmark.app").tag(Pane.uninstall)
                    Label("Başlangıç Öğeleri", systemImage: "power").tag(Pane.launch)
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 240)
        } detail: {
            VStack(spacing: 0) {
                if !s.hasFullDiskAccess { FDABanner() }
                switch pane ?? .smart {
                case .smart: SmartView()
                case .category(let id): CategoryView(cat: Categories.all.first { $0.id == id }!)
                case .large: LargeFilesView()
                case .audit: AuditView()
                case .maintenance: MaintenanceView()
                case .performance: PerformanceView()
                case .orphans: OrphansView()
                case .duplicates: DuplicatesView()
                case .uninstall: UninstallerView()
                case .launch: LaunchAgentsView()
                }
                StatusBar()
            }
        }
        .alert("Magicstone", isPresented: Binding(get: { s.alertMessage != nil },
                                                  set: { if !$0 { s.alertMessage = nil } })) {
            Button("Tamam") { s.alertMessage = nil }
        } message: { Text(s.alertMessage ?? "") }
        .toolbar {
            Toggle(isOn: $s.dryRun) { Label("Önizleme", systemImage: "eye") }
                .toggleStyle(.switch)
                .help("Açıkken hiçbir dosya taşınmaz; yalnızca ne yapılacağı raporlanır.")
        }
    }
}

struct FDABanner: View {
    var body: some View {
        HStack {
            Image(systemName: "lock.shield").foregroundStyle(.orange)
            Text("Tam Disk Erişimi verilmemiş; bazı klasörler taranamayabilir.")
            Spacer()
            Button("Ayarları Aç") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
            }
        }
        .padding(10).background(.orange.opacity(0.1))
    }
}

struct StatusBar: View {
    @EnvironmentObject var s: AppState
    var body: some View {
        HStack {
            Image(systemName: s.dryRun ? "eye" : "trash").foregroundStyle(s.dryRun ? .blue : .red)
            Text(s.lastReport ?? (s.dryRun ? "Önizleme modu açık — hiçbir şey silinmez." : "Gerçek mod: seçilenler Çöp Sepeti'ne taşınır."))
                .lineLimit(2).truncationMode(.tail)
            Spacer()
            Button("Günlüğü Göster") { NSWorkspace.shared.activateFileViewerSelecting([AuditLog.url]) }
                .buttonStyle(.link)
        }
        .font(.callout).padding(8).background(.bar)
    }
}

struct SmartView: View {
    @EnvironmentObject var s: AppState
    @State private var confirm = false

    private var selectedTotal: Int64 {
        Categories.all.filter { $0.id != "trash" }.reduce(Int64(0)) { $0 + s.total($1.id, selectedOnly: true) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 112, height: 112)
                    .padding(.top, 24)
                Text("Magicstone").font(.largeTitle.bold())
                Text("Telemetri yok. Ağ erişimi yok. Her şey bu Mac'te kalır.").foregroundStyle(.secondary)
                DiskBar(info: s.disk)
                    .frame(maxWidth: 520)
                HStack(spacing: 12) {
                    Button { Task { await s.scanAll() } } label: {
                        Label(s.scanning.isEmpty ? "Tara" : "Taranıyor…", systemImage: "magnifyingglass")
                            .frame(width: 140)
                    }
                    .controlSize(.large)
                    .disabled(!s.scanning.isEmpty)
                    Button { confirm = true } label: {
                        Label(s.dryRun ? "Önizle" : "Temizle (\(selectedTotal.human))", systemImage: "sparkles")
                            .frame(minWidth: 140)
                    }
                    .controlSize(.large).buttonStyle(.borderedProminent)
                    .disabled(selectedTotal == 0 || !s.scanning.isEmpty)
                }
                if !s.results.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Categories.all) { c in
                            HStack {
                                Label(c.title, systemImage: c.symbol)
                                Spacer()
                                if s.scanning.contains(c.id) { ProgressView().controlSize(.small) }
                                else {
                                    Text(s.total(c.id, selectedOnly: true).human).monospacedDigit()
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 8).padding(.horizontal, 14)
                            Divider()
                        }
                    }
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
                    .frame(maxWidth: 520)
                    Text("Tek tıkla temizlik Çöp Sepeti'ni kapsamaz; onu kendi bölümünden boşaltın.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 20)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal)
        }
        .task { s.refreshDisk() }
        .confirmationDialog("Seçili \(selectedTotal.human) Çöp Sepeti'ne taşınsın mı?", isPresented: $confirm) {
            Button(s.dryRun ? "Önizle" : "Temizle", role: s.dryRun ? nil : .destructive) {
                Task { await s.cleanAll() }
            }
        } message: { Text("Her kategoride seçili olan öğeler taşınır. Geri almak için Çöp Sepeti'ni açın.") }
    }
}

struct DiskBar: View {
    let info: DiskInfo?
    var body: some View {
        if let d = info {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Başlangıç Diski").font(.headline)
                    Spacer()
                    Text("\(d.free.human) boş / \(d.total.human)").foregroundStyle(.secondary).monospacedDigit()
                }
                ProgressView(value: Double(d.total - d.free), total: Double(max(d.total, 1)))
                    .tint(d.usedRatio > 0.9 ? .red : (d.usedRatio > 0.75 ? .orange : .accentColor))
            }
        }
    }
}

struct ItemRow: View {
    @Binding var item: FileItem
    @State private var kept = false
    var body: some View {
        HStack {
            Toggle("", isOn: $item.selected).labelsHidden()
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path)).resizable().frame(width: 18, height: 18)
            VStack(alignment: .leading) {
                Text(item.name).lineLimit(1)
                Text(item.displayPath).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Text(item.size.human).monospacedDigit().foregroundStyle(.secondary)
            Button { NSWorkspace.shared.activateFileViewerSelecting([item.url]) } label: {
                Image(systemName: "magnifyingglass")
            }.buttonStyle(.borderless).help("Finder'da göster")
        }
        .opacity(kept ? 0.4 : 1)
        .contextMenu {
            Button("Finder'da Göster") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
            Button(kept ? "Tut listesinden çıkar" : "Tut (bir daha önerme)") {
                if kept { KeepList.remove(item.url.standardizedFileURL.path) } else { KeepList.add(item.url) }
                item.selected = false
                kept.toggle()
            }
        }
        .onAppear { kept = KeepList.contains(item.url) }
    }
}

struct CategoryView: View {
    @EnvironmentObject var s: AppState
    let cat: CleanCategory
    @State private var confirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    Text(cat.title).font(.title2.bold())
                    Text(cat.detail).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Yeniden Tara") { Task { await s.scan(cat) } }
                Button(s.dryRun ? "Önizle" : "Temizle (\(s.total(cat.id, selectedOnly: true).human))") { confirm = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(s.total(cat.id, selectedOnly: true) == 0)
            }.padding()
            SelectionBar(items: Binding(get: { s.results[cat.id] ?? [] }, set: { s.results[cat.id] = $0 }))
                .padding(.horizontal).padding(.bottom, 6)
            List {
                ForEach(Binding(get: { s.results[cat.id] ?? [] }, set: { s.results[cat.id] = $0 })) { $item in
                    ItemRow(item: $item)
                }
            }
            .overlay { if s.results[cat.id] == nil { Text("Henüz taranmadı").foregroundStyle(.secondary) } }
        }
        .task { if s.results[cat.id] == nil { await s.scan(cat) } }
        .confirmationDialog(confirmTitle, isPresented: $confirm) {
            Button(s.dryRun ? "Önizle" : "Devam", role: s.dryRun ? nil : .destructive) { Task { await s.clean(cat) } }
        } message: {
            Text(cat.id == "trash" && !s.dryRun ? "Çöp Sepeti kalıcı olarak boşaltılacak. Geri alınamaz." :
                 "Seçilen öğeler Çöp Sepeti'ne taşınır; oradan geri alabilirsiniz.")
        }
    }
    var confirmTitle: String {
        "\(s.results[cat.id]?.filter(\.selected).count ?? 0) öğe, \(s.total(cat.id, selectedOnly: true).human)"
    }
}

struct LargeFilesView: View {
    @EnvironmentObject var s: AppState
    @State private var confirm = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Büyük Dosyalar").font(.title2.bold())
                Spacer()
                Text("En az")
                TextField("", value: $s.largeMinMB, format: .number).frame(width: 70)
                Text("MB")
                Button(s.largeScanning ? "Taranıyor… \(s.largeProgress)" : "Tara") { Task { await s.scanLarge() } }
                    .disabled(s.largeScanning)
                Button(s.dryRun ? "Önizle" : "Çöpe Taşı") { confirm = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(!s.largeFiles.contains(where: \.selected))
            }.padding()
            SelectionBar(items: $s.largeFiles).padding(.horizontal).padding(.bottom, 6)
            List { ForEach($s.largeFiles) { $i in ItemRow(item: $i) } }
        }
        .confirmationDialog("Seçilen dosyalar Çöp Sepeti'ne taşınsın mı?", isPresented: $confirm) {
            Button(s.dryRun ? "Önizle" : "Taşı", role: s.dryRun ? nil : .destructive) { Task { await s.trashLarge() } }
        }
    }
}

struct UninstallerView: View {
    @EnvironmentObject var s: AppState
    @State private var confirm = false
    var body: some View {
        HSplitView {
            List(s.apps, selection: Binding(get: { s.selectedApp?.id }, set: { id in
                if let a = s.apps.first(where: { $0.id == id }) { Task { await s.select(a) } }
            })) { app in
                HStack {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path)).resizable().frame(width: 20, height: 20)
                    Text(app.name); Spacer()
                    Text(app.size.human).font(.caption).foregroundStyle(.secondary)
                }.tag(app.id)
            }.frame(minWidth: 240)
            VStack(alignment: .leading) {
                if let app = s.selectedApp {
                    HStack {
                        Text(app.name).font(.title2.bold())
                        Spacer()
                        Button(s.dryRun ? "Önizle" : "Kaldır") { confirm = true }.buttonStyle(.borderedProminent)
                    }
                    Text(app.bundleID ?? "—").font(.caption).foregroundStyle(.secondary)
                    Text("\(s.leftovers.count) ilgili öğe bulundu (\(s.leftovers.reduce(Int64(0)) { $0 + $1.size }.human)). Paket kimliğiyle eşleşenler seçili; yalnızca adla eşleşenleri kontrol edip işaretleyin. /Library öğeleri için yönetici parolası istenir.")
                        .font(.callout).padding(.top, 6)
                    SelectionBar(items: $s.leftovers)
                    List { ForEach($s.leftovers) { $i in ItemRow(item: $i) } }
                } else {
                    Text("Bir uygulama seçin").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }.padding()
        }
        .task { if s.apps.isEmpty { await s.loadApps() } }
        .confirmationDialog("Uygulama ve seçili dosyaları Çöp Sepeti'ne taşınsın mı?", isPresented: $confirm) {
            Button(s.dryRun ? "Önizle" : "Kaldır", role: s.dryRun ? nil : .destructive) { Task { await s.uninstall() } }
        } message: { Text("Uygulama açıksa önce kapatın.") }
    }
}
