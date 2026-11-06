#if DEBUG
import AVFoundation

/// Nur Debug: `-transcriptionSelfTest <Pfad zu Audiodatei> [locale]` als Launch-Argument
/// schickt die Datei in Mikrofon-Puffergröße durch denselben Weg wie die Live-Aufnahme
/// (LiveTranscriber.feed) und gibt die Ergebnisse auf der Konsole aus.
enum TranscriptionSelfTest {
    static func runIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-transcriptionSelfTest"), i + 1 < args.count else { return }
        let path = args[i + 1]
        // Relativer Pfad → im Documents-Ordner der App (dorthin kopiert devicectl die Testdatei).
        let url = path.hasPrefix("/") ? URL(fileURLWithPath: path) : URL.documentsDirectory.appending(path: path)
        let locale = Locale(identifier: i + 2 < args.count ? args[i + 2] : "de-DE")
        Task.detached { await run(url: url, locale: locale) }
    }

    private static func run(url: URL, locale: Locale) async {
        print("[SelfTest] start \(url.lastPathComponent) \(locale.identifier)")
        do {
            let t = try await LiveTranscriber.prepare(locale: locale) { p in print("[SelfTest] download \(Int(p * 100)) %") }
            try await t.start { update in
                print("[SelfTest] \(update.isFinal ? "FINAL" : "volatile") [\(String(format: "%.1f", update.start))–\(String(format: "%.1f", update.end))] \(update.text)")
            }
            let file = try AVAudioFile(forReading: url)
            let format = file.processingFormat
            while file.framePosition < file.length {
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096) else { break }
                try file.read(into: buffer, frameCount: 4096)
                t.feed(buffer)
                try await Task.sleep(for: .milliseconds(20))
            }
            await t.finish()
            print("[SelfTest] done")
        } catch {
            print("[SelfTest] FAILED: \(error)")
        }
    }
}
#endif
