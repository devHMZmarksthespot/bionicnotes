import SwiftUI

/// Fotos/Folien einer Session als Vorschaubilder in einer Zeile. Tippen öffnet die Detailansicht.
struct PhotoStripView: View {
    let store: PhotoStore
    let onOpen: (SessionPhoto) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.photos) { photo in
                    Button { onOpen(photo) } label: {
                        ZStack(alignment: .bottomLeading) {
                            if let thumb = store.thumbnail(for: photo) {
                                Image(uiImage: thumb)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                Color.secondary.opacity(0.2)
                            }
                            HStack(spacing: 3) {
                                Image(systemName: photo.kind == .slide ? "doc.viewfinder" : "camera.fill")
                                if let time = photo.time { Text(time.clockString).monospacedDigit() }
                            }
                            .font(.caption2.bold())
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(4)
                        }
                        .frame(width: 72, height: 54)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(photo.kind == .slide ? "Folie" : "Foto")
                }
            }
        }
    }
}

/// Großansicht eines Fotos mit Zeit, erkanntem Text, Sprung und Löschen.
struct PhotoDetailView: View {
    let photo: SessionPhoto
    let store: PhotoStore
    let onJump: ((TimeInterval) -> Void)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let image = store.image(for: photo) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    if let text = currentText, !text.isEmpty {
                        Text("Erkannter Text").font(.headline)
                        Text(text)
                            .font(.callout)
                            .textSelection(.enabled)
                    } else if photo.kind == .slide && currentText == nil {
                        Label("Text wird erkannt …", systemImage: "text.viewfinder")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle(photo.time.map { "\(photo.kind == .slide ? "Folie" : "Foto") bei \($0.clockString)" } ?? "Foto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig") { dismiss() }
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    if let onJump, let time = photo.time {
                        Button {
                            onJump(time)
                            dismiss()
                        } label: {
                            Label("Zur Stelle springen", systemImage: "play.circle.fill")
                        }
                    }
                    Spacer()
                    Button(role: .destructive) {
                        store.remove(photo)
                        dismiss()
                    } label: {
                        Label("Löschen", systemImage: "trash")
                    }
                }
            }
        }
    }

    /// Aktueller Stand aus dem Store (OCR kommt evtl. erst nach dem Öffnen).
    private var currentText: String? {
        store.photos.first { $0.id == photo.id }?.recognizedText
    }
}
