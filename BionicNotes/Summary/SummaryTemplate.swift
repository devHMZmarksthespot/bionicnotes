import Foundation

/// Die festen Vorlagen für die Nachbearbeitung. Bewusst statisch (kein freier Assistent),
/// damit der Kunde nur auswählen muss. Reihenfolge = Reihenfolge in der Auswahl.
enum SummaryTemplate: String, CaseIterable, Identifiable, Codable, Sendable {
    case meetingMinutes
    case executiveSummary
    case actionItems
    case report
    case talkNotes
    case lecture
    case interview
    case workshop
    case clientMeeting
    case slideDeck

    var id: String { rawValue }

    var title: String {
        switch self {
        case .meetingMinutes: "Meeting-Protokoll"
        case .executiveSummary: "Kurzfassung"
        case .actionItems: "Aufgaben & Entscheidungen"
        case .report: "Bericht"
        case .talkNotes: "Konferenz-Notizen"
        case .lecture: "Lernnotizen"
        case .interview: "Interview"
        case .workshop: "Workshop & Brainstorming"
        case .clientMeeting: "Kundengespräch"
        case .slideDeck: "Folien-Übersicht"
        }
    }

    var subtitle: String {
        switch self {
        case .meetingMinutes: "Themen, Diskussion, Beschlüsse, Pendenzen"
        case .executiveSummary: "Das Wichtigste in wenigen Sätzen"
        case .actionItems: "Wer macht was bis wann – und was wurde entschieden"
        case .report: "Ausgangslage, Inhalte, Erkenntnisse, Fazit"
        case .talkNotes: "Kernaussagen, Zitate und Takeaways eines Vortrags"
        case .lecture: "Begriffe, Erklärungen, Fragen zum Wiederholen"
        case .interview: "Fragen und Antworten, zentrale Aussagen"
        case .workshop: "Ideen, Gruppen, Bewertung, nächste Schritte"
        case .clientMeeting: "Anliegen, Bedürfnisse, Vereinbarungen, Follow-up"
        case .slideDeck: "Folie für Folie mit dem, was dazu gesagt wurde"
        }
    }

    var symbol: String {
        switch self {
        case .meetingMinutes: "list.bullet.clipboard"
        case .executiveSummary: "text.append"
        case .actionItems: "checklist"
        case .report: "doc.richtext"
        case .talkNotes: "person.wave.2"
        case .lecture: "graduationcap"
        case .interview: "bubble.left.and.bubble.right"
        case .workshop: "lightbulb"
        case .clientMeeting: "handshake"
        case .slideDeck: "rectangle.on.rectangle"
        }
    }

    /// Abschnitts-Überschriften in der Sprache der Session.
    func sections(english: Bool) -> [String] {
        switch self {
        case .meetingMinutes:
            english ? ["Topics", "Discussion", "Decisions", "Action items", "Open questions"]
                    : ["Themen", "Diskussion", "Beschlüsse", "Pendenzen", "Offene Fragen"]
        case .executiveSummary:
            english ? ["Summary", "Key points"]
                    : ["Zusammenfassung", "Kernpunkte"]
        case .actionItems:
            english ? ["Decisions", "Action items", "Open questions"]
                    : ["Entscheidungen", "Aufgaben", "Offene Fragen"]
        case .report:
            english ? ["Background", "Content", "Findings", "Conclusion"]
                    : ["Ausgangslage", "Inhalt", "Erkenntnisse", "Fazit"]
        case .talkNotes:
            english ? ["Core message", "Key statements", "Notable quotes", "Takeaways"]
                    : ["Kernbotschaft", "Wichtigste Aussagen", "Bemerkenswerte Zitate", "Takeaways"]
        case .lecture:
            english ? ["Overview", "Key terms", "Explanations", "Review questions"]
                    : ["Überblick", "Wichtige Begriffe", "Erklärungen", "Fragen zum Wiederholen"]
        case .interview:
            english ? ["Context", "Questions and answers", "Key statements"]
                    : ["Kontext", "Fragen und Antworten", "Zentrale Aussagen"]
        case .workshop:
            english ? ["Goal", "Ideas", "Clusters and assessment", "Next steps"]
                    : ["Ziel", "Ideen", "Gruppierung und Bewertung", "Nächste Schritte"]
        case .clientMeeting:
            english ? ["Client concerns", "Needs and requirements", "Agreements", "Follow-up"]
                    : ["Anliegen des Kunden", "Bedürfnisse und Anforderungen", "Vereinbarungen", "Follow-up"]
        case .slideDeck:
            english ? ["Slides", "Overall summary"]
                    : ["Folien", "Gesamtfazit"]
        }
    }

    /// Was die Vorlage inhaltlich verlangt – Anweisung an das On-Device-Modell.
    var guidance: String {
        switch self {
        case .meetingMinutes:
            "Write formal meeting minutes. List the topics discussed, summarize the discussion per topic, state every decision, and list action items as '- Task – owner – due date' (use '–' when owner or date is unknown)."
        case .executiveSummary:
            "Write a short executive summary: one paragraph of at most five sentences, then at most five bullet points with the key points."
        case .actionItems:
            "Extract only decisions, action items and open questions. Action items as '- Task – owner – due date' (use '–' when unknown). No general summary."
        case .report:
            "Write a neutral, well-structured report in full sentences that someone who was not present can understand."
        case .talkNotes:
            "Summarize a conference talk: the core message in one or two sentences, the most important statements as bullets, literal quotes worth keeping (only if clearly stated), and practical takeaways."
        case .lecture:
            "Create study notes for a lecture or lesson: a short overview, important terms with a one-line explanation each, the main explanations, and three to five review questions."
        case .interview:
            "Summarize an interview as pairs of question and answer (condensed, not verbatim), then the most important statements."
        case .workshop:
            "Summarize a workshop or brainstorming: the goal, all ideas as bullets, how ideas were grouped or rated, and agreed next steps."
        case .clientMeeting:
            "Summarize a client meeting: the client's concerns, their needs and requirements, everything that was agreed (prices, dates, scope) and the follow-up tasks."
        case .slideDeck:
            "Go through the slides in order. For each slide write a heading '### Slide N (time)' with its main content and what the speaker said about it. Then give an overall summary."
        }
    }
}
