import AVFoundation
import BackgroundTasks
import Foundation
import Observation
import OSLog
import UIKit

/// Genaue Nachtranskription einer Session mit Whisper – vollständig auf dem Gerät.
///
/// Die Aufnahme wird in Abschnitten von ~5 Minuten (Schnitt an einer leisen Stelle) gelesen und
/// transkribiert; jeder Abschnitt startet ohne Kontext der vorherigen, damit Whisper nicht in
/// Wiederholungsschleifen gerät. Das Live-Transkript bleibt als `transcript-live.json` erhalten.
/// Läuft per `BGContinuedProcessingTask` weiter, wenn die App in den Hintergrund geht.
@MainActor
@Observable
final class Retranscriber {
    static let shared = Retranscriber()

    struct Input: Sendable {
        let sessionID: UUID
        let title: String
        let folderURL: URL
        let language: String
        let duration: TimeInterval
        /// Sprache für Whisper: „de“, „en“ oder `nil` = pro Abschnitt automatisch erkennen.
        var whisperLanguage: String? = nil

        var audioURL: URL { folderURL.appending(path: "audio.m4a") }
        var transcriptURL: URL { folderURL.appending(path: "transcript.json") }
        var liveBackupURL: URL { folderURL.appending(path: Retranscriber.liveBackupName) }
    }

    enum Phase: Equatable {
        case downloadingModel(Double)
        case preparingModel
        case transcribing(Double)
        case finished(segments: Int)
        case failed(String)

        var isActive: Bool {
            switch self {
            case .downloadingModel, .preparingModel, .transcribing: true
            case .finished, .failed: false
            }
        }
    }

    struct Job: Equatable {
        let sessionID: UUID
        var phase: Phase
    }

    nonisolated static let liveBackupName = "transcript-live.json"
    nonisolated static let backgroundTaskPrefix = "hmzinnovation.bionicnotes.retranscribe"

    private(set) var job: Job?
    /// Zählt hoch, wenn ein neues Transkript geschrieben wurde – Ansichten laden dann neu.
    private(set) var revision = 0

    private var work: Task<Void, Never>?
    private var backgroundTask: BGContinuedProcessingTask?
    private let progress = Progress(totalUnitCount: 1_000)
    private let log = Logger(subsystem: "hmzinnovation.bionicnotes", category: "retranscribe")

    var isBusy: Bool { job?.phase.isActive == true }

    func job(for sessionID: UUID) -> Job? { job?.sessionID == sessionID ? job : nil }

    // MARK: - Start / Abbruch

    func start(_ input: Input) {
        guard !isBusy else { return }
        job = Job(sessionID: input.sessionID, phase: WhisperModel.shared.isInstalled ? .preparingModel : .downloadingModel(0))
        progress.completedUnitCount = 0
        UIApplication.shared.isIdleTimerDisabled = true
        submitBackgroundTask(title: input.title)
        work = Task { await run(input) }
    }

    func cancel() {
        work?.cancel()
    }

    func dismissResult() {
        if job?.phase.isActive == false { job = nil }
    }

    // MARK: - Ablauf

    private func run(_ input: Input) async {
        defer {
            UIApplication.shared.isIdleTimerDisabled = false
            work = nil
        }
        do {
            if !WhisperModel.shared.isInstalled {
                let watcher = Task { [weak self] in
                    while !Task.isCancelled {
                        if case .downloading(let f) = WhisperModel.shared.state { self?.update(.downloadingModel(f), fraction: f * 0.1) }
                        if WhisperModel.shared.state == .preparing { self?.update(.preparingModel, fraction: 0.1) }
                        try? await Task.sleep(for: .milliseconds(300))
                    }
                }
                defer { watcher.cancel() }
                try await WhisperModel.shared.install()
            }
            update(.preparingModel, fraction: 0.1)
            try await WhisperEngine.shared.load()
            try Task.checkCancellation()

            let segments = try await transcribe(input) { [weak self] fraction in
                self?.update(.transcribing(fraction), fraction: 0.1 + 0.9 * fraction)
            }
            try Task.checkCancellation()
            try save(segments, for: input)
            revision += 1
            finish(.finished(segments: segments.count), success: true)
            log.info("retranscribe done: \(segments.count) segments")
        } catch is CancellationError {
            job = nil
            finish(nil, success: false)
        } catch {
            log.error("retranscribe failed: \(error.localizedDescription, privacy: .public)")
            finish(.failed(error.localizedDescription), success: false)
        }
        // Modell nach dem Lauf freigeben (~1 GB RAM)
        await WhisperEngine.shared.unload()
    }

