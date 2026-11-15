import SwiftUI
import AppKit

struct DuplicatesView: View {
    @EnvironmentObject var s: AppState
    @State private var root: URL = SafetyGuard.home
    @State private var minMB: Double = 1
    @State private var groups: [DuplicateGroup] = []
    @State private var scanned = false
    @State private var scanning = false
    @State private var cleaning = false
    @State private var progressText = ""
    @State private var finderTask: Task<[DuplicateGroup], Never>?
    @State private var confirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Kopya Dosyalar").font(.title2.bold())
                Spacer()
                Button(s.dryRun ? "Önizle" : "Seçilenleri Çöpe Taşı") { confirm = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(scanning || cleaning || selectedCount == 0)
            }
            .padding([.horizontal, .top])

            HStack {
                Button { pickFolder() } label: {
                    Label("Klasör Seç", systemImage: "folder")
                }
                .disabled(scanning)
                Text(displayRoot)
                    .lineLimit(1).truncationMode(.middle)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("En az")
                TextField("", value: $minMB, format: .number).frame(width: 60)
                Text("MB")
                if scanning {
                    ProgressView().controlSize(.small)
                    Button("Durdur") { finderTask?.cancel() }
                } else {
                    Button("Tara") { startScan() }
                        .disabled(cleaning)
                }
            }
            .padding()

            HStack {
                if scanning {
                    Text(progressText).foregroundStyle(.secondary)
                } else if scanned {
                    Text("\(groups.count) grup, \(totalWasted.human) boşa harcanan")
                        .font(.headline)
                }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            if !groups.isEmpty {
                HStack {
                    let sel = groups.flatMap(\.files).filter(\.selected)
                    Text("\(sel.count) dosya seçili · \(sel.reduce(Int64(0)) { $0 + $1.size }.human)")
                        .monospacedDigit().foregroundStyle(.secondary)
                    Spacer()
                    Button("Tüm kopyaları seç (her grupta biri kalır)") {
                        for g in groups.indices {
                            for f in groups[g].files.indices { groups[g].files[f].selected = f != 0 }
                        }
                    }
                    Button("Seçimi Kaldır") {
                        for g in groups.indices {
                            for f in groups[g].files.indices { groups[g].files[f].selected = false }
                        }
                    }
                }
                .font(.callout).controlSize(.small)
                .padding(.horizontal).padding(.bottom, 6)
            }
            List {
                ForEach($groups) { $group in
                    Section {
                        ForEach($group.files) { $item in
                            ItemRow(item: $item)
                        }
                    } header: {
                        HStack {
                            Text(group.files.first?.name ?? "").lineLimit(1)
                            Spacer()
                            Text(group.wasted.human).monospacedDigit()
                        }
                    }
                }
            }
            .overlay {
                if !scanning && groups.isEmpty {
                    Text(scanned ? "Kopya dosya bulunamadı" : "Henüz taranmadı")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onDisappear { finderTask?.cancel() }
        .confirmationDialog(confirmTitle, isPresented: $confirm) {
            Button(s.dryRun ? "Önizle" : "Çöpe Taşı", role: s.dryRun ? nil : .destructive) {
                performClean()
            }
        } message: {
            Text("Her grupta en az bir kopya korunur. Seçilen dosyalar Çöp Sepeti'ne taşınır; oradan geri alabilirsiniz.")
        }
    }

    // MARK: - Hesaplananlar

    private var displayRoot: String {
        root.path.replacingOccurrences(of: SafetyGuard.home.path, with: "~")
    }

    private var totalWasted: Int64 {
        groups.reduce(Int64(0)) { $0 + $1.wasted }
    }

    private var selectedCount: Int {
        groups.reduce(0) { acc, g in acc + g.files.filter { $0.selected }.count }
    }

    private var selectedBytes: Int64 {
        var total: Int64 = 0
        for g in groups { for f in g.files where f.selected { total += f.size } }
        return total
    }

    private var confirmTitle: String {
        "\(selectedCount) dosya, \(selectedBytes.human)"
    }

    // MARK: - Eylemler

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = root
        panel.prompt = "Seç"
        if panel.runModal() == .OK, let url = panel.url {
            root = url.standardizedFileURL
            groups = []
            scanned = false
        }
    }

    private func startScan() {
        finderTask?.cancel()
        let rootURL = root
        let mb = minMB.isFinite ? max(minMB, 0) : 1
        let minBytes = Int64(mb * 1_048_576)
        groups = []
        scanned = false
        scanning = true
        progressText = "Başlatılıyor…"

        let update: (String) -> Void = { msg in
            Task { @MainActor in
                if scanning { progressText = msg }
            }
        }
        let task = Task.detached(priority: .userInitiated) { () -> [DuplicateGroup] in
            DuplicateFinder.find(in: rootURL, minBytes: minBytes, progress: update)
        }
        finderTask = task

        Task { @MainActor in
            let result = await task.value
            // Daha yeni bir tarama başladıysa bu sonucu yok say.
            guard finderTask == task else { return }
            if task.isCancelled {
                groups = []
                scanned = false
            } else {
                groups = result
                scanned = true
            }
            scanning = false
            finderTask = nil
        }
    }

    private func performClean() {
        // Güvenlik: bir grubun tüm kopyaları asla seçili olamaz.
        var fixed = groups
        for gi in fixed.indices {
            let files = fixed[gi].files
            if !files.isEmpty && files.allSatisfy({ $0.selected }) {
                fixed[gi].files[0].selected = false
            }
        }
        groups = fixed

        var items: [FileItem] = []
        for g in fixed { items.append(contentsOf: g.files.filter { $0.selected }) }
        guard !items.isEmpty else { return }

        let dry = s.dryRun
        let appState = s
        cleaning = true
        Task { @MainActor in
            let r = await Task.detached(priority: .userInitiated) {
                Cleaner.clean(items, allowedRoots: [SafetyGuard.home], dryRun: dry)
            }.value
            appState.report(r, dry: dry)
            if !dry {
                let gone = Set(r.trashed.map { $0.standardizedFileURL.path })
                var updated = groups
                for gi in updated.indices {
                    updated[gi].files.removeAll { gone.contains($0.url.standardizedFileURL.path) }
                }
                updated.removeAll { $0.files.count < 2 }
                updated.sort { $0.wasted > $1.wasted }
                groups = updated
            }
            cleaning = false
        }
    }
}
