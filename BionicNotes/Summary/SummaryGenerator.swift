import Foundation
import FoundationModels
import NaturalLanguage
import OSLog

private let summaryLog = Logger(subsystem: "hmzinnovation.bionicnotes", category: "summary")

enum SummaryError: LocalizedError {
    case noContent

    var errorDescription: String? {
        switch self {
        case .noContent: "Diese Session hat noch kein Transkript und keine Folien – es gibt nichts zusammenzufassen."
        }
    }
}

/// Erzeugt Zusammenfassungen nach einer Vorlage.
///
/// - Standard: Apples On-Device-Sprachmodell (`SystemLanguageModel`) – nichts verlässt das Gerät.
/// - Opt-in: eigener OpenAI-Key (Drittanbieter, höchste Genauigkeit) – siehe `OpenAIClient`.
/// - Opt-in: Apples grösseres Modell auf Private Cloud Compute (32K Kontext). Das Transkript wird dafür
///   verschlüsselt an Apple gesendet, nur für diese Anfrage verwendet und nicht gespeichert.
///   Fällt bei Netz-/Kontingentproblemen automatisch auf das Gerät zurück.
/// Lange Transkripte, die nicht ins Kontextfenster passen: zuerst Abschnitt für Abschnitt Stichpunkte
/// („map“), danach das Dokument nach Vorlage aus diesen Stichpunkten („reduce“).
/// Ohne Apple Intelligence (oder wenn das Modell ablehnt): strukturierte Fassung, siehe `StructuredSummarizer`.
enum SummaryGenerator {
    enum Availability: Equatable {
        case onDevice
        case structuredOnly(reason: String)
    }

    enum Backend: Sendable {
        case onDevice
        case privateCloud
    }

    struct Progress: Equatable {
        var step: Int
        var total: Int
        var label: String
    }

    struct Result {
        var summary: SessionSummary
        /// Hinweis, falls statt des gewählten Modells etwas anderes verwendet wurde.
        var notice: String?
    }

