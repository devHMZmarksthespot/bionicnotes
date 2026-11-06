import AVFoundation
import Observation

/// UI-Zustand der Aufnahme. Die gemeinsame Session-Uhr (`elapsed`) ist später die
/// Zeitachse für Transkript, Pencil-Striche und Fotos.
@MainActor
@Observable
final class AudioRecorder {
    enum State { case idle, recording, paused }

    private(set) var state: State = .idle
    private(set) var level: Float = 0
    private(set) var elapsed: TimeInterval = 0
    var errorMessage: String?

    @ObservationIgnored private let capture = AudioCaptureEngine()
    @ObservationIgnored private var accumulated: TimeInterval = 0
    @ObservationIgnored private var segmentStart: Date?
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var interruptionObserver: NSObjectProtocol?

    init() {
        capture.onLevel = { [weak self] value in
            Task { @MainActor in self?.level = value }
        }
        // iOS 27: ersetzt die alte Interruption-Notification.
        // z. B. Anruf: Session wird inaktiv → Aufnahme pausieren, Nutzer setzt selbst fort.
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.didBecomeInactiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.pause() }
        }
    }

    /// Startet die Aufnahme. `onBuffer` bekommt jeden Mikrofon-Puffer (Audio-Thread), z. B. für die Transkription.
    /// - Returns: `true`, wenn die Aufnahme läuft.
    @discardableResult
    func start(writingTo url: URL,
               onBuffer: (@Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void)? = nil) async -> Bool {
        guard state == .idle else { return false }
        errorMessage = nil
        capture.onBuffer = onBuffer
        do {
            guard await AVAudioApplication.requestRecordPermission() else { throw RecorderError.noPermission }
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            try capture.start(writingTo: url)
            accumulated = 0
            segmentStart = .now
            state = .recording
            startTicking()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func pause() {
        guard state == .recording else { return }
        capture.pause()
        accumulated += Date.now.timeIntervalSince(segmentStart ?? .now)
        segmentStart = nil
        level = 0
        state = .paused
    }

    func resume() {
        guard state == .paused else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            try capture.resume()
            segmentStart = .now
            state = .recording
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Beendet die Aufnahme und liefert die Gesamtdauer.
    @discardableResult
    func stop() -> TimeInterval {
        guard state != .idle else { return elapsed }
        if state == .recording { accumulated += Date.now.timeIntervalSince(segmentStart ?? .now) }
        capture.stop()
        tickTask?.cancel()
        tickTask = nil
        segmentStart = nil
        elapsed = accumulated
        level = 0
        state = .idle
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return accumulated
    }

    private func startTicking() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                self?.tick()
            }
        }
    }

    private func tick() {
        let running = segmentStart.map { Date.now.timeIntervalSince($0) } ?? 0
        elapsed = accumulated + running
    }
}