    private func update(_ phase: Phase, fraction: Double) {
        guard job != nil else { return }
        job?.phase = phase
        progress.completedUnitCount = Int64(min(max(fraction, 0), 1) * 1_000)
        if let backgroundTask {
            switch phase {
            case .downloadingModel: backgroundTask.updateTitle(backgroundTask.title, subtitle: "Sprachmodell wird geladen …")
            case .preparingModel: backgroundTask.updateTitle(backgroundTask.title, subtitle: "Sprachmodell wird vorbereitet …")
            case .transcribing(let f): backgroundTask.updateTitle(backgroundTask.title, subtitle: "Transkribiere … \(Int(f * 100)) %")
            default: break
            }
        }
    }

    private func finish(_ phase: Phase?, success: Bool) {
        if let phase { job?.phase = phase }
        backgroundTask?.setTaskCompleted(success: success)
        backgroundTask = nil
    }

    /// Abschnittsweise lesen und transkribieren. Läuft nicht auf dem MainActor.
    nonisolated private func transcribe(_ input: Input,
                                        onProgress: @escaping @MainActor (Double) -> Void) async throws -> [TranscriptSegment] {
        guard FileManager.default.fileExists(atPath: input.audioURL.path) else { throw RetranscribeError.noAudio }
        let segments = try await ChunkedWhisper.transcribe(audioURL: input.audioURL, language: input.whisperLanguage,
                                                           onProgress: { fraction in await onProgress(fraction) })
        return Glossary.correct(segments)
    }

    private func save(_ segments: [TranscriptSegment], for input: Input) throws {
        guard !segments.isEmpty else { throw RetranscribeError.empty }
        let fm = FileManager.default
        // Live-Transkript einmalig sichern (nicht überschreiben, wenn schon einmal nachtranskribiert wurde)
        if !fm.fileExists(atPath: input.liveBackupURL.path), fm.fileExists(atPath: input.transcriptURL.path) {
            try fm.copyItem(at: input.transcriptURL, to: input.liveBackupURL)
        }
        let file = TranscriptFile(locale: input.language, segments: segments, engine: TranscriptFile.Engine.whisper.rawValue)
        try JSONEncoder().encode(file).write(to: input.transcriptURL, options: [.atomic, .completeFileProtection])
    }

    /// Live-Transkript wiederherstellen.
    func restoreLive(folderURL: URL) {
        let backup = folderURL.appending(path: Self.liveBackupName)
        let target = folderURL.appending(path: "transcript.json")
        guard FileManager.default.fileExists(atPath: backup.path) else { return }
        try? FileManager.default.removeItem(at: target)
        try? FileManager.default.moveItem(at: backup, to: target)
        revision += 1
        if job?.phase.isActive == false { job = nil }
    }

    // MARK: - Hintergrund

    private func attach(_ task: BGContinuedProcessingTask) {
        guard isBusy else { task.setTaskCompleted(success: true); return }
        backgroundTask = task
        task.progress.totalUnitCount = progress.totalUnitCount
        task.progress.addChild(progress, withPendingUnitCount: progress.totalUnitCount)
        task.expirationHandler = { [weak self] in
            Task { @MainActor in self?.cancel() }
        }
    }

    /// Pro Lauf eine eigene ID (Wildcard `…retranscribe.*` in der Info.plist). Der Handler muss für genau diese
    /// ID registriert sein, bevor iOS den Task startet – sonst beendet iOS die App
    /// („No launch handler registered for task with identifier …“).
    private func submitBackgroundTask(title: String) {
        let identifier = Self.backgroundTaskPrefix + "." + UUID().uuidString
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { task in
            guard let task = task as? BGContinuedProcessingTask else { task.setTaskCompleted(success: false); return }
            MainActor.assumeIsolated { Retranscriber.shared.attach(task) }
        }
        guard registered else {
            log.info("continued processing: register failed, läuft nur im Vordergrund")
            return
        }
        let request = BGContinuedProcessingTaskRequest(identifier: identifier,
                                                       title: "Genaue Transkription",
                                                       subtitle: title)
        request.strategy = .fail
        let log = log
        Task {
            do {
                try await BGTaskScheduler.shared.submitTaskRequest(request)
            } catch {
                // Ohne Hintergrund-Erlaubnis läuft es trotzdem, solange die App offen bleibt.
                log.info("continued processing not available: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

enum RetranscribeError: LocalizedError {
    case noAudio
    case empty

    var errorDescription: String? {
        switch self {
        case .noAudio: "Zu dieser Session gibt es keine Audioaufnahme."
        case .empty: "In der Aufnahme wurde keine Sprache erkannt. Das bisherige Transkript bleibt unverändert."
        }
    }
}