    static func availability(language: String) -> Availability {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            guard model.supportsLocale(Locale(identifier: language)) else {
                return .structuredOnly(reason: "Apple Intelligence unterstützt diese Sprache auf dem Gerät noch nicht.")
            }
            return .onDevice
        case .unavailable(.deviceNotEligible):
            return .structuredOnly(reason: "Dieses Gerät unterstützt Apple Intelligence nicht.")
        case .unavailable(.appleIntelligenceNotEnabled):
            return .structuredOnly(reason: "Apple Intelligence ist ausgeschaltet (Einstellungen › Apple Intelligence & Siri).")
        case .unavailable(.modelNotReady):
            return .structuredOnly(reason: "Das Apple-Intelligence-Modell wird noch geladen – später erneut versuchen.")
        case .unavailable:
            return .structuredOnly(reason: "Apple Intelligence ist gerade nicht verfügbar.")
        }
    }

    // MARK: - Private Cloud Compute

    /// Der Build hat das Entitlement `com.apple.developer.private-cloud-compute` (Info.plist-Schalter wird
    /// zusammen mit dem Entitlement gesetzt). Ohne Entitlement beendet iOS die App beim ersten Aufruf.
    static var isPrivateCloudInBuild: Bool {
        Bundle.main.object(forInfoDictionaryKey: "BNPrivateCloudCompute") as? Bool == true
    }

    static let privateCloudKey = "summaryUsesPrivateCloud"

    /// Nutzer hat Private Cloud Compute eingeschaltet (Einstellungen). Debug: `-summaryEngine pcc|device`.
    static var prefersPrivateCloud: Bool {
        guard isPrivateCloudInBuild else { return false }
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-summaryEngine"), i + 1 < args.count { return args[i + 1] == "pcc" }
        #endif
        return UserDefaults.standard.bool(forKey: privateCloudKey)
    }

    enum PrivateCloudStatus {
        case notInBuild
        case unavailable(String)
        case limitReached
        case available(approachingLimit: Bool)
    }

    static var privateCloudStatus: PrivateCloudStatus {
        guard isPrivateCloudInBuild else { return .notInBuild }
        let model = PrivateCloudComputeLanguageModel()
        switch model.availability {
        case .available: break
        case .unavailable(.deviceNotEligible): return .unavailable("Dieses Gerät unterstützt Private Cloud Compute nicht.")
        case .unavailable: return .unavailable("Private Cloud Compute ist gerade nicht bereit (Apple Intelligence eingeschaltet?).")
        }
        if model.quotaUsage.isLimitReached { return .limitReached }
        if case .belowLimit(let info) = model.quotaUsage.status { return .available(approachingLimit: info.isApproachingLimit) }
        return .available(approachingLimit: false)
    }

    /// Apples Angebot, das Tageskontingent zu erhöhen (z. B. iCloud+), falls vorhanden.
    @MainActor
    static func showLimitIncreaseOptions() {
        guard isPrivateCloudInBuild else { return }
        PrivateCloudComputeLanguageModel().quotaUsage.limitIncreaseSuggestion?.show()
    }

    // MARK: - Erzeugen

    @MainActor
    static func generate(_ template: SummaryTemplate,
                         from content: SessionContent,
                         onProgress: @escaping (Progress) -> Void) async throws -> Result {
        guard !content.segments.isEmpty || !content.slides.isEmpty else { throw SummaryError.noContent }

        var notice: String?
        if OpenAIClient.isEnabled {
            do {
                let body = try await generateWithOpenAI(template, content: content, onProgress: onProgress)
                return Result(summary: makeSummary(template, content: content, body: body, engine: .openAI), notice: nil)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                summaryLog.error("OpenAI fehlgeschlagen: \(String(describing: type(of: error)), privacy: .public) \(String(describing: error), privacy: .private)")
                #if DEBUG
                print("[Summary] OpenAI-Fehler: \(error)")
                #endif
                let fallback = prefersPrivateCloud ? "mit Apple Private Cloud Compute" : "auf dem Gerät"
                notice = (error.localizedDescription) + " Diese Fassung wurde \(fallback) erstellt."
            }
        }
        if prefersPrivateCloud {
            switch privateCloudStatus {
            case .available:
                do {
                    let body = try await generateWithModel(template, content: content, backend: .privateCloud, onProgress: onProgress)
                    return Result(summary: makeSummary(template, content: content, body: body, engine: .privateCloud), notice: notice)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    summaryLog.error("Private Cloud Compute fehlgeschlagen: \(String(describing: type(of: error)), privacy: .public) \(String(describing: error), privacy: .private)")
                    #if DEBUG
                    print("[Summary] PCC-Fehler: \(error)")
                    #endif
                    notice = notice ?? privateCloudNotice(for: error)
                }
            case .limitReached:
                notice = notice ?? "Das heutige Kontingent für Private Cloud Compute ist aufgebraucht – diese Fassung wurde auf dem Gerät erstellt."
            case .unavailable(let reason):
                notice = notice ?? reason + " Diese Fassung wurde auf dem Gerät erstellt."
            case .notInBuild:
                break
            }
        }

        if case .structuredOnly(let reason) = availability(language: content.language) {
            notice = notice ?? reason
        } else {
            do {
                let body = try await generateWithModel(template, content: content, backend: .onDevice, onProgress: onProgress)
                return Result(summary: makeSummary(template, content: content, body: body, engine: .onDevice), notice: notice)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                summaryLog.error("On-Device-Zusammenfassung fehlgeschlagen: \(String(describing: type(of: error)), privacy: .public) \(String(describing: error), privacy: .private)")
                #if DEBUG
                print("[Summary] Modellfehler: \(error)")
                #endif
                notice = "Apple Intelligence konnte diese Session gerade nicht verarbeiten. Es wurde eine strukturierte Fassung erstellt – später „Neu erstellen“ versuchen."
            }
        }
        onProgress(Progress(step: 1, total: 1, label: "Strukturierte Fassung wird erstellt …"))
        let body = StructuredSummarizer.body(for: template, content: content)
        return Result(summary: makeSummary(template, content: content, body: body, engine: .structured), notice: notice)
    }

    /// OpenAI (eigener Key): ganzes Transkript in einem Aufruf – grosses Kontextfenster, keine Verdichtung nötig.
    @MainActor
    private static func generateWithOpenAI(_ template: SummaryTemplate, content: SessionContent,
                                           onProgress: @escaping (Progress) -> Void) async throws -> String {
        onProgress(Progress(step: 1, total: 1, label: "Bericht wird mit OpenAI geschrieben …"))
        let english = content.isEnglish
        let terms = Glossary.terms
        let transcript = Glossary.correct(content.timedTranscript)
        let extras = extrasText(content, english: english, limit: 40_000)
        let prompt = """
        \(english ? "Title" : "Titel"): \(content.title)

        \(english ? "TRANSCRIPT, with timestamps" : "TRANSKRIPT, mit Zeitstempeln"):
        \(transcript.isEmpty ? "–" : transcript)
        \(extras)

        \(languageRule(english: english))
        """
        let response = try await OpenAIClient.respond(
            instructions: instructions(for: template, english: english, terms: terms), input: prompt)
        #if DEBUG
        print("[Summary] OpenAI: in \(response.inputTokens ?? 0) / out \(response.outputTokens ?? 0) Tokens")
        #endif
        return Glossary.correct(dedupe(clean(response.text)))
    }

    private static func privateCloudNotice(for error: Error) -> String {
        if let error = error as? PrivateCloudComputeLanguageModel.Error {
            switch error {
            case .networkFailure: return "Keine Verbindung zu Private Cloud Compute – diese Fassung wurde auf dem Gerät erstellt."
            case .quotaLimitReached: return "Das heutige Kontingent für Private Cloud Compute ist aufgebraucht – diese Fassung wurde auf dem Gerät erstellt."
            default: break
            }
        }
        return "Private Cloud Compute war gerade nicht erreichbar – diese Fassung wurde auf dem Gerät erstellt."
    }

    // MARK: - Kopf (immer deterministisch, nie vom Modell)

    private static func makeSummary(_ template: SummaryTemplate, content: SessionContent,
                                    body: String, engine: SessionSummary.Engine) -> SessionSummary {
        var meta = [template.title, content.createdAt.formatted(date: .long, time: .shortened)]
        if content.duration > 0 { meta.append("Dauer \(content.duration.clockString)") }
        let header = "# \(content.title)\n\n*\(meta.joined(separator: " · "))*\n\n"
        return SessionSummary(template: template, createdAt: .now, engine: engine, text: header + body)
    }

    // MARK: - Sprachmodell

    private struct Setup {
        let backend: Backend
        let contextSize: Int
        /// Für Ausgabe, Reasoning und Anweisungen freigehaltene Tokens.
        let reserve: Int
        /// Geschätzte Zeichen pro Token (lieber zu klein → Abschnitte eher kleiner).
        let charsPerToken: Double
        let notesTokens: Int

        func session(instructions: String) -> LanguageModelSession {
            switch backend {
            case .onDevice: LanguageModelSession(instructions: instructions)
            case .privateCloud: LanguageModelSession(model: PrivateCloudComputeLanguageModel(), instructions: instructions)
            }
        }

        var reasoning: ContextOptions.ReasoningLevel? {
            guard backend == .privateCloud else { return nil }
            #if DEBUG
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-pccReasoning"), i + 1 < args.count {
                switch args[i + 1] {
                case "none": return nil
                case "moderate": return .moderate
                case "deep": return .deep
                default: return .light
                }
            }
            #endif
            return .light
        }
    }

    @MainActor
    private static func generateWithModel(_ template: SummaryTemplate, content: SessionContent, backend: Backend,
                                          onProgress: @escaping (Progress) -> Void) async throws -> String {
        let setup: Setup
        switch backend {
        case .onDevice:
            setup = Setup(backend: backend, contextSize: SystemLanguageModel.default.contextSize,
                          reserve: 1600, charsPerToken: 3, notesTokens: 500)
        case .privateCloud:
            let size = (try? await PrivateCloudComputeLanguageModel().contextSize) ?? 32768
            // Notizen grosszügig: 3 Abschnitte × 4000 Tokens passen noch gut in einen Schlussaufruf.
            setup = Setup(backend: backend, contextSize: size, reserve: 9000, charsPerToken: 2.8, notesTokens: 4000)
        }
        // Bei Überlauf wird mit kleineren Abschnitten neu versucht.
        var lastError: Error?
        for factor in [1.0, 0.6, 0.35] {
            let budget = max(1500, Int(Double(setup.contextSize - setup.reserve) * setup.charsPerToken * factor))
            do {
                return try await run(template, content: content, setup: setup, budget: budget, onProgress: onProgress)
            } catch {
                guard isContextOverflow(error) else { throw error }
                summaryLog.info("Kontextfenster überschritten bei Budget \(budget) – neuer Versuch kleiner")
                lastError = error
            }
        }
        throw lastError ?? SummaryError.noContent
    }

    @MainActor
    private static func run(_ template: SummaryTemplate, content: SessionContent, setup: Setup, budget: Int,
                            onProgress: @escaping (Progress) -> Void) async throws -> String {
        let english = content.isEnglish
        let extras = extrasText(content, english: english, limit: budget / 3)
        let terms = Glossary.terms
        // Glossar auch auf ältere Transkripte und auf Begriffe anwenden, die erst nachträglich erfasst wurden.
        let transcript = Glossary.correct(content.timedTranscript)
        let available = max(800, budget - extras.count)

        var material: String
        if transcript.count <= available {
            onProgress(Progress(step: 1, total: 1, label: "Zusammenfassung wird geschrieben …"))
            material = transcript
        } else {
            // map: Abschnitte zu Stichpunkten verdichten, bis alles in einen Aufruf passt
            var parts = chunk(lines: transcript.components(separatedBy: "\n"), maxChars: budget)
            var round = 0
            repeat {
                round += 1
                var notes: [String] = []
                for (index, part) in parts.enumerated() {
                    try Task.checkCancellation()
                    onProgress(Progress(step: index + 1, total: parts.count + 1,
                                        label: round == 1 ? "Abschnitt \(index + 1) von \(parts.count) wird gelesen …"
                                                          : "Notizen werden verdichtet …"))
                    notes.append(try await condense(part, english: english, terms: terms, setup: setup))
                }
                material = dedupe(notes.joined(separator: "\n"))
                parts = chunk(lines: material.components(separatedBy: "\n"), maxChars: budget)
            } while material.count > available && round < 3
            if material.count > available { material = String(material.prefix(available)) }
            onProgress(Progress(step: parts.count + 1, total: parts.count + 1, label: "Dokument wird geschrieben …"))
        }

        try Task.checkCancellation()
        let prompt = """
        \(english ? "Title" : "Titel"): \(content.title)

        \(english ? "TRANSCRIPT (or notes from it), with timestamps" : "TRANSKRIPT (bzw. Notizen daraus), mit Zeitstempeln"):
        \(material.isEmpty ? "–" : material)
        \(extras)

        \(languageRule(english: english))
        """
        let sections = template.sections(english: english)
        var body: String
        if setup.backend == .privateCloud, sections.count >= 4, transcript.count > sectionWiseThreshold {
            // Lange Aufnahme: jeden Abschnitt einzeln schreiben – ein einzelner Aufruf kürzt sonst stark.
            var parts: [String] = []
            for (index, section) in sections.enumerated() {
                try Task.checkCancellation()
                onProgress(Progress(step: index + 1, total: sections.count,
                                    label: "Abschnitt „\(section)“ wird geschrieben …"))
                let session = setup.session(instructions: instructions(for: template, english: english, terms: terms,
                                                                       onlySection: section))
                var text = clean(try await respond(session, to: prompt, setup: setup,
                                                   options: GenerationOptions(temperature: 0.3)))
                if !text.hasPrefix("## ") { text = "## \(section)\n" + text }
                parts.append(text)
            }
            body = dedupe(parts.joined(separator: "\n\n"))
        } else {
            let session = setup.session(instructions: instructions(for: template, english: english, terms: terms))
            body = dedupe(clean(try await respond(session, to: prompt, setup: setup,
                                                  options: GenerationOptions(temperature: 0.3))))
        }
        body = Glossary.correct(body)
        if !english, setup.backend == .onDevice {
            body = try await ensureGerman(body, setup: setup)
        }
        return body
    }

    /// Ab dieser Transkriptlänge (Zeichen, ≈ 30 Min.) schreibt PCC lange Vorlagen Abschnitt für Abschnitt.
    private static let sectionWiseThreshold = 20_000

    /// Zusatzregeln, wenn ein Abschnitt einzeln geschrieben wird – sonst will jeder Abschnitt alles abdecken.
    private static func sectionRule(_ section: String, index: Int) -> String {
        switch section.lowercased() {
        case "themen", "topics":
            return "This section is only a short list of the topics: one line per topic, at most twelve words, no details or numbers."
        case "beschlüsse", "entscheidungen", "decisions":
            return "List only decisions that were explicitly made or agreed in this meeting. Plans, goals, priorities, "
                + "announcements or results that were merely presented are NOT decisions. A talk or presentation usually has none."
        case "pendenzen", "aufgaben", "action items":
            return "List only concrete tasks someone will do, as '- Task – owner – due date'. Use names only if they are in the material."
        case "offene fragen", "open questions":
            return "List only questions that were explicitly raised and left unanswered."
        default:
            return ""
        }
    }

    private static func languageRule(english: Bool) -> String {
        english ? "The output must be in English."
                : "The output must be in German, even where the transcript is in English."
    }

    /// Modellaufruf mit Wiederholung, wenn das System drosselt (viele Aufrufe bei langen Aufnahmen,
    /// oder App kurz im Hintergrund). Wartet 3 / 8 / 20 s.
    private static func respond(_ session: LanguageModelSession, to prompt: String, setup: Setup,
                                options: GenerationOptions) async throws -> String {
        var delays: [UInt64] = [3, 8, 20]
        while true {
            do {
                if let reasoning = setup.reasoning {
                    return try await session.respond(to: prompt, options: options,
                                                     contextOptions: ContextOptions(reasoningLevel: reasoning)).content
                }
                return try await session.respond(to: prompt, options: options).content
            } catch {
                // PCC: kurze Aussetzer (Netz, Serverfehler, leere Antwort) einmal bzw. zweimal neu versuchen,
                // statt gleich den ganzen Bericht auf dem Gerät neu zu schreiben.
                let retryable = isRateLimited(error)
                    || (setup.backend == .privateCloud && !(error is CancellationError) && !isContextOverflow(error)
                        && !isQuotaReached(error))
                guard retryable, !delays.isEmpty else { throw error }
                let delay = delays.removeFirst()
                summaryLog.info("Modellfehler (\(String(describing: error).prefix(120))) – neuer Versuch in \(delay) s")
                #if DEBUG
                print("[Summary] Wiederholung in \(delay) s nach: \(String(describing: error).prefix(160))")
                #endif
                try await Task.sleep(for: .seconds(delay))
            }
        }
    }

    private static func isQuotaReached(_ error: Error) -> Bool {
        if let error = error as? PrivateCloudComputeLanguageModel.Error, case .quotaLimitReached = error { return true }
        return String(describing: error).contains("quotaLimitReached")
    }

    private static func isRateLimited(_ error: Error) -> Bool {
        if #available(iOS 27.0, macOS 27.0, *), let error = error as? LanguageModelError, case .rateLimited = error { return true }
        let text = String(describing: error)
        return text.contains("rateLimited") || text.contains("rate limited")
    }

    /// Kontextfenster zu klein – iOS 27 meldet `LanguageModelError`, ältere Pfade noch `GenerationError`.
    private static func isContextOverflow(_ error: Error) -> Bool {
        if #available(iOS 27.0, macOS 27.0, *), let error = error as? LanguageModelError, case .contextSizeExceeded = error { return true }
        let text = String(describing: error)
        return text.contains("exceededContextWindowSize") || text.contains("contextSizeExceeded")
    }

    /// Ein Abschnitt → kompakte Stichpunkte mit Zeitstempeln.
    private static func condense(_ part: String, english: Bool, terms: [String], setup: Setup) async throws -> String {
        let session = setup.session(instructions: """
        \(languageRule(english: english))
        You condense one part of a meeting or talk transcript into compact notes.
        Output only bullet points starting with '- [mm:ss]' (timestamp of the source line).
        Keep: key statements, facts and numbers, names, decisions, tasks with owner and deadline, open questions.
        Drop filler and repetitions. Never invent anything.
        \(glossaryRule(terms))
        """)
        return clean(try await respond(session, to: part, setup: setup,
                                       options: GenerationOptions(temperature: 0.2, maximumResponseTokens: setup.notesTokens)))
    }

    private static func glossaryRule(_ terms: [String]) -> String {
        guard !terms.isEmpty else { return "" }
        return "Speech recognition often mishears these names and terms – write them exactly like this: "
            + terms.prefix(80).joined(separator: ", ") + "."
    }

    private static func instructions(for template: SummaryTemplate, english: Bool, terms: [String],
                                     onlySection: String? = nil) -> String {
        let all = template.sections(english: english)
        let layout: String
        if let onlySection {
            let others = all.filter { $0 != onlySection }.map { "'\($0)'" }.joined(separator: ", ")
            layout = """
            Output Markdown. Write ONLY the section '## \(onlySection)' of this document, starting with exactly that heading.
            The other sections (\(others)) are written separately – leave their content out.
            Be thorough within the scope of this section only, with concrete names, numbers and dates. Content that
            belongs in another section must not appear here. If nothing clearly belongs here, write only '–'.
            \(sectionRule(onlySection, index: all.firstIndex(of: onlySection) ?? 0))
            """
        } else {
            layout = "Output Markdown. Use exactly these section headings, in this order:\n"
                + all.map { "## \($0)" }.joined(separator: "\n")
        }
        return """
        \(languageRule(english: english))
        You turn the material of a meeting, talk or lecture into a document that follows a fixed template.
        \(template.guidance)
        \(layout)
        Under each heading write bullet points starting with '- ' or short paragraphs. Never start a bullet with '–'.
        Every point appears only once in the whole document – never repeat a point in other words.
        If the material contains nothing for a section, write only '–' under that heading. This is normal: a talk or
        presentation usually has no decisions or tasks.
        A decision must be explicitly stated as decided or agreed. A task must be explicitly stated as something a
        person will do. Never turn statements, past events or ideas into decisions or tasks.
        Use only facts from the material. Never invent names, numbers, dates, owners or deadlines.
        The transcript is automatic speech recognition and may contain misheard words – do not repeat obvious nonsense.
        \(glossaryRule(terms))
        Lines marked as starred are moments the user flagged as important – give them weight.
        Slide texts come from photos the user took – use them to get names and terms right.
        Do not add a title, an introduction or closing remarks.
        """
    }

    /// Kleines Modell schreibt bei englischem Material trotz Anweisung oft Englisch – dann Absatz für Absatz übersetzen.
    private static func ensureGerman(_ body: String, setup: Setup) async throws -> String {
        guard dominantLanguage(body) == .english else { return body }
        summaryLog.info("Ausgabe englisch statt deutsch – wird übersetzt")
        var result: [String] = []
        var block: [String] = []
        func flush() async throws {
            guard !block.isEmpty else { return }
            let text = block.joined(separator: "\n")
            block = []
            guard dominantLanguage(text) == .english else { result.append(text); return }
            let session = setup.session(instructions: """
            Translate the Markdown text into German. Keep the Markdown structure, bullet points, names, numbers and
            timestamps exactly. Output only the translation.
            """)
            result.append(clean(try await respond(session, to: text, setup: setup, options: GenerationOptions(temperature: 0.1))))
        }
        for line in body.components(separatedBy: "\n") {
            if line.hasPrefix("## ") {
                try await flush()
                result.append(line)
            } else {
                block.append(line)
            }
        }
        try await flush()
        return result.joined(separator: "\n")
    }

    private static func dominantLanguage(_ text: String) -> NLLanguage? {
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [.german, .english]
        recognizer.processString(text)
        return recognizer.dominantLanguage
    }

    /// ⭐-Marker und Folientexte als Zusatzmaterial.
    private static func extrasText(_ content: SessionContent, english: Bool, limit: Int) -> String {
        var text = ""
        if !content.markers.isEmpty {
            text += "\n\n" + (english ? "STARRED MOMENTS:" : "MARKIERTE MOMENTE (⭐):") + "\n"
            text += content.markers.map { "- [\($0.time.clockString)] \($0.snippet.suffix(240))" }.joined(separator: "\n")
        }
        let slides = content.slides.filter { !($0.recognizedText ?? "").isEmpty }
        if !slides.isEmpty {
            text += "\n\n" + (english ? "SLIDE TEXTS (OCR):" : "FOLIENTEXTE (OCR):") + "\n"
            text += slides.enumerated().map { index, slide in
                let time = slide.time.map { " [\($0.clockString)]" } ?? ""
                let body = (slide.recognizedText ?? "").replacingOccurrences(of: "\n", with: " / ").prefix(300)
                return "- \(english ? "Slide" : "Folie") \(index + 1)\(time): \(body)"
            }.joined(separator: "\n")
        }
        return text.count > limit ? String(text.prefix(limit)) : text
    }

    private static func chunk(lines: [String], maxChars: Int) -> [String] {
        var chunks: [String] = []
        var current = ""
        for line in lines where !line.isEmpty {
            if !current.isEmpty && current.count + line.count + 1 > maxChars {
                chunks.append(current)
                current = ""
            }
            current += (current.isEmpty ? "" : "\n") + String(line.prefix(maxChars))
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    // MARK: - Nachbearbeitung

    /// Entfernt Aufzählungspunkte, die (fast) wörtlich schon weiter oben stehen – kleine Modelle wiederholen sich.
    static func dedupe(_ text: String) -> String {
        var seen: [Set<String>] = []
        var lines: [String] = []
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("- ") else { lines.append(line); continue }
            let words = wordSet(trimmed)
            guard words.count >= 3 else { lines.append(line); continue }
            if seen.contains(where: { similarity($0, words) >= 0.7 }) { continue }
            seen.append(words)
            lines.append(line)
        }
        // Abschnitte, die dadurch leer wurden → „–“
        return clean(lines.joined(separator: "\n"))
    }

    private static func wordSet(_ line: String) -> Set<String> {
        let body = line.replacingOccurrences(of: #"\[\d{1,2}:\d{2}(:\d{2})?\]"#, with: "", options: .regularExpression)
        return Set(body.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 })
    }

    /// Jaccard-Ähnlichkeit der Wortmengen.
    private static func similarity(_ a: Set<String>, _ b: Set<String>) -> Double {
        let union = a.union(b).count
        guard union > 0 else { return 0 }
        return Double(a.intersection(b).count) / Double(union)
    }

    /// Räumt die Modellausgabe auf: Code-Fences, Titel, doppelte/leere Aufzählungszeichen,
    /// leere Abschnitte → „–“.
    static func clean(_ text: String) -> String {
        var lines: [String] = []
        for raw in text.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n") {
            var line = raw.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") { continue }
            if lines.isEmpty && trimmed.hasPrefix("# ") { continue }
            // „- - Text“, „- – Text“, „– Text“, „• Text“ → „- Text“
            let indent = String(line.prefix { $0 == " " })
            var body = trimmed
            var isBullet = false
            while let first = body.first, "-–•*".contains(first), body.dropFirst().first == " " {
                body = String(body.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                isBullet = true
            }
            if isBullet {
                // Leere Punkte („- –“, „- -“) weglassen
                if body.isEmpty || body == "–" || body == "-" { continue }
                line = indent + "- " + body
            }
            lines.append(line)
        }
        // Überschrift ohne Inhalt bis zur nächsten Überschrift → „–“ ergänzen
        var result: [String] = []
        for (index, line) in lines.enumerated() {
            result.append(line)
            guard line.hasPrefix("## ") else { continue }
            let rest = lines[(index + 1)...].prefix { !$0.hasPrefix("## ") }
            if rest.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) { result.append("–") }
        }
        return result.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
