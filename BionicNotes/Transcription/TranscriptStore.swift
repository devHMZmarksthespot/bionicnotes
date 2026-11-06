import Foundation
import Observation

/// UI-Zustand des Transkripts einer Session: finale Segmente + aktueller vorläufiger Text.
@MainActor
@Observable
final class TranscriptStore {
    enum Status: Equatable {
        case idle
        case preparing
        case downloading(Double)
        case listening
        case unavailable(String)
    }

    private(set) var segments: [TranscriptSegment] = []
    private(set) var volatileText = ""
    var status: Status = .idle

    var isEmpty: Bool { segments.isEmpty && volatileText.isEmpty }

    func reset() {
        segments = []
        volatileText = ""
    }

    func apply(_ update: LiveTranscriber.Update) {
        let text = update.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if update.isFinal {
            if !text.isEmpty {
                segments.append(TranscriptSegment(start: update.start, end: update.end, text: text))
            }
            volatileText = ""
        } else {
            volatileText = text
        }
    }

    /// Segment, das gerade zur Abspielposition gehört.
    func segment(at time: TimeInterval) -> TranscriptSegment? {
        segments.last { $0.start <= time + 0.05 }
    }

    /// Text der letzten `seconds` Sekunden bis `time` – Grundlage für das Watch-Rewind.
    func recentText(seconds: TimeInterval, until time: TimeInterval) -> String {
        let finals = segments.filter { $0.end >= time - seconds }.map(\.text)
        return (finals + (volatileText.isEmpty ? [] : [volatileText])).joined(separator: " ")
    }

    // MARK: - Speichern / Laden (transcript.json)

    func save(to url: URL, locale: String) {
        let file = TranscriptFile(locale: locale, segments: segments)
        do {
            let data = try JSONEncoder().encode(file)
            try data.write(to: url, options: .atomic)
        } catch {
            status = .unavailable("Transkript konnte nicht gespeichert werden: \(error.localizedDescription)")
        }
    }

    func load(from url: URL) {
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(TranscriptFile.self, from: data) else { return }
        segments = file.segments
        volatileText = ""
    }
}
