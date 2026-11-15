import SwiftUI
import AppKit

struct AuditView: View {
    @State private var text = ""
    @State private var file: URL?
    @State private var running = false
    @State private var step = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Denetim").font(.title2.bold())
                    Text("Önce ölç, sonra öner: salt-okunur sistem raporu. Hiçbir şey değiştirilmez.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let file {
                    Button("Raporu Göster") { NSWorkspace.shared.activateFileViewerSelecting([file]) }
                }
                Button {
                    Task { await run() }
                } label: {
                    Label(running ? "Denetleniyor… \(step)" : "Denetle", systemImage: "stethoscope")
                }
                .buttonStyle(.borderedProminent).disabled(running)
            }.padding()
            ScrollView {
                Text(text.isEmpty ? "Henüz denetim yapılmadı." : text)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .background(.quaternary.opacity(0.3))
        }
    }

    private func run() async {
        running = true
        let res = await Task.detached(priority: .userInitiated) {
            Audit.run { s in Task { @MainActor in step = s } }
        }.value
        text = res.text; file = res.file
        running = false
    }
}
