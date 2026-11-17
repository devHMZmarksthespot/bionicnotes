import AVFoundation
import Foundation
import WhisperKit

/// Lange Aufnahmen abschnittsweise mit Whisper transkribieren.
///
/// Abschnitte von ~5 Minuten, geschnitten an der leisesten Stelle in der Nähe der 5-Minuten-Marke,
/// damit kein Wort zerteilt wird. Jeder Abschnitt startet ohne den Text der vorherigen als Kontext
/// (wie whisper.cpp `--max-context 0`) – das verhindert Wiederholungsschleifen bei langen Vorträgen.
/// Innerhalb eines Abschnitts teilt WhisperKit per Sprach-Erkennung (VAD) in 30-s-Fenster.
enum ChunkedWhisper {
    static let chunkSeconds: Double = 300
    static let lookaheadSeconds: Double = 15

    /// `language`: fester Sprachcode („de“, „en“) oder `nil` = pro Abschnitt automatisch erkennen
    /// (für gemischte Aufnahmen; erzwingt man die falsche Sprache, übersetzt Whisper teilweise).
    static func transcribe(audioURL: URL, language: String?,
                           onProgress: @Sendable (Double) async -> Void) async throws -> [TranscriptSegment] {
        let path = audioURL.path
        let file = try AVAudioFile(forReading: audioURL)
        let total = Double(file.length) / file.fileFormat.sampleRate
        let rate = Double(WhisperKit.sampleRate)

        var position: Double = 0
        var segments: [TranscriptSegment] = []
        while position < total - 0.5 {
            try Task.checkCancellation()
            let readEnd = min(position + chunkSeconds + lookaheadSeconds, total)
            var samples = try autoreleasepool {
                try AudioProcessor.loadAudioAsFloatArray(fromPath: path, startTime: position, endTime: readEnd)
            }
            if readEnd < total {
                let cut = quietestPoint(in: samples, from: (chunkSeconds - lookaheadSeconds) * rate, to: Double(samples.count))
                samples = Array(samples[..<cut])
            }
            let length = Double(samples.count) / rate
            let isLast = readEnd >= total
            let chunkLanguage: String
            if let language { chunkLanguage = language } else { chunkLanguage = try await detectLanguage(samples) }
            var parts = removeOverlaps(try await WhisperEngine.shared.transcribe(samples, language: chunkLanguage))
            parts = try await repairGaps(parts, samples: samples, language: chunkLanguage)
            // Am Abschnittsende bricht Whisper den letzten Satz oft ab und lässt den Rest des Fensters weg.
            // Deshalb den letzten Satz verwerfen und den nächsten Abschnitt an dessen Anfang beginnen
            // (= nach dem letzten vollständigen Satz) – so geht an den Schnittstellen nichts verloren.
            var next = position + length
            if !isLast, parts.count > 1, let tail = parts.last, Double(tail.start) > length * 0.5 {
                parts.removeLast()
                next = position + Double(tail.start)
            }
            for part in parts {
                let text = clean(part.text)
                guard isPlausible(part, text: text, previous: segments.last?.text) else { continue }
                segments.append(TranscriptSegment(start: position + Double(part.start),
                                                  end: position + min(Double(part.end), length),
                                                  text: text))
            }
            position = max(next, position + 1)
            await onProgress(min(position / total, 1))
        }
        return segments
    }

    /// Sprache eines Abschnitts: Whisper-Erkennung auf den drei lautesten 30-s-Fenstern, Mehrheit gewinnt
    /// (bei Gleichstand das lauteste Fenster). Ein einzelnes Fenster kann bei Pausen oder Zurufen danebenliegen.
    static func detectLanguage(_ samples: [Float]) async throws -> String {
        let window = 30 * WhisperKit.sampleRate
        var windows: [(start: Int, loudness: Float)] = []
        var i = 0
        repeat {
            windows.append((i, loudness(samples[i..<min(i + window, samples.count)])))
            i += window
        } while i + window / 2 < samples.count
        var votes: [String] = []
        for w in windows.sorted(by: { $0.loudness > $1.loudness }).prefix(3) {
            votes.append(try await WhisperEngine.shared.detectLanguage(Array(samples[w.start..<min(w.start + window, samples.count)])))
        }
        let counts = Dictionary(votes.map { ($0, 1) }, uniquingKeysWith: +)
        let best = counts.values.max() ?? 0
        return votes.first { counts[$0] == best } ?? "de"
    }

    /// Bei schwierigen Stellen dekodiert Whisper ein Fenster mit höherer Temperatur neu; das liefert teils
    /// zusätzliche, überlappende Fassungen desselben Satzes. Pro Zeitbereich nur die erste behalten.
    static func removeOverlaps(_ parts: [TranscriptionSegment]) -> [TranscriptionSegment] {
        var out: [TranscriptionSegment] = []
        // Leere Segmente entstehen, wenn alle Dekodier-Versuche scheitern – sie würden die Lücke verdecken.
        for part in parts.sorted(by: { $0.start < $1.start }) where part.end > part.start && !clean(part.text).isEmpty {
            if let last = out.last, part.start < last.end - 0.5 { continue }
            out.append(part)
        }
        return out
    }

