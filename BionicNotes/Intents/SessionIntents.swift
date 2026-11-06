import AppIntents
import Foundation

// App Intents für Siri, Kurzbefehle, Spotlight und die Action-Taste.
// Marker, Rewind, Pause/Weiter und Stopp laufen im Hintergrund – die App muss dafür
// nicht in den Vordergrund. Aufnahme starten und Foto brauchen die Oberfläche.

private func noRecordingDialog() -> IntentDialog {
    "Gerade läuft keine Aufnahme in BionicNotes."
}

struct StartRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "Aufnahme starten"
    static let description = IntentDescription("Startet eine neue Session und nimmt den Vortrag mit Live-Transkript auf.")
    static let supportedModes: IntentModes = .foreground(.immediate)

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        if let active = PhoneWatchLink.shared.current {
            if active.state() == .paused {
                active.resume()
                return .result(dialog: "Aufnahme läuft weiter.")
            }
            return .result(dialog: "Die Aufnahme läuft bereits.")
        }
        SessionCommands.shared.pending = .newRecording
        return .result(dialog: "Aufnahme startet.")
    }
}

struct StopRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "Aufnahme beenden"
    static let description = IntentDescription("Beendet die laufende Aufnahme und speichert Audio, Transkript und Notizen.")
    static let supportedModes: IntentModes = .background

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let active = PhoneWatchLink.shared.current else { return .result(dialog: noRecordingDialog()) }
        let duration = active.elapsed()
        active.stop()
        return .result(dialog: "Aufnahme beendet nach \(duration.clockString).")
    }
}

struct PauseRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "Aufnahme pausieren"
    static let description = IntentDescription("Pausiert die laufende Aufnahme.")
    static let supportedModes: IntentModes = .background

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let active = PhoneWatchLink.shared.current else { return .result(dialog: noRecordingDialog()) }
        guard active.state() == .recording else { return .result(dialog: "Die Aufnahme ist bereits pausiert.") }
        active.pause()
        return .result(dialog: "Aufnahme pausiert bei \(active.elapsed().clockString).")
    }
}

struct ResumeRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "Aufnahme fortsetzen"
    static let description = IntentDescription("Setzt eine pausierte Aufnahme fort.")
    static let supportedModes: IntentModes = .background

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let active = PhoneWatchLink.shared.current else { return .result(dialog: noRecordingDialog()) }
        guard active.state() == .paused else { return .result(dialog: "Die Aufnahme läuft bereits.") }
        active.resume()
        return .result(dialog: "Aufnahme läuft weiter.")
    }
}

struct AddMarkerIntent: AppIntent {
    static let title: LocalizedStringResource = "Als wichtig markieren"
    static let description = IntentDescription("Setzt einen ⭐-Marker an der aktuellen Stelle der Aufnahme – mit dem Transkript der letzten Sekunden.")
    static let supportedModes: IntentModes = .background

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let active = PhoneWatchLink.shared.current,
              let marker = PhoneWatchLink.shared.makeMarker(seconds: WatchProtocol.defaultSeconds, source: .phone)
        else { return .result(dialog: noRecordingDialog()) }
        active.addMarker(marker)
        return .result(dialog: "⭐ Marker bei \(marker.time.clockString) gesetzt.")
    }
}

struct RewindIntent: AppIntent {
    static let title: LocalizedStringResource = "Was wurde gerade gesagt?"
    static let description = IntentDescription("Liefert das Transkript der letzten Sekunden der laufenden Aufnahme.")
    static let supportedModes: IntentModes = .background

    @Parameter(title: "Sekunden", default: 30, inclusiveRange: (10, 300))
    var seconds: Int

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        guard let active = PhoneWatchLink.shared.current else {
            return .result(value: "", dialog: noRecordingDialog())
        }
        let text = active.recentText(TimeInterval(seconds))
        guard !text.isEmpty else {
            return .result(value: "", dialog: "In den letzten \(seconds) Sekunden wurde nichts erkannt.")
        }
        return .result(value: text, dialog: "\(text)")
    }
}

struct TakePhotoIntent: AppIntent {
    static let title: LocalizedStringResource = "Foto aufnehmen"
    static let description = IntentDescription("Öffnet die Kamera und legt das Foto an die aktuelle Stelle der Aufnahme.")
    static let supportedModes: IntentModes = .foreground(.immediate)

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard PhoneWatchLink.shared.current != nil else { return .result(dialog: noRecordingDialog()) }
        SessionCommands.shared.pending = .photo
        return .result(dialog: "Kamera ist bereit.")
    }
}

struct ScanSlideIntent: AppIntent {
    static let title: LocalizedStringResource = "Folie scannen"
    static let description = IntentDescription("Öffnet den Folien-Scanner; der Text der Folie wird erkannt.")
    static let supportedModes: IntentModes = .foreground(.immediate)

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard PhoneWatchLink.shared.current != nil else { return .result(dialog: noRecordingDialog()) }
        SessionCommands.shared.pending = .slide
        return .result(dialog: "Scanner ist bereit.")
    }
}

/// Sätze für Siri und Einträge in der Kurzbefehle-App (auch für die Action-Taste).
struct BionicNotesShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartRecordingIntent(), phrases: [
            "Starte Aufnahme in \(.applicationName)",
            "Neue Aufnahme mit \(.applicationName)",
            "Vortrag aufnehmen mit \(.applicationName)",
        ], shortTitle: "Aufnahme starten", systemImageName: "record.circle")
        AppShortcut(intent: AddMarkerIntent(), phrases: [
            "Markiere das in \(.applicationName)",
            "Das ist wichtig in \(.applicationName)",
            "Setze Marker in \(.applicationName)",
        ], shortTitle: "Wichtig", systemImageName: "star.fill")
        AppShortcut(intent: RewindIntent(), phrases: [
            "Was wurde gerade gesagt in \(.applicationName)",
            "Spul zurück in \(.applicationName)",
            "\(.applicationName) Rewind",
        ], shortTitle: "Rewind", systemImageName: "gobackward.30")
        AppShortcut(intent: TakePhotoIntent(), phrases: [
            "Foto in \(.applicationName)",
            "Mach ein Foto mit \(.applicationName)",
        ], shortTitle: "Foto", systemImageName: "camera")
        AppShortcut(intent: ScanSlideIntent(), phrases: [
            "Folie scannen mit \(.applicationName)",
        ], shortTitle: "Folie scannen", systemImageName: "doc.viewfinder")
        AppShortcut(intent: PauseRecordingIntent(), phrases: [
            "Pausiere \(.applicationName)",
            "Aufnahme pausieren in \(.applicationName)",
        ], shortTitle: "Pause", systemImageName: "pause.fill")
        AppShortcut(intent: ResumeRecordingIntent(), phrases: [
            "Setze \(.applicationName) fort",
            "Aufnahme fortsetzen in \(.applicationName)",
        ], shortTitle: "Weiter", systemImageName: "play.fill")
        AppShortcut(intent: StopRecordingIntent(), phrases: [
            "Beende Aufnahme in \(.applicationName)",
            "Stoppe \(.applicationName)",
        ], shortTitle: "Aufnahme beenden", systemImageName: "stop.fill")
    }
}
