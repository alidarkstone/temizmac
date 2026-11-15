import SwiftUI
import AppKit

enum Pane: Hashable { case smart, category(String), large, uninstall }

struct ContentView: View {
    @EnvironmentObject var s: AppState
    @State private var pane: Pane? = .smart

    var body: some View {
        NavigationSplitView {
            List(selection: $pane) {
                Label("Akıllı Tarama", systemImage: "sparkles").tag(Pane.smart)
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
                Section("Araçlar") {
                    Label("Büyük Dosyalar", systemImage: "doc.richtext").tag(Pane.large)
                    Label("Uygulama Kaldırıcı", systemImage: "xmark.app").tag(Pane.uninstall)
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
                case .uninstall: UninstallerView()
                }
                StatusBar()
            }
        }
        .alert("Cleanstone", isPresented: Binding(get: { s.alertMessage != nil },
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
            Spacer()
            Button("Günlüğü Göster") { NSWorkspace.shared.activateFileViewerSelecting([AuditLog.url]) }
                .buttonStyle(.link)
        }
        .font(.callout).padding(8).background(.bar)
    }
}

struct SmartView: View {
    @EnvironmentObject var s: AppState
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 128, height: 128)
            Text("Cleanstone").font(.largeTitle.bold())
            Text("Telemetri yok. Ağ erişimi yok. Her şey bu Mac'te kalır.").foregroundStyle(.secondary)
            Button {
                Task { await s.scanAll() }
            } label: { Text("Tara").frame(width: 140) }
            .controlSize(.large).buttonStyle(.borderedProminent)
            .disabled(!s.scanning.isEmpty)
            if !s.results.isEmpty {
                let total = Categories.all.reduce(Int64(0)) { $0 + s.total($1.id, selectedOnly: true) }
                Text("Temizlenebilir (seçili): \(total.human)").font(.title3)
            }
            Spacer()
        }.frame(maxWidth: .infinity)
    }
}

struct ItemRow: View {
    @Binding var item: FileItem
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
                    Text("İlgili dosyalar (Application Support ve Containers varsayılan olarak seçili değildir):")
                        .font(.callout).padding(.top, 6)
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
