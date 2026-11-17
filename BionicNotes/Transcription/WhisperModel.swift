import CoreML
import Foundation
import Observation
import WhisperKit

/// Das Whisper-Modell für die genaue Nachtranskription.
///
/// Wird einmalig auf Wunsch geladen (~630 MB, von Hugging Face – es werden dabei **keine** Nutzerdaten
/// gesendet, nur die Modelldateien geholt). Danach läuft alles offline auf dem Gerät.
/// Liegt in Application Support und ist vom Backup ausgeschlossen.
@MainActor
@Observable
final class WhisperModel {
    static let shared = WhisperModel()

    /// large-v3-turbo, 4-bit-quantisiert: fast so genau wie large-v3, aber klein und schnell auf der Neural Engine.
    nonisolated static let variant = "openai_whisper-large-v3-v20240930_turbo_632MB"
    nonisolated static let repo = "argmaxinc/whisperkit-coreml"
    static let approximateSize = "630 MB"

    enum State: Equatable {
        case notInstalled
        case downloading(Double)
        case preparing
        case installed
        case failed(String)
    }

    private(set) var state: State

    private init() {
        state = FileManager.default.fileExists(atPath: Self.readyMarker.path) ? .installed : .notInstalled
    }

    var isInstalled: Bool { state == .installed }

    nonisolated static var baseFolder: URL {
        URL.applicationSupportDirectory.appending(path: "WhisperModels", directoryHint: .isDirectory)
    }
    nonisolated static var modelFolder: URL {
        baseFolder.appending(path: "models/\(repo)/\(variant)", directoryHint: .isDirectory)
    }
    nonisolated private static var readyMarker: URL { baseFolder.appending(path: "\(variant).ready") }

    /// Lädt das Modell herunter und bereitet es einmal vor (CoreML kompiliert es für die Neural Engine,
    /// der Tokenizer wird mitgeladen). Danach ist kein Netz mehr nötig.
    func install() async throws {
        if case .downloading = state { return }
        if state == .preparing || state == .installed { return }
        state = .downloading(0)
        do {
            try FileManager.default.createDirectory(at: Self.baseFolder, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var base = Self.baseFolder
            try? base.setResourceValues(values)

            _ = try await WhisperKit.download(variant: Self.variant, downloadBase: Self.baseFolder, from: Self.repo) { progress in
                let fraction = progress.fractionCompleted
                Task { @MainActor in
                    if case .downloading = WhisperModel.shared.state { WhisperModel.shared.state = .downloading(fraction) }
                }
            }
            state = .preparing
            try await WhisperEngine.shared.load()
            try Data().write(to: Self.readyMarker)
            state = .installed
        } catch is CancellationError {
            state = .notInstalled
            throw CancellationError()
        } catch {
            state = .failed(error.localizedDescription)
            throw error
        }
    }

    func remove() async {
        await WhisperEngine.shared.unload()
        try? FileManager.default.removeItem(at: Self.baseFolder)
        state = .notInstalled
    }

    /// Belegter Speicher in MB (für die Einstellungen).
    nonisolated static func diskUsageMB() -> Int {
        guard let enumerator = FileManager.default.enumerator(at: baseFolder, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var bytes = 0
        for case let url as URL in enumerator {
            bytes += (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        }
        return bytes / 1_000_000
    }
}

/// Hält die geladene WhisperKit-Instanz. Ein Actor, damit Laden/Transkribieren nicht auf dem MainActor läuft.
actor WhisperEngine {
    static let shared = WhisperEngine()

    private var kit: WhisperKit?

    func load() async throws {
        guard kit == nil else { return }
        // Mel-Spektrogramm auf der CPU (GPU ist im Hintergrund nicht erlaubt), Encoder/Decoder auf der Neural Engine.
        let compute = ModelComputeOptions(melCompute: .cpuOnly,
                                          audioEncoderCompute: .cpuAndNeuralEngine,
                                          textDecoderCompute: .cpuAndNeuralEngine)
        let config = WhisperKitConfig(model: WhisperModel.variant,
                                      downloadBase: WhisperModel.baseFolder,
                                      modelRepo: WhisperModel.repo,
                                      modelFolder: WhisperModel.modelFolder.path,
                                      tokenizerFolder: WhisperModel.baseFolder,
                                      computeOptions: compute,
                                      verbose: false,
                                      logLevel: .error,
                                      prewarm: false,
                                      load: true,
                                      download: false)
        kit = try await WhisperKit(config)
    }

    func unload() {
        kit = nil
    }

    /// Erkennt die gesprochene Sprache in (bis zu) 30 s Audio, z. B. „de“ oder „en“.
    func detectLanguage(_ samples: [Float]) async throws -> String {
        try await load()
        guard let kit else { return "de" }
        return try await kit.detectLangauge(audioArray: samples).language
    }

    /// Transkribiert 16-kHz-Mono-Samples. Zeiten in den Segmenten sind relativ zum Anfang von `samples`.
    func transcribe(_ samples: [Float], language: String) async throws -> [TranscriptionSegment] {
        try await load()
        guard let kit else { return [] }
        let options = DecodingOptions(task: .transcribe,
                                      language: language,
                                      temperature: 0,
                                      temperatureFallbackCount: 5,
                                      usePrefillPrompt: true,
                                      detectLanguage: false,
                                      skipSpecialTokens: true,
                                      withoutTimestamps: false,
                                      suppressBlank: true,
                                      compressionRatioThreshold: 2.4,
                                      logProbThreshold: -1.0,
                                      noSpeechThreshold: 0.6,
                                      concurrentWorkerCount: 4,
                                      chunkingStrategy: .vad)
        let results = try await kit.transcribe(audioArray: samples, decodeOptions: options)
        return results.flatMap(\.segments).sorted { $0.start < $1.start }
    }
}