    static let gapSeconds: Float = 6

    /// Längere Lücken zwischen Segmenten, in denen hörbar gesprochen wird, gezielt nochmals transkribieren.
    /// (Whisper lässt gelegentlich ein ganzes 30-s-Fenster aus, wenn die Dekodierung dort mehrfach scheitert.)
    static func repairGaps(_ parts: [TranscriptionSegment], samples: [Float], language: String) async throws -> [TranscriptionSegment] {
        let rate = Float(WhisperKit.sampleRate)
        let length = Float(samples.count) / rate
        let reference = medianLoudness(samples)
        guard reference > 0 else { return parts }

        var bounds: [(Float, Float)] = []
        var cursor: Float = 0
        for part in parts {
            if part.start - cursor > gapSeconds { bounds.append((cursor, part.start)) }
            cursor = max(cursor, part.end)
        }
        if length - cursor > gapSeconds { bounds.append((cursor, length)) }

        var repaired = parts
        for (from, to) in bounds {
            try Task.checkCancellation()
            let a = Int(max(from - 0.5, 0) * rate), b = min(Int((to + 0.5) * rate), samples.count)
            guard b - a > Int(rate), loudness(samples[a..<b]) > reference * 0.5 else { continue }
            let offset = Float(a) / rate
            let extra = try await WhisperEngine.shared.transcribe(Array(samples[a..<b]), language: language)
            for var part in removeOverlaps(extra) {
                part.start += offset
                part.end += offset
                let mid = (part.start + part.end) / 2
                if mid > from && mid < to { repaired.append(part) }
            }
        }
        return removeOverlaps(repaired)
    }

    /// Anteil der 1-s-Fenster mit Sprache-typischem Pegel ist schwer zu schätzen – wir nehmen den Median-RMS
    /// über 1-s-Fenster als Bezug für „normal laut gesprochen“ in diesem Abschnitt.
    static func medianLoudness(_ samples: [Float]) -> Float {
        let window = WhisperKit.sampleRate
        guard samples.count >= window else { return loudness(samples[...]) }
        var values: [Float] = []
        var i = 0
        while i + window <= samples.count {
            values.append(loudness(samples[i..<(i + window)]))
            i += window
        }
        values.sort()
        return values[values.count / 2]
    }

    static func loudness(_ samples: ArraySlice<Float>) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for x in samples { sum += x * x }
        return (sum / Float(samples.count)).squareRoot()
    }

    /// Reste von Steuer-Tokens („<|de|>“, „<|0.00|>“) entfernen.
    static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: #"<\|[^|]*\|>"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Index der leisesten 200-ms-Stelle zwischen `from` und `to` (in Samples).
    static func quietestPoint(in samples: [Float], from: Double, to: Double) -> Int {
        let window = 3_200
        let start = max(Int(from), 0)
        let end = min(Int(to), samples.count) - window
        guard end > start else { return samples.count }
        var best = end + window / 2
        var bestEnergy = Float.greatestFiniteMagnitude
        var i = start
        while i < end {
            var energy: Float = 0
            for j in i..<(i + window) { energy += samples[j] * samples[j] }
            if energy < bestEnergy { bestEnergy = energy; best = i + window / 2 }
            i += window / 2
        }
        return best
    }

    /// Bekannte Whisper-Halluzinationen in Stille/Musik und direkte Wiederholungen aussortieren.
    static func isPlausible(_ segment: TranscriptionSegment, text: String, previous: String?) -> Bool {
        guard !text.isEmpty else { return false }
        if segment.noSpeechProb > 0.6 && segment.avgLogprob < -1 { return false }
        if segment.compressionRatio > 2.6 { return false }
        if let previous, previous.caseInsensitiveCompare(text) == .orderedSame, text.count < 80 { return false }
        let lower = text.lowercased()
        // Reine Geräusch-Markierungen („* Applaus *“, „(Musik)“)
        let bare = lower.trimmingCharacters(in: CharacterSet(charactersIn: "*()[]♪ .!"))
        if ["applaus", "beifall", "musik", "lachen", "gelächter", "applause", "music", "laughter", "stille"].contains(bare) { return false }
        let hallucinations = ["untertitel im auftrag des zdf", "untertitelung des zdf", "untertitelung im auftrag des zdf",
                              "untertitel von stephanie geiges", "vielen dank fürs zuschauen", "thanks for watching",
                              "thank you for watching", "amara.org"]
        return !hallucinations.contains { lower.contains($0) }
    }
}
