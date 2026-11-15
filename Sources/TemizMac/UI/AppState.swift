import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    // Önizleme (dry-run) varsayılan olarak AÇIK: hiçbir şey taşınmaz/silinmez, sadece raporlanır.
    @Published var dryRun = true
    @Published var results: [String: [FileItem]] = [:]
    @Published var scanning: Set<String> = []
    @Published var lastReport: String?

    @Published var largeFiles: [FileItem] = []
    @Published var largeMinMB: Double = 500
    @Published var largeScanning = false
    @Published var largeProgress = 0

    @Published var apps: [InstalledApp] = []
    @Published var selectedApp: InstalledApp?
    @Published var leftovers: [FileItem] = []

    var hasFullDiskAccess: Bool {
        // Sezgisel kontrol: FDA olmadan bu dizin okunamaz.
        let probe = SafetyGuard.home.appendingPathComponent("Library/Safari")
        return (try? FileManager.default.contentsOfDirectory(atPath: probe.path)) != nil
    }

    func scan(_ cat: CleanCategory) async {
        scanning.insert(cat.id)
        let items = await Task.detached(priority: .userInitiated) { DiskScanner.scan(cat) }.value
        results[cat.id] = items
        scanning.remove(cat.id)
    }

    func scanAll() async {
        await withTaskGroup(of: Void.self) { g in
            for c in Categories.all { g.addTask { await self.scan(c) } }
        }
    }

    func total(_ id: String, selectedOnly: Bool = false) -> Int64 {
        (results[id] ?? []).filter { !selectedOnly || $0.selected }.reduce(0) { $0 + $1.size }
    }

    func clean(_ cat: CleanCategory) async {
        let sel = (results[cat.id] ?? []).filter(\.selected)
        let dry = dryRun
        let permanent = cat.id == "trash"
        let r = await Task.detached { Cleaner.clean(sel, allowedRoots: cat.roots, permanent: permanent, dryRun: dry) }.value
        report(r, dry: dry)
        if !dry { await scan(cat) }
    }

    func scanLarge() async {
        largeScanning = true; largeProgress = 0
        let min = Int64(largeMinMB * 1_048_576)
        let items = await Task.detached(priority: .userInitiated) {
            DiskScanner.largeFiles(minBytes: min) { n in Task { @MainActor in self.largeProgress = n } }
        }.value
        largeFiles = items
        largeScanning = false
    }

    func trashLarge() async {
        let sel = largeFiles.filter(\.selected)
        let dry = dryRun
        let r = await Task.detached { Cleaner.clean(sel, allowedRoots: [SafetyGuard.home], dryRun: dry) }.value
        report(r, dry: dry)
        if !dry { largeFiles.removeAll { r.trashed.contains($0.url) } }
    }

    func loadApps() async {
        apps = await Task.detached { Uninstaller.installedApps() }.value
    }

    func select(_ app: InstalledApp) async {
        selectedApp = app
        leftovers = await Task.detached { Uninstaller.leftovers(for: app) }.value
    }

    func uninstall() async {
        guard let app = selectedApp else { return }
        let appItem = FileItem(url: app.url, size: app.size, modified: nil)
        let sel = [appItem] + leftovers.filter(\.selected)
        let dry = dryRun
        let r = await Task.detached {
            Cleaner.clean(sel, allowedRoots: nil, allowApplications: true, dryRun: dry)
        }.value
        report(r, dry: dry)
        if !dry { selectedApp = nil; leftovers = []; await loadApps() }
    }

    private func report(_ r: CleanReport, dry: Bool) {
        let verb = dry ? "Önizleme: taşınacaktı" : "Temizlendi"
        var s = "\(verb) \(r.trashed.count) öğe, \(r.freedBytes.human)."
        if !r.skipped.isEmpty { s += " \(r.skipped.count) öğe atlandı (günlüğe bakın)." }
        lastReport = s
    }
}
