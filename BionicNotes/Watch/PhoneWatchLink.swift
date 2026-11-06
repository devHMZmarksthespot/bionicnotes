import Foundation
import WatchConnectivity

/// iPhone-Seite der Watch-Verbindung.
/// - Schickt den Status der laufenden Aufnahme als Application Context an die Watch.
/// - Beantwortet Rewind-Anfragen mit dem Transkript der letzten Sekunden.
/// - Nimmt Marker von der Watch entgegen.
@MainActor
final class PhoneWatchLink: NSObject {
    static let shared = PhoneWatchLink()

    /// Laufende Aufnahme, an die die Watch angebunden ist.
    struct ActiveSession {
        let title: () -> String
        let state: () -> WatchProtocol.RecordingState
        let elapsed: () -> TimeInterval
        let recentText: (_ seconds: TimeInterval) -> String
        let addMarker: (SessionMarker) -> Void
        let pause: () -> Void
        let resume: () -> Void
        let stop: () -> Void
    }

    private var active: ActiveSession?

    /// Laufende Aufnahme – auch für App Intents (Siri, Kurzbefehle).
    var current: ActiveSession? { active }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func attach(_ session: ActiveSession) {
        active = session
        publishState()
    }

    func detach() {
        active = nil
        publishState()
    }

    /// Status an die Watch senden (bei Start/Pause/Fortsetzen/Stopp aufrufen).
    func publishState() {
        let session = WCSession.default
        guard WCSession.isSupported(), session.activationState == .activated,
              session.isPaired, session.isWatchAppInstalled else { return }
        let context: [String: Any] = [
            WatchProtocol.state: (active?.state() ?? .idle).rawValue,
            WatchProtocol.title: active?.title() ?? "",
            WatchProtocol.elapsed: active?.elapsed() ?? 0,
            WatchProtocol.sentAt: Date.now.timeIntervalSince1970,
        ]
        try? session.updateApplicationContext(context)
    }

    /// Erzeugt einen Marker an der aktuellen Stelle (für iPhone-Button und Watch).
    func makeMarker(seconds: TimeInterval, source: SessionMarker.Source) -> SessionMarker? {
        guard let active else { return nil }
        return SessionMarker(time: active.elapsed(),
                             snippet: active.recentText(seconds),
                             source: source)
    }

    fileprivate func handle(kind: WatchProtocol.Kind?, seconds: TimeInterval) -> [String: Any] {
        guard let active, active.state() != .idle else {
            return [WatchProtocol.error: "Keine laufende Aufnahme auf dem iPhone."]
        }
        switch kind {
        case .rewind:
            return [WatchProtocol.text: active.recentText(seconds),
                    WatchProtocol.time: active.elapsed()]
        case .marker:
            guard let marker = makeMarker(seconds: seconds, source: .watch) else {
                return [WatchProtocol.error: "Marker konnte nicht gesetzt werden."]
            }
            active.addMarker(marker)
            return [WatchProtocol.time: marker.time, WatchProtocol.text: marker.snippet]
        case nil:
            return [WatchProtocol.error: "Unbekannte Anfrage."]
        }
    }
}

extension PhoneWatchLink: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.publishState() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Wechsel auf eine andere Watch: neu aktivieren.
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.publishState() }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        let kind = (message[WatchProtocol.kind] as? String).flatMap(WatchProtocol.Kind.init(rawValue:))
        let seconds = message[WatchProtocol.seconds] as? Double ?? WatchProtocol.defaultSeconds
        nonisolated(unsafe) let reply = replyHandler
        Task { @MainActor in
            reply(self.handle(kind: kind, seconds: seconds))
        }
    }
}
