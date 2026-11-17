import Foundation

/// Fassung nach Vorlage ohne Sprachmodell (Geräte ohne Apple Intelligence):
/// Schlüsselsätze per Worthäufigkeit, Aufgaben/Beschlüsse/Fragen per Stichwort,
/// ⭐-Marker und Folien direkt. Ehrlich als Entwurf gekennzeichnet – der Kunde ergänzt.
enum StructuredSummarizer {
    private struct Sentence {
        let time: TimeInterval
        let text: String
    }

    private enum Kind {
        case overview, keyPoints, decisions, tasks, questions, questionsWithAnswers, markers, slides, manual
    }

    static func body(for template: SummaryTemplate, content: SessionContent) -> String {
        let english = content.isEnglish
        let sentences = split(content.segments)
        let headings = template.sections(english: english)
        let kinds = kinds(for: template)

        var out = english
            ? "> Structured draft without Apple Intelligence – please review and complete.\n"
            : "> Strukturierter Entwurf ohne Apple Intelligence – bitte prüfen und ergänzen.\n"
        for (index, heading) in headings.enumerated() {
            out += "\n## \(heading)\n\n"
            let kind = index < kinds.count ? kinds[index] : .manual
            out += section(kind, sentences: sentences, content: content, english: english) + "\n"
        }
        return out
    }

    private static func kinds(for template: SummaryTemplate) -> [Kind] {
        switch template {
        case .meetingMinutes: [.keyPoints, .markers, .decisions, .tasks, .questions]
        case .executiveSummary: [.overview, .keyPoints]
        case .actionItems: [.decisions, .tasks, .questions]
        case .report: [.overview, .keyPoints, .markers, .manual]
        case .talkNotes: [.overview, .keyPoints, .markers, .manual]
        case .lecture: [.overview, .manual, .keyPoints, .questions]
        case .interview: [.overview, .questionsWithAnswers, .keyPoints]
        case .workshop: [.manual, .keyPoints, .manual, .tasks]
        case .clientMeeting: [.keyPoints, .manual, .decisions, .tasks]
        case .slideDeck: [.slides, .overview]
        }
    }

    private static func section(_ kind: Kind, sentences: [Sentence], content: SessionContent, english: Bool) -> String {
        let empty = "–"
        func bullets(_ list: [Sentence]) -> String {
            list.isEmpty ? empty : list.map { "- [\($0.time.clockString)] \($0.text)" }.joined(separator: "\n")
        }
        switch kind {
        case .overview:
            let top = keySentences(sentences, count: 3)
            return top.isEmpty ? empty : top.map(\.text).joined(separator: " ")
        case .keyPoints:
            return bullets(keySentences(sentences, count: min(8, max(3, sentences.count / 15))))
        case .decisions:
            return bullets(sentences.filter { matches($0.text, english ? decisionWordsEN : decisionWordsDE) })
        case .tasks:
            return bullets(sentences.filter { matches($0.text, english ? taskWordsEN : taskWordsDE) })
        case .questions:
            return bullets(sentences.filter { $0.text.hasSuffix("?") })
        case .questionsWithAnswers:
            var pairs: [String] = []
            for (index, sentence) in sentences.enumerated() where sentence.text.hasSuffix("?") {
                let answer = sentences.dropFirst(index + 1).prefix(2).map(\.text).joined(separator: " ")
                pairs.append("- **[\(sentence.time.clockString)] \(sentence.text)**" + (answer.isEmpty ? "" : "\n  \(answer)"))
            }
            return pairs.isEmpty ? empty : pairs.joined(separator: "\n")
        case .markers:
            guard !content.markers.isEmpty else { return empty }
            return content.markers.map { "- ⭐ [\($0.time.clockString)] \($0.snippet.suffix(240))" }.joined(separator: "\n")
        case .slides:
            guard !content.slides.isEmpty else { return empty }
            return content.slides.enumerated().map { index, slide in
                let time = slide.time.map { " (\($0.clockString))" } ?? ""
                var text = "### \(english ? "Slide" : "Folie") \(index + 1)\(time)\n\n"
                let ocr = (slide.recognizedText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                text += ocr.isEmpty ? empty : ocr
                if let time = slide.time {
                    let said = sentences.filter { $0.time >= time && $0.time < time + 60 }.prefix(3).map(\.text)
                    if !said.isEmpty { text += "\n\n*\(english ? "Said" : "Gesagt"):* " + said.joined(separator: " ") }
                }
                return text
            }.joined(separator: "\n\n")
        case .manual:
            return english ? "– *(please complete)*" : "– *(bitte ergänzen)*"
        }
    }

    // MARK: - Sätze

    private static func split(_ segments: [TranscriptSegment]) -> [Sentence] {
        var result: [Sentence] = []
        for segment in segments {
            var current = ""
            for char in segment.text {
                current.append(char)
                if ".?!".contains(char) {
                    append(current, time: segment.start, to: &result)
                    current = ""
                }
            }
            append(current, time: segment.start, to: &result)
        }
        return result
    }

    private static func append(_ text: String, time: TimeInterval, to list: inout [Sentence]) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Sehr kurze Fetzen („Ja.“, „Okay.“) sind keine Aussagen.
        guard trimmed.split(separator: " ").count >= 4 else { return }
        list.append(Sentence(time: time, text: trimmed))
    }

