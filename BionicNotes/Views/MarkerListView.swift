import SwiftUI

/// ⭐-Marker als kompakte Chips in einer Zeile. In der Wiedergabe springt Tippen an die Stelle;
/// gedrückt halten zeigt den Transkript-Ausschnitt und „Löschen“.
struct MarkerListView: View {
    let markers: [SessionMarker]
    let onSelect: ((SessionMarker) -> Void)?
    let onDelete: (SessionMarker) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(markers) { marker in
                    chip(marker)
                        .contextMenu {
                            if !marker.snippet.isEmpty {
                                Text("… " + marker.snippet)
                            }
                            Button("Marker löschen", systemImage: "trash", role: .destructive) { onDelete(marker) }
                        }
                }
            }
        }
    }

    private func chip(_ marker: SessionMarker) -> some View {
        Button {
            onSelect?(marker)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "star.fill")
                Text(marker.time.clockString).monospacedDigit()
                if marker.source == .watch {
                    Image(systemName: "applewatch").font(.caption2)
                }
            }
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.yellow.opacity(0.18)))
            .foregroundStyle(.yellow)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Marker bei \(marker.time.clockString)")
    }
}
