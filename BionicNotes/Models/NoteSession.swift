import Foundation
import SwiftData

/// Eine Session = ein Vortrag. Alle Medien liegen im Session-Ordner (siehe `SessionStorage`).
@Model
final class NoteSession {
    var uuid: UUID
    var title: String
    var createdAt: Date
    /// Länge der Aufnahme in Sekunden.
    var duration: TimeInterval
    var hasAudio: Bool

    init(title: String) {
        self.uuid = UUID()
        self.title = title
        self.createdAt = .now
        self.duration = 0
        self.hasAudio = false
    }

    var folderURL: URL { SessionStorage.folder(for: uuid) }
    var audioURL: URL { folderURL.appending(path: "audio.m4a") }
}
