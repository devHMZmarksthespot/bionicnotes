import Accelerate
import AVFoundation

enum RecorderError: LocalizedError {
    case noPermission
    case noInput

    var errorDescription: String? {
        switch self {
        case .noPermission: "Kein Zugriff aufs Mikrofon. Bitte in Einstellungen › BionicNotes erlauben."
        case .noInput: "Kein Mikrofon gefunden."
        }
    }
}

/// Läuft bewusst NICHT auf dem MainActor: der Tap-Callback kommt vom Audio-Thread.
/// Schreibt das Mikrofon in eine AAC-Datei und reicht jeden Puffer weiter
/// (Pegelanzeige und Live-Transkription).
final class AudioCaptureEngine: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var file: AVAudioFile?

    /// Pegel 0…1, wird vom Audio-Thread aufgerufen.
    var onLevel: (@Sendable (Float) -> Void)?
    /// `true`, sobald das Mikrofon ~3 s lang exakt Stille liefert (z. B. Audio zum Mac umgeleitet),
    /// `false`, sobald wieder Signal kommt. Wird vom Audio-Thread aufgerufen.
    var onSilence: (@Sendable (Bool) -> Void)?
    private var silentFrames: AVAudioFrameCount = 0
    private var reportedSilent = false

    /// Rohe Audiopuffer, z. B. für die Live-Transkription.
    var onBuffer: (@Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void)?

    /// Format des Mikrofons (nach `start` gültig).
    private(set) var inputFormat: AVAudioFormat?

    func start(writingTo url: URL) throws {
        silentFrames = 0
        reportedSilent = false
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw RecorderError.noInput }
        inputFormat = format

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: min(format.channelCount, 2),
            AVEncoderBitRateKey: 96_000,
        ]
        file = try AVAudioFile(forWriting: url,
                               settings: settings,
                               commonFormat: .pcmFormatFloat32,
                               interleaved: format.isInterleaved)

        // installTap ist in iOS 27 deprecated; der Nachfolger mit Fehlerrückgabe hat im
        // 27.3-Beta-SDK noch keinen Swift-Wrapper. Umstellen, sobald Apple ihn nachliefert.
        transcriptionLog.info("mic format: \(format.description, privacy: .public)")
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, time in
            guard let self else { return }
            try? self.file?.write(from: buffer)
            self.onLevel?(Self.level(of: buffer))
            self.trackSilence(buffer)
            self.onBuffer?(buffer, time)
        }
        engine.prepare()
        try engine.start()
    }

    func pause() {
        engine.pause()
    }

    func resume() throws {
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        file = nil // schließt die Datei
    }

    /// Exakt 0 in jedem Sample ist keine leise Umgebung, sondern ein fehlendes Signal.
    private func trackSilence(_ buffer: AVAudioPCMBuffer) {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
        var peak: Float = 0
        vDSP_maxmgv(samples, 1, &peak, vDSP_Length(buffer.frameLength))
        silentFrames = peak == 0 ? silentFrames + buffer.frameLength : 0
        let silent = Double(silentFrames) >= buffer.format.sampleRate * 3
        if silent != reportedSilent {
            reportedSilent = silent
            onSilence?(silent)
        }
    }

    /// RMS → dB → 0…1 (‑60 dB = 0, 0 dB = 1)
    private static func level(of buffer: AVAudioPCMBuffer) -> Float {
        guard let samples = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<count { sum += samples[i] * samples[i] }
        let rms = (sum / Float(count)).squareRoot()
        let db = 20 * log10(max(rms, 0.000_001))
        return max(0, min(1, (db + 60) / 60))
    }
}
