import Foundation

/// Gemeinsames Nachrichtenformat zwischen iPhone- und Watch-App (WatchConnectivity).
/// Diese Datei ist in beiden Targets enthalten.
enum WatchProtocol {
    // MARK: Nachrichten Watch → iPhone (sendMessage mit Antwort)
    static let kind = "kind"
    static let seconds = "seconds"

    enum Kind: String {
        /// Transkript der letzten `seconds` Sekunden anfordern.
        case rewind
        /// Marker an der aktuellen Stelle setzen; Snippet = letzte `seconds` Sekunden.
        case marker
    }

    // MARK: Antworten iPhone → Watch
    static let text = "text"
    static let time = "time"
    static let error = "error"

    // MARK: Application Context iPhone → Watch (Status der laufenden Session)
    static let state = "state"
    static let title = "title"
    static let elapsed = "elapsed"
    static let sentAt = "sentAt"

    enum RecordingState: String {
        case idle, recording, paused
    }

    /// Standard-Länge für Rewind und Marker-Snippets.
    static let defaultSeconds: Double = 30
}
