import SwiftUI

/// ⭐-Marker einer Session mit Zeit und Transkript-Ausschnitt.
/// In der Wiedergabe springt Tippen an die Stelle.
struct MarkerListView: View {
    let markers: [SessionMarker]
    let onSelect: ((SessionMarker) -> Void)?
    let onDelete: (SessionMarker) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Marker (\(markers.count))", systemImage: "star.fill")
                .font(.caption.bold())
                .foregroundStyle(.yellow)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(markers) { marker in
                        row(marker)
                            .contextMenu {
                                Button("Marker löschen", systemImage: "trash", role: .destructive) { onDelete(marker) }
                            }
                    }
                }
            }
            .frame(maxHeight: 140)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func row(_ marker: SessionMarker) -> some View {
        let content = HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(marker.time.clockString)
                .font(.caption.monospacedDigit().bold())
            Image(systemName: marker.source == .watch ? "applewatch" : "iphone")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(marker.snippet.isEmpty ? "(kein Transkript)" : "… " + marker.snippet)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.yellow.opacity(0.12)))

        if let onSelect {
            Button { onSelect(marker) } label: { content }.buttonStyle(.plain)
        } else {
            content
        }
    }
}