    /// Schlüsselsätze: Summe der Häufigkeit ihrer Inhaltswörter, normalisiert auf die Satzlänge.
    /// Ergebnis in zeitlicher Reihenfolge.
    private static func keySentences(_ sentences: [Sentence], count: Int) -> [Sentence] {
        guard !sentences.isEmpty else { return [] }
        func words(_ text: String) -> [String] {
            text.lowercased()
                .components(separatedBy: CharacterSet.letters.inverted)
                .filter { $0.count >= 5 && !stopWords.contains($0) }
        }
        var frequency: [String: Int] = [:]
        for sentence in sentences { for word in words(sentence.text) { frequency[word, default: 0] += 1 } }
        let scored = sentences.enumerated().map { index, sentence -> (Int, Double) in
            let list = words(sentence.text)
            guard !list.isEmpty else { return (index, 0) }
            let score = Double(list.reduce(0) { $0 + (frequency[$1] ?? 0) }) / sqrt(Double(list.count))
            return (index, score)
        }
        let chosen = scored.sorted { $0.1 > $1.1 }.prefix(count).map(\.0).sorted()
        return chosen.map { sentences[$0] }
    }

    private static func matches(_ text: String, _ words: [String]) -> Bool {
        let lower = text.lowercased()
        return words.contains { lower.contains($0) }
    }

    private static let taskWordsDE = ["müssen", "muss ", "sollten", "sollte ", "bis zum", "bis ende", "bis nächste",
                                      "aufgabe", "to-do", "todo", "erledig", "kümmert sich", "kümmere mich", "übernimmt",
                                      "übernehme", "schickt", "schicke", "wir werden", "ich werde", "nächster schritt",
                                      "nächste schritte", "follow-up", "deadline", "frist"]
    private static let taskWordsEN = ["need to", "needs to", "have to", "has to", "should", "will send", "action item",
                                      "to-do", "todo", "follow up", "follow-up", "deadline", "next step", "take care of",
                                      "i'll", "we'll", "by monday", "by friday", "by next week"]
    private static let decisionWordsDE = ["entschieden", "entscheiden uns", "beschlossen", "beschliessen", "beschließen",
                                          "geeinigt", "einigen uns", "festgelegt", "vereinbart", "abgemacht",
                                          "freigegeben", "machen wir so"]
    private static let decisionWordsEN = ["decided", "decision", "agreed", "approved", "settled on", "let's go with",
                                          "we will go with", "we'll go with"]

    private static let stopWords: Set<String> = [
        // Deutsch
        "aber", "alles", "allem", "andere", "anderen", "auch", "dann", "darum", "dass", "deine", "denen", "denn",
        "diese", "diesem", "diesen", "dieser", "dieses", "doch", "durch", "eigentlich", "einem", "einen", "einer",
        "eines", "einfach", "etwas", "gerade", "haben", "habe", "hatte", "hätte", "immer", "jetzt", "kann", "können",
        "könnte", "machen", "macht", "meine", "mehr", "nicht", "noch", "nochmal", "oder", "schon", "sehr", "sein",
        "seine", "sich", "sind", "ganz", "genau", "unsere", "unser", "viele", "vielleicht", "werden", "wird", "wirklich",
        "würde", "wurde", "weil", "wenn", "wieder", "wollen", "zwischen", "also", "eben", "halt", "okay", "quasi",
        // English
        "about", "after", "again", "because", "before", "being", "could", "doing", "every", "going", "having",
        "maybe", "might", "other", "really", "should", "something", "their", "there", "these", "thing", "things",
        "think", "those", "where", "which", "while", "would", "actually", "basically", "right", "today",
    ]
}
