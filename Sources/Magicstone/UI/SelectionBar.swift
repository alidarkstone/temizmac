import SwiftUI

/// Sonuç listeleri için "Tümünü Seç / Seçimi Kaldır" çubuğu, seçili sayı ve boyut.
struct SelectionBar: View {
    @Binding var items: [FileItem]
    var title: String? = nil

    private var selected: [FileItem] { items.filter(\.selected) }

    var body: some View {
        HStack(spacing: 10) {
            if let title { Text(title).font(.headline) }
            Text("\(selected.count)/\(items.count) seçili · \(selected.reduce(Int64(0)) { $0 + $1.size }.human)")
                .monospacedDigit().foregroundStyle(.secondary)
            Spacer()
            Button("Tümünü Seç") { setAll(true) }
                .disabled(items.isEmpty || selected.count == items.count)
            Button("Seçimi Kaldır") { setAll(false) }
                .disabled(selected.isEmpty)
        }
        .font(.callout)
        .controlSize(.small)
    }

    private func setAll(_ on: Bool) {
        for i in items.indices where !(on && KeepList.contains(items[i].url)) {
            items[i].selected = on
        }
    }
}
