import Foundation
import Observation
import WatchConnectivity

/// Watch-Seite der Verbindung zum iPhone.
@MainActor
@Observable
final class WatchLink: NSObject {
    static let shared = WatchLink()

    struct Snippet: Equatable {
        let text: String
        let time: TimeInterval
    }

    enum LinkError: LocalizedError {
        case notReachable
        case phone(String)

        var errorDescription: String? {
            switch self {
            case .notReachable: "iPhone nicht erreichbar. BionicNotes auf dem iPhone öffnen."
            case .phone(let message): message
            }
        }
    }

    private(set) var state: WatchProtocol.RecordingState = .idle
    private(set) var title = ""
    private(set) var isReachable = false
    /// Aufnahmedauer zum Zeitpunkt `sentAt` (vom iPhone gemeldet).
    private var elapsedBase: TimeInterval = 0
    private var sentAt: TimeInterval = Date.now.timeIntervalSince1970

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Aktuelle Aufnahmedauer, lokal hochgezählt seit der letzten Meldung des iPhones.
    func elapsed(at date: Date) -> TimeInterval {
        guard state == .recording else { return elapsedBase }
        return elapsedBase + max(0, date.timeIntervalSince1970 - sentAt)
    }

    func rewind(seconds: TimeInterval) async throws -> Snippet {
        let reply = try await send([WatchProtocol.kind: WatchProtocol.Kind.rewind.rawValue,
                                    WatchProtocol.seconds: seconds])
        return Snippet(text: reply.text, time: reply.time)
    }

    func setMarker(seconds: TimeInterval) async throws -> Snippet {
        let reply = try await send([WatchProtocol.kind: WatchProtocol.Kind.marker.rawValue,
                                    WatchProtocol.seconds: seconds])
        return Snippet(text: reply.text, time: reply.time)
    }

    private func send(_ message: [String: Any]) async throws -> (text: String, time: TimeInterval) {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { throw LinkError.notReachable }
        return try await withCheckedThrowingContinuation { continuation in
            session.sendMessage(message, replyHandler: { reply in
                if let error = reply[WatchProtocol.error] as? String {
                    continuation.resume(throwing: LinkError.phone(error))
                } else {
                    continuation.resume(returning: (reply[WatchProtocol.text] as? String ?? "",
                                                    reply[WatchProtocol.time] as? Double ?? 0))
                }
            }, errorHandler: { error in
                continuation.resume(throwing: error)
            })
        }
    }

    fileprivate func apply(state: String?, title: String?, elapsed: Double?, sentAt: Double?) {
        self.state = state.flatMap(WatchProtocol.RecordingState.init(rawValue:)) ?? .idle
        self.title = title ?? ""
        self.elapsedBase = elapsed ?? 0
        self.sentAt = sentAt ?? Date.now.timeIntervalSince1970
    }

    fileprivate func setReachable(_ value: Bool) {
        isReachable = value
    }
}

extension WatchLink: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let context = session.receivedApplicationContext
        let values = Self.values(from: context)
        let reachable = session.isReachable
        Task { @MainActor in
            self.apply(state: values.0, title: values.1, elapsed: values.2, sentAt: values.3)
            self.setReachable(reachable)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let values = Self.values(from: applicationContext)
        Task { @MainActor in self.apply(state: values.0, title: values.1, elapsed: values.2, sentAt: values.3) }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in self.setReachable(reachable) }
    }

    private nonisolated static func values(from context: [String: Any]) -> (String?, String?, Double?, Double?) {
        (context[WatchProtocol.state] as? String,
         context[WatchProtocol.title] as? String,
         context[WatchProtocol.elapsed] as? Double,
         context[WatchProtocol.sentAt] as? Double)
    }
}
