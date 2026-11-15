import SwiftUI
import AppKit

@main
struct MagicstoneApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        Window("Magicstone", id: "main") {
            ContentView()
                .environmentObject(state)
                .frame(minWidth: 900, minHeight: 580)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Temizlik") {
                Button("Tümünü Tara") { Task { await state.scanAll() } }
                    .keyboardShortcut("r", modifiers: [.command])
                Toggle("Önizleme Modu", isOn: $state.dryRun)
                    .keyboardShortcut("p", modifiers: [.command, .shift])
            }
        }

        MenuBarExtra {
            MenuBarContent().environmentObject(state)
        } label: {
            Image(systemName: "sparkles")
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarContent: View {
    @EnvironmentObject var s: AppState
    @Environment(\.openWindow) private var openWindow

    private var junk: Int64 {
        Categories.all.filter { $0.id != "trash" }.reduce(Int64(0)) { $0 + s.total($1.id, selectedOnly: true) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 32, height: 32)
                VStack(alignment: .leading) {
                    Text("Magicstone").font(.headline)
                    Text(s.dryRun ? "Önizleme modu açık" : "Gerçek mod").font(.caption)
                        .foregroundStyle(s.dryRun ? .blue : .red)
                }
            }
            DiskBar(info: s.disk)
            HStack {
                Text(s.results.isEmpty ? "Henüz taranmadı" : "Temizlenebilir: \(junk.human)")
                Spacer()
                if !s.scanning.isEmpty { ProgressView().controlSize(.small) }
            }.font(.callout)
            HStack {
                Button("Tara") { Task { await s.scanAll(); s.refreshDisk() } }
                    .disabled(!s.scanning.isEmpty)
                Spacer()
                Button("Magicstone'u Aç") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }.buttonStyle(.borderedProminent)
            }
            Divider()
            Button("Çıkış") { NSApp.terminate(nil) }.buttonStyle(.link)
        }
        .padding(14)
        .frame(width: 300)
        .onAppear { s.refreshDisk() }
    }
}
