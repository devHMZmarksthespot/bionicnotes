import SwiftUI

/// Einstellungen & Datenschutz.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var includeInBackup = SessionStorage.isIncludedInBackup
    @State private var language = TranscriptionLanguage.defaultIdentifier
    @State private var glossary = Glossary.text
    @State private var modelSizeMB = 0
    @State private var isRemoveConfirmShown = false
    @AppStorage(SummaryGenerator.privateCloudKey) private var usesPrivateCloud = false
    @AppStorage(OpenAIClient.enabledKey) private var usesOpenAI = false
    @State private var openAIKeyInput = ""
    @State private var openAIMasked = OpenAIClient.maskedKey
    @State private var openAIStatus: String?
    @State private var isVerifyingKey = false
    @State private var isOpenAIConsentShown = false
    private var model: WhisperModel { .shared }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return "\(short) (\(build))"
    }

    private static let licenses = """
        WhisperKit – Copyright (c) 2024 Argmax, Inc.
        Whisper-Modelle – Copyright (c) 2022 OpenAI

        MIT License: Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions: The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software. THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
        """

    @ViewBuilder
    private var openAISection: some View {
        Section {
            if let masked = openAIMasked {
                LabeledContent("API-Key", value: masked)
                Toggle(isOn: Binding(get: { usesOpenAI }, set: { on in
                    if on { isOpenAIConsentShown = true } else { usesOpenAI = false }
                })) {
                    Label("Berichte mit OpenAI erstellen", systemImage: "sparkles")
                }
                Button("Key entfernen", role: .destructive) {
                    OpenAIClient.Keychain.delete()
                    usesOpenAI = false
                    openAIMasked = nil
                    openAIStatus = nil
                }
            } else {
                SecureField("sk-…", text: $openAIKeyInput)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Button {
                    Task { await saveOpenAIKey() }
                } label: {
                    if isVerifyingKey { ProgressView() } else { Text("Key prüfen und sichern") }
                }
                .disabled(openAIKeyInput.trimmingCharacters(in: .whitespaces).isEmpty || isVerifyingKey)
            }
            if let openAIStatus {
                Text(openAIStatus).font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text("Eigener OpenAI-Key (optional)")
        } footer: {
            Text("Für die höchste Genauigkeit bei langen Berichten. Eingeschaltet gehen Transkript, Folientexte und Marker an OpenAI (Drittanbieter) und werden nach deren Bedingungen verarbeitet; die Kosten werden deinem OpenAI-Konto belastet (ca. CHF 4 pro Stunde Aufnahme). Der Key bleibt nur in der Keychain dieses Geräts. Ohne Verbindung oder bei Fehlern wird der Bericht mit Apple erstellt.")
        }
        .confirmationDialog("Berichte mit OpenAI erstellen?", isPresented: $isOpenAIConsentShown, titleVisibility: .visible) {
            Button("Einschalten") { usesOpenAI = true }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Transkript, Folientexte und Marker einer Session werden für jeden Bericht an OpenAI gesendet. Nur einschalten, wenn das für deine Aufnahmen erlaubt ist (z. B. keine vertraulichen Firmeninhalte ohne Freigabe).")
        }
    }

    private func saveOpenAIKey() async {
        let key = openAIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        isVerifyingKey = true
        defer { isVerifyingKey = false }
        do {
            try await OpenAIClient.verify(key: key)
            guard OpenAIClient.Keychain.save(key) else {
                openAIStatus = "Der Key konnte nicht in der Keychain gesichert werden."
                return
            }
            openAIKeyInput = ""
            openAIMasked = OpenAIClient.maskedKey
            openAIStatus = "Key geprüft und gesichert."
        } catch {
            openAIStatus = error.localizedDescription
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Aufnahme, Transkription und Export laufen auf diesem Gerät. Berichte entstehen auf dem Gerät oder – wenn du es einschaltest – mit Apple Private Cloud Compute bzw. deinem eigenen OpenAI-Key.",
                          systemImage: "lock.shield.fill")
                    Label("Kein Konto, keine Analyse-Tools. Daten verlassen das Gerät nur, wenn du sie selbst teilst oder eine der Optionen unten einschaltest. Sonst einzige Verbindung: das optionale Laden von Sprachmodellen.",
                          systemImage: "hand.raised.fill")
                } header: {
                    Text("Datenschutz")
                }

                Section {
                    Toggle("Sessions ins Backup aufnehmen", isOn: $includeInBackup)
                        .onChange(of: includeInBackup) { SessionStorage.isIncludedInBackup = includeInBackup }
                } footer: {
                    Text(includeInBackup
                         ? "Aufnahmen und Notizen werden mit deinem iCloud- bzw. Computer-Backup gesichert (verschlüsselt durch Apple bzw. dein Backup)."
                         : "Aufnahmen und Notizen sind vom iCloud- und Computer-Backup ausgeschlossen. Geht das Gerät verloren, sind sie weg – wichtige Sessions am besten exportieren.")
                }

                Section("Transkription") {
                    Picker("Standardsprache", selection: $language) {
                        ForEach(TranscriptionLanguage.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    .onChange(of: language) { TranscriptionLanguage.remember(language) }
                }

                Section {
                    TextField("z. B. TWINT, Multirail, Betrugsbekämpfung", text: $glossary, axis: .vertical)
                        .lineLimit(3...8)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onChange(of: glossary) { Glossary.text = glossary }
                } header: {
                    Text("Fachbegriffe")
                } footer: {
                    Text("Firmen, Produkte, Namen und Abkürzungen, durch Komma oder Zeilenumbruch getrennt. Die Live-Transkription erkennt sie zuverlässiger, und in Transkripten und Berichten wird ihre Schreibweise vereinheitlicht (z. B. „Multi-Rail“ → „Multirail“). Wird ein Begriff immer gleich falsch erkannt, die Variante mit Pfeil davorschreiben: „Cloud Code -> Claude Code“.")
                }

                Section {
                    switch model.state {
                    case .installed:
                        LabeledContent("Whisper large-v3 turbo", value: "\(modelSizeMB) MB")
                        Button("Sprachmodell entfernen", role: .destructive) { isRemoveConfirmShown = true }
                            .disabled(Retranscriber.shared.isBusy)
                    case .downloading(let fraction):
                        ProgressView(value: fraction) { Text("Sprachmodell wird geladen …") }
                    case .preparing:
                        ProgressView { Text("Sprachmodell wird vorbereitet …") }
                    case .notInstalled, .failed:
                        LabeledContent("Sprachmodell", value: "nicht geladen")
                        Button("Jetzt laden (\(WhisperModel.approximateSize))") {
                            Task { try? await model.install(); modelSizeMB = WhisperModel.diskUsageMB() }
                        }
                        if case .failed(let message) = model.state {
                            Text(message).font(.caption).foregroundStyle(.orange)
                        }
                    }
                } header: {
                    Text("Genaue Transkription")
                } footer: {
                    Text("Unter „Nachbearbeiten“ kann eine Aufnahme mit Whisper genauer neu transkribiert werden – vollständig auf dem Gerät. Das Modell wird einmalig von Hugging Face geladen; dabei werden keine Daten von dir gesendet. Ohne Modell wird es beim ersten Gebrauch angeboten.")
                }
                .onAppear { modelSizeMB = model.isInstalled ? WhisperModel.diskUsageMB() : 0 }
                .confirmationDialog("Sprachmodell entfernen?", isPresented: $isRemoveConfirmShown, titleVisibility: .visible) {
                    Button("Entfernen", role: .destructive) { Task { await model.remove() } }
                } message: {
                    Text("Bereits erstellte Transkripte bleiben erhalten. Für weitere Nachtranskriptionen muss das Modell neu geladen werden.")
                }

                Section {
                    switch SummaryGenerator.availability(language: language) {
                    case .onDevice:
                        Label("Apple Intelligence verfügbar – Zusammenfassungen werden on-device geschrieben.",
                              systemImage: "checkmark.seal")
                    case .structuredOnly(let reason):
                        Label(reason + " Zusammenfassungen werden als strukturierter Entwurf erstellt.",
                              systemImage: "info.circle")
                    }
                    if SummaryGenerator.isPrivateCloudInBuild {
                        Toggle(isOn: $usesPrivateCloud) {
                            Label("Apple Private Cloud Compute", systemImage: "lock.icloud")
                        }
                    }
                } header: {
                    Text("Zusammenfassungen")
                } footer: {
                    if SummaryGenerator.isPrivateCloudInBuild {
                        Text("Eingeschaltet: Berichte werden mit Apples grösserem Modell erstellt – deutlich besser bei langen Aufnahmen. Transkript, Folientexte und Marker gehen dafür verschlüsselt an Apple, werden nur für diese Anfrage verwendet und nicht gespeichert; weder Apple noch wir können sie einsehen. Ausgeschaltet oder ohne Verbindung bleibt alles auf dem Gerät.")
                    }
                }

                openAISection

                Section {
                    LabeledContent("Version", value: version)
                    DisclosureGroup("Open-Source-Lizenzen") {
                        Text(Self.licenses).font(.caption2).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Über")
                }
            }
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
            }
        }
    }
}
