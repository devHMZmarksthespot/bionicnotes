import Foundation
import Observation

/// Eine erzeugte (und ggf. bearbeitete) Zusammenfassung nach einer Vorlage. Text ist Markdown.
struct SessionSummary: Codable, Identifiable, Hashable, Sendable {
    enum Engine: String, Codable, Sendable {
        /// Apple Foundation Models, on-device.
        case onDevice
        /// Apple Foundation Model auf Private Cloud Compute (Opt-in).
        case privateCloud
        /// OpenAI mit dem eigenen API-Key des Nutzers (Opt-in, Drittanbieter).
        case openAI
        /// Strukturierte Fassung ohne Sprachmodell (Marker, Folien, Schlüsselsätze).
        case structured
    }

    var id = UUID()
    var template: SummaryTemplate
    var createdAt: Date
    var engine: Engine
    var text: String
    var isEdited = false
}

/// Zusammenfassungen einer Session: summaries.json im Session-Ordner, eine pro Vorlage.
@MainActor
@Observable
final class SummaryStore {
    static let fileName = "summaries.json"

    private(set) var summaries: [SessionSummary] = []
    @ObservationIgnored private var url: URL?

    func load(sessionFolder: URL) {
        url = sessionFolder.appending(path: Self.fileName)
        guard let url, let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([SessionSummary].self, from: data) else {
            summaries = []
            return
        }
        summaries = list
    }

    func summary(for template: SummaryTemplate) -> SessionSummary? {
        summaries.first { $0.template == template }
    }

    /// Neu erzeugt: ersetzt eine bestehende Zusammenfassung derselben Vorlage.
    func store(_ summary: SessionSummary) {
        summaries.removeAll { $0.template == summary.template }
        summaries.insert(summary, at: 0)
        save()
    }

    func updateText(_ text: String, for id: UUID) {
        guard let index = summaries.firstIndex(where: { $0.id == id }), summaries[index].text != text else { return }
        summaries[index].text = text
        summaries[index].isEdited = true
        save()
    }

    func remove(_ summary: SessionSummary) {
        summaries.removeAll { $0.id == summary.id }
        save()
    }

    private func save() {
        guard let url else { return }
        try? JSONEncoder().encode(summaries).write(to: url, options: .atomic)
    }
}
