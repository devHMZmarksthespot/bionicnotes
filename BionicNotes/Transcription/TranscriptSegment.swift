import Foundation

/// Ein finaler Satz/Abschnitt des Transkripts auf der Session-Zeitachse.
/// `start`/`end` sind Sekunden ab Aufnahmebeginn (ohne Pausen) – identisch mit der Position in audio.m4a.
struct TranscriptSegment: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var start: TimeInterval
    var end: TimeInterval
    var text: String
}

/// Inhalt von transcript.json im Session-Ordner.
struct TranscriptFile: Codable {
    enum Engine: String {
        case live    // Apple SpeechTranscriber während der Aufnahme
        case whisper // genaue Nachtranskription
    }

    var locale: String
    var segments: [TranscriptSegment]
    /// `nil` bei älteren Dateien = Live-Transkript.
    var engine: String? = nil

    var isWhisper: Bool { engine == Engine.whisper.rawValue }
}
