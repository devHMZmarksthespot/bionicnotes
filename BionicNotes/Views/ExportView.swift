import SwiftUI

/// Export einer Session: Format + Inhalte wählen → Datei wird lokal erzeugt →
/// erst durch „Teilen“ oder „In Dateien sichern“ verlässt sie die App.
struct ExportView: View {
    let content: SessionContent
    @Environment(\.dismiss) private var dismiss

    @State private var format: ExportFormat = .pdf
    @State private var options: ExportOptions
    @State private var exportedURL: URL?
    @State private var isExporting = false
    @State private var errorMessage: String?
    @State private var isMoverShown = false

    init(content: SessionContent, summaryID: UUID? = nil) {
        self.content = content
        var options = ExportOptions()
        options.summaryID = summaryID ?? content.summaries.first?.id
        options.includeTranscript = options.summaryID == nil
        _options = State(initialValue: options)
    }

    private var availableFormats: [ExportFormat] {
        ExportFormat.allCases.filter { format in
            switch format {
            case .audio: content.hasAudio
            case .srt: !content.segments.isEmpty
            default: true
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Format") {
                    ForEach(availableFormats) { item in
                        Button { format = item } label: {
                            HStack(spacing: 12) {
                                Image(systemName: item.symbol).frame(width: 28).foregroundStyle(.tint)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title).foregroundStyle(.primary)
                                    Text(item.detail).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if item == format { Image(systemName: "checkmark").foregroundStyle(.tint) }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                if format.usesOptions {
                    Section("Inhalt") {
                        if !content.summaries.isEmpty {
                            Picker("Zusammenfassung", selection: $options.summaryID) {
                                Text("Keine").tag(UUID?.none)
                                ForEach(content.summaries) { Text($0.template.title).tag(Optional($0.id)) }
                            }
                        }
                        if !content.markers.isEmpty {
                            Toggle("⭐ Markierte Momente", isOn: $options.includeMarkers)
                        }
                        if content.hasNotes {
                            Toggle("Handnotizen", isOn: $options.includeNotes)
                        }
                        if !content.photos.isEmpty {
                            Toggle(format.supportsImages ? "Fotos & Folien" : "Folientexte", isOn: $options.includePhotos)
                        }
                        if !content.segments.isEmpty {
                            Toggle("Ganzes Transkript", isOn: $options.includeTranscript)
                        }
                    }
                }

                Section {
                    if let exportedURL {
                        ShareLink(item: exportedURL) {
                            Label("Teilen …", systemImage: "square.and.arrow.up")
                        }
                        Button { isMoverShown = true } label: {
                            Label("In „Dateien“ sichern", systemImage: "folder")
                        }
                    } else {
                        Button(action: runExport) {
                            HStack {
                                Label("Datei erstellen", systemImage: "doc.badge.arrow.up")
                                if isExporting { Spacer(); ProgressView() }
                            }
                        }
                        .disabled(isExporting)
                    }
                } footer: {
                    Label("Die Datei wird auf dem Gerät erstellt. Sie verlässt es nur, wenn du sie teilst oder in einen Cloud-Ordner sicherst.",
                          systemImage: "lock.shield")
                }
            }
            .navigationTitle("Exportieren")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fertig") { dismiss() } }
            }
            .onChange(of: format) { exportedURL = nil }
            .onChange(of: options) { exportedURL = nil }
            .fileMover(isPresented: $isMoverShown, file: exportedURL) { result in
                // Datei wurde verschoben → für weiteres Teilen neu erstellen
                if case .success = result { exportedURL = nil }
            }
            .alert("Export fehlgeschlagen", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func runExport() {
        isExporting = true
        Task {
            defer { isExporting = false }
            // Die Bild-Aufbereitung soll das Sheet erst zeichnen lassen.
            await Task.yield()
            do {
                exportedURL = try await SessionExporter.export(content, format: format, options: options)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
