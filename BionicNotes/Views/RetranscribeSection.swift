import SwiftUI

/// Abschnitt „Transkript“ in der Nachbearbeitung: Live-Transkript genauer mit Whisper neu erstellen.
struct RetranscribeSection: View {
    let input: Retranscriber.Input
    let isWhisper: Bool
    let hasLiveBackup: Bool
    let hasSummaries: Bool

    @State private var isDownloadConfirmShown = false
    /// „auto“, „de“ oder „en“ – gilt für alle Sessions.
    @AppStorage("retranscribeLanguage") private var language = "auto"
    private var runner: Retranscriber { .shared }
    private var model: WhisperModel { .shared }

    var body: some View {
        Section {
            if let job = runner.job(for: input.sessionID) {
                jobView(job)
            } else if runner.isBusy {
                Label("Eine andere Session wird gerade transkribiert.", systemImage: "hourglass")
                    .foregroundStyle(.secondary)
            } else if isWhisper {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Genau transkribiert")
                        Text("Mit Whisper auf diesem Gerät").font(.caption).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                }
                languagePicker
                Button("Erneut transkribieren", systemImage: "arrow.clockwise", action: startTapped)
                if hasLiveBackup {
                    Button("Live-Transkript wiederherstellen", systemImage: "arrow.uturn.backward") {
                        runner.restoreLive(folderURL: input.folderURL)
                    }
                }
            } else {
                Button(action: startTapped) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Genauer transkribieren").foregroundStyle(.primary)
                            Text("Erkennt Fachbegriffe, englische Wörter und Stellen mit Lärm deutlich besser. Dauert einige Minuten.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "waveform.badge.magnifyingglass").foregroundStyle(.tint)
                    }
                }
                .buttonStyle(.plain)
                languagePicker
            }
        } header: {
            Text("Transkript")
        } footer: {
            Text(footer)
        }
        .confirmationDialog("Sprachmodell laden?", isPresented: $isDownloadConfirmShown, titleVisibility: .visible) {
            Button("Laden (\(WhisperModel.approximateSize))") { runner.start(configuredInput) }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Für die genaue Transkription wird einmalig ein Sprachmodell (\(WhisperModel.approximateSize)) geladen – am besten im WLAN. Dabei werden keine Aufnahmen oder Daten von dir gesendet; die Transkription läuft danach komplett offline.")
        }
    }

    private var footer: String {
        var text = "Läuft vollständig auf dem Gerät. Eigene Fachbegriffe kannst du in den Einstellungen hinterlegen."
        if isWhisper && hasSummaries {
            text = "Bereits erstellte Zusammenfassungen beruhen evtl. noch auf dem Live-Transkript – bei Bedarf neu erstellen. " + text
        }
        return text
    }

    @ViewBuilder
    private func jobView(_ job: Retranscriber.Job) -> some View {
        switch job.phase {
        case .downloadingModel(let fraction):
            progressRow("Sprachmodell wird geladen …", value: fraction)
        case .preparingModel:
            progressRow("Sprachmodell wird vorbereitet …", value: nil,
                        detail: "Nach der Installation oder einem App-Update dauert das einmalig 2–3 Minuten. Bitte die App so lange geöffnet lassen.")
        case .transcribing(let fraction):
            progressRow("Transkribiere … \(Int(fraction * 100)) %", value: fraction,
                        detail: "Du kannst die App verlassen – die Transkription läuft weiter.")
        case .finished(let count):
            Label("Fertig – \(count) Abschnitte neu transkribiert.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Button("OK") { runner.dismissResult() }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            Button("Erneut versuchen", systemImage: "arrow.clockwise") { runner.dismissResult(); startTapped() }
        }
    }

    private func progressRow(_ title: String, value: Double?, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let value {
                ProgressView(value: value) { Text(title) }
            } else {
                ProgressView { Text(title) }.progressViewStyle(.linear)
            }
            if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            Button("Abbrechen", role: .destructive) { runner.cancel() }
                .font(.callout)
        }
        .padding(.vertical, 2)
    }

    private var languagePicker: some View {
        Picker("Sprache", selection: $language) {
            Text("Automatisch").tag("auto")
            Text("Deutsch").tag("de")
            Text("Englisch").tag("en")
        }
    }

    private var configuredInput: Retranscriber.Input {
        var input = input
        input.whisperLanguage = language == "auto" ? nil : language
        return input
    }

    private func startTapped() {
        if model.isInstalled { runner.start(configuredInput) } else { isDownloadConfirmShown = true }
    }
}
