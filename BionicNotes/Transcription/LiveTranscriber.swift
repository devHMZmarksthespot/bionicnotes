import AVFoundation
import OSLog
import Speech

let transcriptionLog = Logger(subsystem: "hmzinnovation.bionicnotes", category: "transcription")

enum TranscriptionError: LocalizedError {
    case unsupportedLocale(String)
    case noAudioFormat

    var errorDescription: String? {
        switch self {
        case .unsupportedLocale(let id): "Die Sprache \(id) wird für die Transkription auf diesem Gerät nicht unterstützt."
        case .noAudioFormat: "Kein passendes Audioformat für die Transkription gefunden."
        }
    }
}

/// Live-Transkription mit SpeechAnalyzer + SpeechTranscriber, komplett on-device.
///
/// Läuft bewusst NICHT auf dem MainActor: `feed` wird vom Audio-Thread aufgerufen.
/// Die Puffer werden ohne eigene Zeitstempel eingespeist, damit die Zeitachse des Analyzers
/// genau der Aufnahme ohne Pausen entspricht (= Position in audio.m4a).
final class LiveTranscriber: @unchecked Sendable {
    /// Ein Ergebnis des Transcribers – vorläufig (`isFinal == false`) oder final.
    struct Update: Sendable {
        let text: String
        let start: TimeInterval
        let end: TimeInterval
        let isFinal: Bool
    }

    let locale: Locale
    private let transcriber: SpeechTranscriber
    private let analyzer: SpeechAnalyzer
    private var converter: AnalyzerInputConverter?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var fedBuffers = 0

    private init(locale: Locale, transcriber: SpeechTranscriber) {
        self.locale = locale
        self.transcriber = transcriber
        self.analyzer = SpeechAnalyzer(modules: [transcriber])
    }

    /// Prüft die Sprache und lädt bei Bedarf das Sprachmodell (einmalig, danach offline verfügbar).
    static func prepare(locale requested: Locale,
                        onDownloadProgress: @escaping @Sendable (Double) -> Void) async throws -> LiveTranscriber {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requested) else {
            throw TranscriptionError.unsupportedLocale(requested.identifier)
        }
        let transcriber = SpeechTranscriber(locale: locale,
                                            transcriptionOptions: [],
                                            reportingOptions: [.volatileResults, .fastResults],
                                            attributeOptions: [.audioTimeRange])

        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            let progress = request.progress
            let watcher = Task {
                while !Task.isCancelled {
                    onDownloadProgress(progress.fractionCompleted)
                    try? await Task.sleep(for: .milliseconds(250))
                }
            }
            defer { watcher.cancel() }
            try await request.downloadAndInstall()
        }
        _ = try? await AssetInventory.reserve(locale: locale)
        transcriptionLog.info("prepare ok: requested=\(requested.identifier, privacy: .public) locale=\(locale.identifier, privacy: .public)")
        return LiveTranscriber(locale: locale, transcriber: transcriber)
    }

    /// Startet die Analyse. Danach Audio per `feed` einspeisen.
    /// `onUpdate` läuft auf dem MainActor, in der Reihenfolge der Ergebnisse.
    func start(onUpdate: @escaping @MainActor @Sendable (Update) -> Void) async throws {
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw TranscriptionError.noAudioFormat
        }
        transcriptionLog.info("analyzer format: \(format.description, privacy: .public)")
        converter = AnalyzerInputConverter(analyzerFormat: format)
        try await analyzer.prepareToAnalyze(in: format)

        let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        self.continuation = continuation

        let transcriber = self.transcriber
        resultsTask = Task {
            do {
                for try await result in transcriber.results {
                    transcriptionLog.debug("result final=\(result.isFinal) [\(result.range.start.seconds)-\(result.range.end.seconds)] len=\(result.text.characters.count)")  // kein Transkript-Inhalt im Log
                    await onUpdate(Update(text: String(result.text.characters),
                                    start: result.range.start.seconds,
                                    end: result.range.end.seconds,
                                    isFinal: result.isFinal))
                }
            } catch {
                // Ende der Analyse oder Abbruch – bereits gelieferte finale Ergebnisse bleiben erhalten.
                transcriptionLog.error("results ended with error: \(error.localizedDescription, privacy: .public)")
            }
        }
        try await analyzer.start(inputSequence: stream)
        transcriptionLog.info("analyzer started")
    }

    /// Vom Audio-Thread: Mikrofon-Puffer ins Analyzer-Format wandeln und einspeisen.
    func feed(_ buffer: AVAudioPCMBuffer) {
        guard let converter, let continuation else { return }
        fedBuffers += 1
        do {
            let inputs = try converter.convert(buffer, at: nil)
            if fedBuffers <= 3 || fedBuffers % 100 == 0 {
                transcriptionLog.debug("feed #\(self.fedBuffers): \(buffer.frameLength) frames → \(inputs.count) inputs")
            }
            for input in inputs {
                continuation.yield(input)
            }
        } catch {
            // Einzelner Puffer nicht konvertierbar – überspringen statt Aufnahme abzubrechen.
            if fedBuffers <= 3 || fedBuffers % 100 == 0 {
                transcriptionLog.error("convert failed #\(self.fedBuffers): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Restliches Audio verarbeiten, letzte Ergebnisse finalisieren und beenden.
    func finish() async {
        if let rest = try? converter?.flush() {
            rest.forEach { continuation?.yield($0) }
        }
        continuation?.finish()
        continuation = nil
        do {
            try await analyzer.finalizeAndFinishThroughEndOfInput()
        } catch {
            transcriptionLog.error("finalize failed: \(error.localizedDescription, privacy: .public)")
        }
        await resultsTask?.value
        await AssetInventory.release(reservedLocale: locale)
    }
}
