import SwiftUI

/// Nachbearbeitung: Vorlage wählen → Zusammenfassung on-device erzeugen → ansehen, bearbeiten, exportieren.
struct SummaryView: View {
    @State private var content: SessionContent
    let store: SummaryStore
    /// Gesetzt, wenn eine Aufnahme vorhanden ist → Nachtranskription anbieten.
    let retranscribe: Retranscriber.Input?
    @Environment(\.dismiss) private var dismiss
    @State private var isWhisper = false
    @State private var hasLiveBackup = false

    init(content: SessionContent, store: SummaryStore, retranscribe: Retranscriber.Input? = nil) {
        _content = State(initialValue: content)
        self.store = store
        self.retranscribe = retranscribe
    }

    @State private var path: [UUID] = []
    @State private var progress: SummaryGenerator.Progress?
    @State private var task: Task<Void, Never>?
    @State private var errorMessage: String?
    @State private var notice: String?
    @State private var exportTarget: ExportTarget?

    private struct ExportTarget: Identifiable {
        let id: UUID
    }

    private var availability: SummaryGenerator.Availability {
        SummaryGenerator.availability(language: content.language)
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if let retranscribe {
                    RetranscribeSection(input: retranscribe, isWhisper: isWhisper,
                                        hasLiveBackup: hasLiveBackup, hasSummaries: !store.summaries.isEmpty)
                }
                if !store.summaries.isEmpty {
                    Section("Erstellt") {
                        ForEach(store.summaries) { summary in
                            NavigationLink(value: summary.id) {
                                Label {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(summary.template.title)
                                        Text(summary.createdAt.formatted(date: .abbreviated, time: .shortened)
                                             + (summary.isEdited ? " · bearbeitet" : ""))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                } icon: {
                                    Image(systemName: summary.template.symbol)
                                }
                            }
                        }
                        .onDelete { offsets in offsets.map { store.summaries[$0] }.forEach(store.remove) }
                    }
                }

                Section {
                    ForEach(SummaryTemplate.allCases) { template in
                        Button { generate(template) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: template.symbol)
                                    .font(.title3)
                                    .frame(width: 32)
                                    .foregroundStyle(.tint)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(template.title).foregroundStyle(.primary)
                                    Text(template.subtitle).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if store.summary(for: template) != nil {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                        .accessibilityLabel("Bereits erstellt")
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        .disabled(progress != nil)
                    }
                } header: {
                    Text("Vorlage wählen")
                } footer: {
                    availabilityFooter
                }
            }
            .navigationTitle("Nachbearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .navigationDestination(for: UUID.self) { id in
                SummaryEditorView(store: store, summaryID: id, notice: $notice,
                                  onRegenerate: { generate($0) }, onExport: { exportTarget = ExportTarget(id: $0.id) })
            }
            .overlay {
                if let progress { GeneratingOverlay(progress: progress, onCancel: cancel) }
            }
            .alert("Zusammenfassung nicht möglich", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .sheet(item: $exportTarget) { target in
            ExportView(content: contentWithSummaries, summaryID: target.id)
        }
        .interactiveDismissDisabled(progress != nil)
        .onDisappear { task?.cancel() }
        .onAppear(perform: reloadTranscript)
        .onChange(of: Retranscriber.shared.revision) { reloadTranscript() }
    }

    @ViewBuilder
    private var availabilityFooter: some View {
        if OpenAIClient.isEnabled {
            Label("Wird mit OpenAI erstellt (eigener Key): Transkript, Folientexte und Marker gehen an OpenAI. Bei Fehlern wird mit Apple erstellt.",
                  systemImage: "sparkles")
        } else if SummaryGenerator.prefersPrivateCloud {
            switch SummaryGenerator.privateCloudStatus {
            case .available(let approaching):
                Label("Wird mit Apple Private Cloud Compute erstellt: Das Transkript geht verschlüsselt an Apple, wird nur für diese Anfrage verwendet und nicht gespeichert."
                      + (approaching ? " Das heutige Kontingent ist bald aufgebraucht." : ""),
                      systemImage: "lock.icloud")
            case .limitReached:
                VStack(alignment: .leading, spacing: 6) {
                    Label("Das heutige Kontingent für Private Cloud Compute ist aufgebraucht – es wird auf dem Gerät erstellt.",
                          systemImage: "hourglass")
                    Button("Mehr Kontingent") { SummaryGenerator.showLimitIncreaseOptions() }
                        .font(.caption)
                }
            case .unavailable(let reason):
                Label(reason + " Es wird auf dem Gerät erstellt.", systemImage: "info.circle")
            case .notInBuild:
                deviceFooter
            }
        } else {
            deviceFooter
        }
    }

    @ViewBuilder
    private var deviceFooter: some View {
        switch availability {
        case .onDevice:
            Label("Wird mit Apple Intelligence direkt auf dem Gerät erstellt – nichts verlässt dein Gerät.",
                  systemImage: "lock.shield")
        case .structuredOnly(let reason):
            Label("\(reason) Du erhältst eine strukturierte Fassung aus Transkript, ⭐-Markern und Folien zum Ergänzen.",
                  systemImage: "info.circle")
        }
    }

    /// Transkript von der Platte neu lesen (nach Whisper-Nachtranskription oder Wiederherstellen).
    private func reloadTranscript() {
        let folder = content.folderURL
        guard let data = try? Data(contentsOf: folder.appending(path: "transcript.json")),
              let file = try? JSONDecoder().decode(TranscriptFile.self, from: data) else { return }
        content.segments = file.segments
        isWhisper = file.isWhisper
        hasLiveBackup = FileManager.default.fileExists(atPath: folder.appending(path: Retranscriber.liveBackupName).path)
    }

    /// Inhalt inkl. der hier neu erstellten/bearbeiteten Zusammenfassungen.
    private var contentWithSummaries: SessionContent {
        var updated = content
        updated.summaries = store.summaries
        return updated
    }

    private func generate(_ template: SummaryTemplate) {
        guard progress == nil else { return }
        progress = .init(step: 0, total: 1, label: "Wird vorbereitet …")
        // Läuft kurz weiter, falls die App während der Erzeugung in den Hintergrund geht.
        let background = UIApplication.shared.beginBackgroundTask(withName: "Zusammenfassung")
        task = Task {
            defer {
                progress = nil
                UIApplication.shared.endBackgroundTask(background)
            }
            do {
                let result = try await SummaryGenerator.generate(template, from: content) { progress = $0 }
                store.store(result.summary)
                notice = result.notice
                path = [result.summary.id]
            } catch is CancellationError {
                // abgebrochen
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func cancel() {
        task?.cancel()
        progress = nil
    }
}

/// Ansicht/Bearbeitung einer Zusammenfassung.
private struct SummaryEditorView: View {
    let store: SummaryStore
    let summaryID: UUID
    @Binding var notice: String?
    let onRegenerate: (SummaryTemplate) -> Void
    let onExport: (SessionSummary) -> Void

    @State private var isEditing = false
    @State private var draft = ""
    @State private var confirmRegenerate = false

    private var summary: SessionSummary? { store.summaries.first { $0.id == summaryID } }

    var body: some View {
        Group {
            if let summary {
                VStack(spacing: 0) {
                    if let notice {
                        Label(notice, systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.thinMaterial)
                    }
                    if isEditing {
                        TextEditor(text: $draft)
                            .font(.body.monospaced())
                            .padding(.horizontal, 8)
                    } else {
                        ScrollView {
                            MarkdownView(markdown: summary.text).padding()
                        }
                    }
                }
                .navigationTitle(summary.template.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button(isEditing ? "Sichern" : "Bearbeiten") {
                            if isEditing { store.updateText(draft, for: summary.id) } else { draft = summary.text }
                            isEditing.toggle()
                        }
                    }
                    ToolbarItemGroup(placement: .bottomBar) {
                        Button { confirmRegenerate = true } label: {
                            Label("Neu erstellen", systemImage: "arrow.clockwise")
                        }
                        .disabled(isEditing)
                        Spacer()
                        Button { onExport(summary) } label: {
                            Label("Exportieren", systemImage: "square.and.arrow.up")
                        }
                        .disabled(isEditing)
                    }
                }
                .confirmationDialog("Zusammenfassung neu erstellen?", isPresented: $confirmRegenerate, titleVisibility: .visible) {
                    Button("Neu erstellen", role: .destructive) { onRegenerate(summary.template) }
                } message: {
                    Text(summary.isEdited ? "Deine Änderungen gehen dabei verloren." : "Die bisherige Fassung wird ersetzt.")
                }
                .onDisappear {
                    if isEditing { store.updateText(draft, for: summary.id) }
                    notice = nil
                }
            } else {
                ContentUnavailableView("Zusammenfassung gelöscht", systemImage: "doc")
            }
        }
    }
}

private struct GeneratingOverlay: View {
    let progress: SummaryGenerator.Progress
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            VStack(spacing: 14) {
                if progress.total > 1 {
                    ProgressView(value: Double(max(progress.step - 1, 0)), total: Double(progress.total))
                        .frame(maxWidth: 240)
                } else {
                    ProgressView().controlSize(.large)
                }
                Text(progress.label).font(.callout)
                Text(OpenAIClient.isEnabled
                     ? "Läuft über OpenAI mit deinem Key – das kann bei langen Aufnahmen ein bis zwei Minuten dauern."
                     : SummaryGenerator.prefersPrivateCloud
                     ? "Läuft verschlüsselt über Apple Private Cloud Compute – das kann bei langen Aufnahmen eine Minute dauern."
                     : "Läuft auf dem Gerät – das kann bei langen Aufnahmen eine Minute dauern.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Abbrechen", role: .cancel, action: onCancel)
                    .buttonStyle(.bordered)
            }
            .padding(24)
        }
    }
}
