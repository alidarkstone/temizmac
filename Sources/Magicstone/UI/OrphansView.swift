import SwiftUI

struct OrphansView: View {
    @EnvironmentObject var s: AppState
    @State private var sure: [FileItem] = []
    @State private var maybe: [FileItem] = []
    @State private var scanned = false
    @State private var loading = false
    @State private var confirm = false

    private var selected: [FileItem] { (sure + maybe).filter(\.selected) }
    private var selectedSize: Int64 { selected.reduce(0) { $0 + $1.size } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Eski Uygulama Kalıntıları").font(.title2.bold())
                    Text("Bu Mac'ten daha önce kaldırılmış uygulamaların ~/Library ve /Library'de bıraktığı klasör ve kayıtlar.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(loading ? "Taranıyor…" : "Tara") { Task { await load() } }.disabled(loading)
                Button(s.dryRun ? "Önizle" : "Temizle (\(selectedSize.human))") { confirm = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(selected.isEmpty || loading)
            }.padding()
            List {
                if !sure.isEmpty {
                    Section {
                        ForEach($sure) { $i in ItemRow(item: $i) }
                    } header: {
                        SelectionBar(items: $sure, title: "Kesin kalıntılar")
                    }
                }
                if !maybe.isEmpty {
                    Section {
                        ForEach($maybe) { $i in ItemRow(item: $i) }
                    } header: {
                        VStack(alignment: .leading, spacing: 2) {
                            SelectionBar(items: $maybe, title: "Kontrol edin")
                            Text("Aynı firmanın başka ürünü kurulu ya da yakın zamanda kullanılmış. Tek tek bakmanız önerilir.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .overlay {
                if loading { ProgressView("Kurulu uygulamalar ve kitaplık taranıyor…") }
                else if scanned && sure.isEmpty && maybe.isEmpty { Text("Kalıntı bulunamadı 🎉").foregroundStyle(.secondary) }
                else if !scanned { Text("Taramak için \"Tara\"ya basın").foregroundStyle(.secondary) }
            }
        }
        .confirmationDialog("\(selected.count) öğe (\(selectedSize.human)) Çöp Sepeti'ne taşınsın mı?", isPresented: $confirm) {
            Button(s.dryRun ? "Önizle" : "Taşı", role: s.dryRun ? nil : .destructive) {
                let sel = selected, dry = s.dryRun
                Task {
                    let r = await Task.detached {
                        Cleaner.clean(sel, allowedRoots: nil, allowApplications: true, dryRun: dry)
                    }.value
                    s.report(r, dry: dry)
                    if !dry { await load() }
                }
            }
        } message: { Text("/Library öğeleri için bir kez yönetici parolası istenir. Hepsi Çöp Sepeti'nden geri alınabilir.") }
    }

    private func load() async {
        loading = true
        let r = await Task.detached(priority: .userInitiated) { OrphanScanner.scan() }.value
        sure = r.sure; maybe = r.maybe
        scanned = true; loading = false
    }
}
