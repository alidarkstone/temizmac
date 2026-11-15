import SwiftUI
import AppKit

struct LaunchAgentsView: View {
    @EnvironmentObject var s: AppState
    @State private var items: [LaunchItem] = []
    @State private var loading = false
    @State private var confirm = false

    private var selected: [LaunchItem] { items.filter { $0.isUser && $0.selected } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Başlangıç Öğeleri").font(.title2.bold())
                    Text("Arka planda çalışan ajanlar. \"Yetim\": ait olduğu uygulama silinmiş.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Tümünü Seç") { for i in items.indices where items[i].isUser { items[i].selected = true } }
                    .disabled(!items.contains(where: \.isUser))
                Button("Seçimi Kaldır") { for i in items.indices { items[i].selected = false } }
                    .disabled(selected.isEmpty)
                Button("Yenile") { Task { await load() } }.disabled(loading)
                Button(s.dryRun ? "Önizle" : "Seçilenleri Kaldır") { confirm = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(selected.isEmpty)
            }.padding()
            List {
                ForEach($items) { $item in
                    HStack {
                        Toggle("", isOn: $item.selected).labelsHidden().disabled(!item.isUser)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(item.label).lineLimit(1)
                                if item.orphaned { Badge(text: "Yetim", color: .red) }
                                if !item.isUser { Badge(text: "Sistem geneli", color: .gray) }
                            }
                            Text(item.program ?? "—").font(.caption).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Button { NSWorkspace.shared.activateFileViewerSelecting([item.url]) } label: {
                            Image(systemName: "magnifyingglass")
                        }.buttonStyle(.borderless).help("Finder'da göster")
                    }
                }
            }
            .overlay { if loading { ProgressView() } else if items.isEmpty { Text("Öğe bulunamadı").foregroundStyle(.secondary) } }
        }
        .task { if items.isEmpty { await load() } }
        .confirmationDialog("\(selected.count) başlangıç öğesi durdurulup Çöp Sepeti'ne taşınsın mı?",
                            isPresented: $confirm) {
            Button(s.dryRun ? "Önizle" : "Kaldır", role: s.dryRun ? nil : .destructive) {
                let sel = selected, dry = s.dryRun
                Task {
                    let r = await Task.detached { LaunchAgents.remove(sel, dryRun: dry) }.value
                    s.report(r, dry: dry)
                    if !dry { await load() }
                }
            }
        } message: { Text("Sistem geneli öğeler yalnızca görüntülenir; kaldırılmaz.") }
    }

    private func load() async {
        loading = true
        items = await Task.detached { LaunchAgents.scan() }.value
        loading = false
    }
}

struct Badge: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text).font(.caption2.bold())
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }
}
