import Foundation

/// Eigene Fachbegriffe (Firmen, Produkte, Namen, Abkürzungen), die die Transkription kennen soll.
///
/// - Live-Transkription: als Kontext für den SpeechAnalyzer (`contextualStrings`).
/// - Danach (live und Whisper): Schreibweise korrigieren, z. B. „Multi-Rail“ → „Multirail“, „Twint“ → „TWINT“.
///   Bewusst *kein* Whisper-Prompt: Im Test mit echten Aufnahmen ließ Whisper mit Prompt ~7 % des Textes aus
///   und verlor die Zeitstempel; die Begriffe selbst erkennt es meist richtig, nur anders geschrieben.
///
/// Liegt nur in den UserDefaults dieses Geräts.
enum Glossary {
    private static let key = "glossaryTerms"

    /// Rohtext wie eingegeben: ein Begriff pro Zeile oder durch Kommas getrennt.
    static var text: String {
        get { UserDefaults.standard.string(forKey: key) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// Die korrekten Schreibweisen (ohne Varianten) – für Spracherkennung und Sprachmodell.
    static var terms: [String] { parse(text) }

    /// Rohe Einträge, inkl. Varianten wie „Cloud Code → Claude Code“ oder „Finova / Finnowa = Finnova“.
    static var entries: [String] { splitEntries(text) }

    static func parse(_ text: String) -> [String] {
        var seen = Set<String>()
        return splitEntries(text).map { variants(of: $0).spelling }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    private static func splitEntries(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: ",;\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static let arrow = try! NSRegularExpression(pattern: #"\s*(?:→|->|=>|=)\s*"#)

    /// „A / B → C“ → Varianten [A, B], Schreibweise C. Ohne Pfeil: keine Varianten.
    private static func variants(of entry: String) -> (variants: [String], spelling: String) {
        let ns = entry as NSString
        guard let match = arrow.firstMatch(in: entry, range: NSRange(location: 0, length: ns.length)) else {
            return ([], entry)
        }
        let left = ns.substring(to: match.range.location)
        let right = ns.substring(from: NSMaxRange(match.range)).trimmingCharacters(in: .whitespaces)
        let variants = left.components(separatedBy: "/").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return (variants, right)
    }

    // MARK: - Schreibweise korrigieren

    static func correct(_ segments: [TranscriptSegment], entries: [String] = Glossary.entries) -> [TranscriptSegment] {
        let prepared = prepare(entries)
        guard !prepared.isEmpty else { return segments }
        return segments.map { segment in
            var copy = segment
            copy.text = correct(segment.text, prepared: prepared)
            return copy
        }
    }

    static func correct(_ text: String, entries: [String] = Glossary.entries) -> String {
        correct(text, prepared: prepare(entries))
    }

    private struct Term {
        let spelling: String
        let key: String   // klein, ohne Leer-/Bindestriche
        let words: Int
    }

    private static func prepare(_ entries: [String]) -> [Term] {
        entries.flatMap { entry -> [Term] in
            let (variants, spelling) = variants(of: entry)
            guard !spelling.isEmpty else { return [] }
            return ([spelling] + variants).compactMap { form in
                let key = normalized(form)
                guard key.count >= 3 else { return nil }
                return Term(spelling: spelling, key: key, words: form.split(whereSeparator: { $0 == " " || $0 == "-" }).count)
            }
        }
    }

    private static func normalized(_ s: String) -> String {
        s.lowercased().replacingOccurrences(of: "ß", with: "ss").filter { $0.isLetter || $0.isNumber }
    }

    private static let wordPattern = try! NSRegularExpression(pattern: #"[\p{L}\p{N}]+"#)

    /// Sucht Folgen von 1–3 Wörtern (nur durch Leerzeichen/Bindestrich getrennt), die – ohne Gross/klein,
    /// Leer- und Bindestriche – dem Begriff oder einer seiner Varianten entsprechen. Bei langen Begriffen
    /// sind 1–2 Tippfehler erlaubt, wenn der Anfangsbuchstabe stimmt.
    private static func correct(_ text: String, prepared terms: [Term]) -> String {
        let ns = text as NSString
        let words = wordPattern.matches(in: text, range: NSRange(location: 0, length: ns.length)).map(\.range)
        guard !words.isEmpty else { return text }

        var replacements: [(NSRange, String)] = []
        var i = 0
        while i < words.count {
            var matched = false
            for n in stride(from: min(3, words.count - i), through: 1, by: -1) {
                let first = words[i], last = words[i + n - 1]
                // Zwischen den Wörtern nur Leerzeichen oder Bindestriche
                var joinable = true
                for k in i..<(i + n - 1) {
                    let gap = ns.substring(with: NSRange(location: NSMaxRange(words[k]),
                                                         length: words[k + 1].location - NSMaxRange(words[k])))
                    if gap.isEmpty || !gap.allSatisfy({ $0 == " " || $0 == "-" }) { joinable = false; break }
                }
                guard joinable else { continue }
                let range = NSRange(location: first.location, length: NSMaxRange(last) - first.location)
                let candidate = ns.substring(with: range)
                let key = normalized(candidate)
                guard let term = terms.first(where: { term in
                    guard abs(term.words - n) <= 2 else { return false }
                    if term.key == key { return true }
                    // Tippfehler-Toleranz: ab 8 Zeichen 1, ab 10 Zeichen 2 (z. B. „Cloud Code“ → „Claude Code“)
                    let tolerance = term.key.count >= 10 ? 2 : (term.key.count >= 8 ? 1 : 0)
                    return tolerance > 0 && n == term.words && key.first == term.key.first
                        && abs(key.count - term.key.count) <= tolerance
                        && editDistance(key, term.key, limit: tolerance) <= tolerance
                }) else { continue }
                if candidate != term.spelling { replacements.append((range, term.spelling)) }
                i += n
                matched = true
                break
            }
            if !matched { i += 1 }
        }
        guard !replacements.isEmpty else { return text }
        let out = NSMutableString(string: text)
        for (range, spelling) in replacements.reversed() { out.replaceCharacters(in: range, with: spelling) }
        return out as String
    }

    private static func editDistance(_ a: String, _ b: String, limit: Int) -> Int {
        let a = Array(a), b = Array(b)
        var previous = Array(0...b.count)
        for i in 1...max(a.count, 1) where !a.isEmpty {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...max(b.count, 1) where !b.isEmpty {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            if current.min()! > limit { return limit + 1 }
            previous = current
        }
        return previous[b.count]
    }
}
