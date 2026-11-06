import Foundation
import Observation

/// Brücke zwischen App Intents (Siri, Kurzbefehle, Action-Taste) und der Oberfläche.
/// Intents, die eine Ansicht brauchen (neue Aufnahme, Kamera), legen hier eine Anfrage ab;
/// die Views reagieren darauf. Alles andere läuft direkt über die laufende Aufnahme
/// (`PhoneWatchLink.shared.current`).
@MainActor
@Observable
final class SessionCommands {
    static let shared = SessionCommands()

    enum Request: Equatable {
        case newRecording
        case photo
        case slide
    }

    /// Offene Anfrage an die Oberfläche; wird von der View abgeholt und zurückgesetzt.
    var pending: Request?

    /// Session, die beim Erscheinen sofort die Aufnahme starten soll.
    var autoStartSessionID: UUID?

    func take(_ request: Request) -> Bool {
        guard pending == request else { return false }
        pending = nil
        return true
    }
}
