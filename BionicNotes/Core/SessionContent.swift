import Foundation

/// Alles, was zu einer Session auf der Platte liegt – als einfache Werte gelesen.
/// Grundlage für Zusammenfassung, Export und Suche (unabhängig von den UI-Stores).
struct SessionContent: Sendable {
    var title: String
    var createdAt: Date
    var duration: TimeInterval
    var language: String
    var hasAudio: Bool
    var segments: [TranscriptSegment]
    var markers: [SessionMarker]
    var photos: [SessionPhoto]
    var summaries: [SessionSummary]
    var folderURL: URL

    var audioURL: URL { folderURL.appending(path: "audio.m4a") }
    var drawingURL: URL { folderURL.appending(path: "drawing.data") }
    var photosFolder: URL { folderURL.appending(path: "photos", directoryHint: .isDirectory) }

    var isEnglish: Bool { language.hasPrefix("en") }
    var slides: [SessionPhoto] { photos.filter { $0.kind == .slide } }
    var hasNotes: Bool { FileManager.default.fileExists(atPath: drawingURL.path) }

    /// Ganzes Transkript als Fließtext.
    var transcriptText: String { segments.map(\.text).joined(separator: " ") }

    /// Transkript mit Zeitstempeln, eine Zeile pro Segment: „[12:05] …“.
    var timedTranscript: String {
        segments.map { "[\($0.start.clockString)] \($0.text)" }.joined(separator: "\n")
    }

    func photoURL(_ photo: SessionPhoto) -> URL { photosFolder.appending(path: photo.fileName) }

    @MainActor
    static func load(_ session: NoteSession) -> SessionContent {
        let folder = session.folderURL
        let transcript: TranscriptFile? = decode(session.transcriptURL)
        return SessionContent(
            title: session.title,
            createdAt: session.createdAt,
            duration: session.duration,
            language: session.language,
            hasAudio: session.hasAudio,
            segments: transcript?.segments ?? [],
            markers: decode(session.markersURL) ?? [],
            photos: decode(folder.appending(path: "photos.json")) ?? [],
            summaries: decode(folder.appending(path: SummaryStore.fileName)) ?? [],
            folderURL: folder)
    }

    private static func decode<T: Decodable>(_ url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
