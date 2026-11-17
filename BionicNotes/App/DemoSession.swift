#if DEBUG
import FoundationModels
import SwiftData
import UIKit

/// Nur Debug: `-seedDemo` legt eine Beispiel-Session an (Transkript, Marker, Folie) –
/// zum Testen von Zusammenfassung/Export im Simulator und für Screenshots.
/// `-exportSelfTest` erzeugt zusätzlich alle Vorlagen (strukturiert) und alle Exportformate
/// in Documents/ExportSelfTest.
@MainActor
enum DemoSession {
    static var shouldOpenDemo: Bool { ProcessInfo.processInfo.arguments.contains("-openDemo") }
    static var openSheet: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-openSheet"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    /// `-summaryAllSelfTest [vorlage,vorlage]`: alle Sessions × Vorlagen durchrechnen. Schreibt nur nach
    /// Documents/SummarySelfTest – die Sessions selbst bleiben unverändert.
    static func runAllSummariesIfRequested(context: ModelContext) {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-summaryAllSelfTest") else { return }
        var templates = SummaryTemplate.allCases
        if i + 1 < args.count, !args[i + 1].hasPrefix("-") {
            let wanted = Set(args[i + 1].split(separator: ",").map(String.init))
            templates = templates.filter { wanted.contains($0.rawValue) }
        }
        let sessions = (try? context.fetch(FetchDescriptor<NoteSession>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        var contents = sessions.map { SessionContent.load($0) }
        // `-useWhisperSelfTest`: statt des Session-Transkripts die Whisper-Fassung aus RetranscribeSelfTest
        // verwenden (gleiche Nummerierung wie dort) und nur Sessions ab 30 Min. rechnen.
        if args.contains("-useWhisperSelfTest") {
            let root = URL.documentsDirectory.appending(path: "RetranscribeSelfTest", directoryHint: .isDirectory)
            let audioIDs = sessions.filter(\.hasAudio).map(\.id)
            contents = zip(sessions, contents).compactMap { session, content in
                guard content.duration >= 1800, let n = audioIDs.firstIndex(of: session.id),
                      let data = try? Data(contentsOf: root.appending(path: "\(n + 1).json")),
                      let file = try? JSONDecoder().decode(TranscriptFile.self, from: data) else { return nil }
                var content = content
                content.segments = file.segments
                return content
            }
        }
        Task { await runAll(contents, templates: templates) }
    }

    /// `-pccProbe`: prüft, ob Apple Private Cloud Compute in diesem Build nutzbar ist (Entitlement, Kontingent).
    static func runPCCProbeIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-pccProbe") else { return }
        Task {
            let log = { (s: String) in print("[PCCProbe] \(s)"); fflush(stdout) }
            log("start")
            let model = PrivateCloudComputeLanguageModel()
            log("availability: \(model.availability) · quota: \(model.quotaUsage.status)")
            do {
                log("contextSize: \(try await model.contextSize)")
                log("supports de: \(try await model.supportsLocale(Locale(identifier: "de-DE")))")
                let session = LanguageModelSession(model: model, instructions: "The output must be in German.")
                let start = Date.now
                let answer = try await session.respond(to: "Say hello in one short sentence.")
                log("antwort nach \(Int(Date.now.timeIntervalSince(start))) s: \(answer.content)")
            } catch { log("FEHLER \(error)") }
            log("FERTIG")
        }
    }

    /// `-retranscribeAllSelfTest`: alle Sessions mit Audio per Whisper neu transkribieren und die Dauer messen.
    /// Schreibt nur nach Documents/RetranscribeSelfTest – die Sessions bleiben unverändert.
    static func runRetranscribeAllIfRequested(context: ModelContext) {
        guard ProcessInfo.processInfo.arguments.contains("-retranscribeAllSelfTest") else { return }
        let sessions = ((try? context.fetch(FetchDescriptor<NoteSession>(sortBy: [SortDescriptor(\.createdAt)]))) ?? [])
            .filter(\.hasAudio)
        let items = sessions.map { ($0.title, $0.audioURL, String($0.language.prefix(2)), $0.duration) }
        Task {
            let log = { (s: String) in print("[WhisperTest] \(s)"); fflush(stdout) }
            UIApplication.shared.isIdleTimerDisabled = true   // sonst sperrt das Gerät und iOS hält den Test an
            defer { UIApplication.shared.isIdleTimerDisabled = false }
            let root = URL.documentsDirectory.appending(path: "RetranscribeSelfTest", directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            do {
                let t0 = Date.now
                if !WhisperModel.shared.isInstalled { try await WhisperModel.shared.install() }
                try await WhisperEngine.shared.load()
                log("Modell bereit nach \(Int(Date.now.timeIntervalSince(t0))) s")
            } catch { log("Modell FEHLER \(error)"); return }
            for (n, item) in items.enumerated() where item.3 >= 5 {
                // Bereits erledigte Aufnahmen überspringen (Test kann nach Abbruch fortgesetzt werden)
                if FileManager.default.fileExists(atPath: root.appending(path: "\(n + 1).json").path) { continue }
                let start = Date.now
                do {
                    let segments = Glossary.correct(try await ChunkedWhisper.transcribe(audioURL: item.1, language: nil) { _ in })
                    let secs = Date.now.timeIntervalSince(start)
                    try JSONEncoder().encode(TranscriptFile(locale: item.2, segments: segments, engine: "whisper"))
                        .write(to: root.appending(path: "\(n + 1).json"))
                    log("\(item.0) · \(item.3.clockString) → \(segments.count) Segmente in \(Int(secs)) s (\(String(format: "%.1f", item.3 / max(secs, 1)))× Echtzeit)")
                } catch { log("\(item.0): FEHLER \(error)") }
            }
            await WhisperEngine.shared.unload()
            log("FERTIG")
        }
    }

    private static func runAll(_ contents: [SessionContent], templates: [SummaryTemplate]) async {
        let log = { (s: String) in print("[AllTest] \(s)"); fflush(stdout) }
        UIApplication.shared.isIdleTimerDisabled = true   // sonst sperrt das Gerät und iOS beendet den Test
        defer { UIApplication.shared.isIdleTimerDisabled = false }
        // `-summaryOut <Ordner>`: eigener Ausgabeordner, z. B. um Gerät und Private Cloud Compute zu vergleichen
        let args = ProcessInfo.processInfo.arguments
        let outName = args.firstIndex(of: "-summaryOut").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } ?? "SummarySelfTest"
        let root = URL.documentsDirectory.appending(path: outName, directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        log("Modell: \(SummaryGenerator.availability(language: "de-DE")) · Kontext \(SystemLanguageModel.default.contextSize) Tokens · PCC gewünscht: \(SummaryGenerator.prefersPrivateCloud)")
        log("\(contents.count) Sessions × \(templates.count) Vorlagen")
        var report = "session\ttemplate\tengine\tseconds\tchars\tnotice\n"
        for (n, content) in contents.enumerated() {
            let words = content.transcriptText.split(separator: " ").count
            log("=== [\(n + 1)/\(contents.count)] \(content.title) · \(content.language) · \(content.duration.clockString) · \(content.segments.count) Segmente · \(words) Wörter · \(content.markers.count) Marker · \(content.slides.count) Folien")
            guard !content.segments.isEmpty || !content.slides.isEmpty else { log("übersprungen (kein Inhalt)"); continue }
            let folder = root.appending(path: "\(n + 1)-" + SessionExporter.fileName(content.title), directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for template in templates {
                let start = Date.now
                var steps = 0
                do {
                    let result = try await SummaryGenerator.generate(template, from: content) { _ in steps += 1 }
                    let seconds = Int(Date.now.timeIntervalSince(start))
                    let text = result.summary.text
                    try? text.write(to: folder.appending(path: "\(template.rawValue).md"), atomically: true, encoding: .utf8)
                    let headings = text.components(separatedBy: "\n").filter { $0.hasPrefix("## ") }.count
                    log("\(template.rawValue): \(result.summary.engine) · \(seconds) s · \(text.count) Zeichen · \(headings) Abschnitte · \(steps) Schritte\(result.notice.map { " · HINWEIS: \($0)" } ?? "")")
                    report += "\(content.title)\t\(template.rawValue)\t\(result.summary.engine)\t\(seconds)\t\(text.count)\t\(result.notice ?? "")\n"
                } catch {
                    log("\(template.rawValue): FEHLER \(error)")
                    report += "\(content.title)\t\(template.rawValue)\tERROR\t\t\t\(error)\n"
                }
            }
        }
        try? report.write(to: root.appending(path: "report.tsv"), atomically: true, encoding: .utf8)
        log("FERTIG")
    }

    @discardableResult
    static func seedIfRequested(context: ModelContext) -> NoteSession? {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-seedDemo") || args.contains("-exportSelfTest") || args.contains("-summarySelfTest") else { return nil }
        let existing = (try? context.fetch(FetchDescriptor<NoteSession>())) ?? []
        let session = existing.first { $0.title == demoTitle } ?? makeSession(context: context)
        // `-demoAudio <Pfad>`: echte Aufnahme in die Demo-Session kopieren (Simulator kann Mac-Pfade lesen)
        if let i = args.firstIndex(of: "-demoAudio"), i + 1 < args.count, !FileManager.default.fileExists(atPath: session.audioURL.path) {
            try? FileManager.default.copyItem(at: URL(fileURLWithPath: args[i + 1]), to: session.audioURL)
            session.hasAudio = true
        }
        if args.contains("-exportSelfTest") {
            Task { await runExportSelfTest(session) }
        }
        if args.contains("-summarySelfTest") {
            Task { await runSummarySelfTest(session) }
        }
        return session
    }

    private static let demoTitle = "Projekt-Kickoff Kundenportal"

    private static func makeSession(context: ModelContext) -> NoteSession {
        let session = NoteSession(title: demoTitle)
        session.language = "de-DE"
        session.duration = 1_380
        context.insert(session)

        let lines = [
            "Guten Morgen zusammen, schön dass ihr alle da seid.",
            "Heute geht es um den Kickoff für das neue Kundenportal der Firma Muster AG.",
            "Ziel ist, dass Kunden ihre Rechnungen und Verträge selbst online verwalten können.",
            "Anna stellt zuerst die Ergebnisse der Umfrage vor.",
            "Wir haben 420 Kunden befragt, und 68 Prozent wünschen sich eine mobile App.",
            "Am häufigsten genannt wurde der Wunsch, Rechnungen als PDF herunterzuladen.",
            "Sollen wir mit der Web-Version oder direkt mit der App starten?",
            "Wir haben entschieden, zuerst die Web-Version zu bauen und die App im zweiten Schritt.",
            "Das Budget für Phase eins liegt bei 180'000 Franken.",
            "Marco kümmert sich bis Ende Monat um das Konzept für das Login mit Zwei-Faktor-Authentifizierung.",
            "Lisa schickt bis Freitag die Offerte an den Kunden.",
            "Wie gehen wir mit dem Datenschutz bei den hochgeladenen Dokumenten um?",
            "Alle Dokumente bleiben in der Schweiz gespeichert, das ist eine klare Anforderung des Kunden.",
            "Wir haben uns geeinigt, dass die erste Version im März live gehen soll.",
            "Nächster Schritt ist ein Workshop mit der IT des Kunden in zwei Wochen.",
            "Vielen Dank, dann schliessen wir für heute.",
        ]
        let segments = lines.enumerated().map { index, text in
            TranscriptSegment(start: Double(index) * 85 + 3, end: Double(index) * 85 + 12, text: text)
        }
        try? JSONEncoder().encode(TranscriptFile(locale: "de-DE", segments: segments)).write(to: session.transcriptURL)
        session.hasAudio = false

        let markers = [
            SessionMarker(time: 598, snippet: "Wir haben entschieden, zuerst die Web-Version zu bauen und die App im zweiten Schritt.", source: .phone),
            SessionMarker(time: 1_108, snippet: "Alle Dokumente bleiben in der Schweiz gespeichert.", source: .watch),
        ]
        try? JSONEncoder().encode(markers).write(to: session.markersURL)

        // Eine „Folie“ als Bild + OCR-Text
        let slide = UIGraphicsImageRenderer(size: CGSize(width: 1600, height: 900)).image { ctx in
            UIColor(red: 0.1, green: 0.12, blue: 0.32, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1600, height: 900))
            let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 90), .foregroundColor: UIColor.white]
            ("Umfrage: 68 % wollen eine App" as NSString).draw(at: CGPoint(x: 100, y: 380), withAttributes: attrs)
        }
        let photosFolder = session.folderURL.appending(path: "photos", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: photosFolder, withIntermediateDirectories: true)
        let photo = SessionPhoto(time: 340, kind: .slide, fileName: "demo-slide.jpg",
                                 recognizedText: "Umfrage Kundenportal\n420 Befragte\n68 % wollen eine App")
        try? slide.jpegData(compressionQuality: 0.8)?.write(to: photosFolder.appending(path: photo.fileName))
        try? JSONEncoder().encode([photo]).write(to: session.folderURL.appending(path: "photos.json"))
        return session
    }

    private static func runSummarySelfTest(_ session: NoteSession) async {
        do {
            let probe = try await LanguageModelSession(instructions: "Answer briefly.").respond(to: "Say hello in German.")
            print("[SummarySelfTest] probe OK: \(probe.content)")
        } catch {
            print("[SummarySelfTest] probe FAILED: \(error)")
        }
        let content = SessionContent.load(session)
        for template in [SummaryTemplate.meetingMinutes, .executiveSummary, .slideDeck] {
            let start = Date.now
            do {
                let result = try await SummaryGenerator.generate(template, from: content) { print("[SummarySelfTest] … \($0.label)") }
                print("[SummarySelfTest] \(template.rawValue) engine=\(result.summary.engine) notice=\(result.notice ?? "-") \(Int(Date.now.timeIntervalSince(start))) s\n\(result.summary.text)\n[SummarySelfTest] ---")
            } catch {
                print("[SummarySelfTest] FAILED \(template.rawValue): \(error)")
            }
        }
        print("[SummarySelfTest] done")
    }

    private static func runExportSelfTest(_ session: NoteSession) async {
        let out = URL.documentsDirectory.appending(path: "ExportSelfTest", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: out)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        var content = SessionContent.load(session)
        print("[ExportSelfTest] Verfügbarkeit: \(SummaryGenerator.availability(language: content.language))")
        for template in SummaryTemplate.allCases {
            let body = StructuredSummarizer.body(for: template, content: content)
            content.summaries.append(SessionSummary(template: template, createdAt: .now, engine: .structured, text: "# \(content.title)\n\n*\(template.title)*\n\n" + body))
            try? body.write(to: out.appending(path: "summary-\(template.rawValue).md"), atomically: true, encoding: .utf8)
        }
        var options = ExportOptions()
        options.summaryID = content.summaries.first?.id
        for format in ExportFormat.allCases {
            do {
                let url = try await SessionExporter.export(content, format: format, options: options)
                try FileManager.default.copyItem(at: url, to: out.appending(path: "export.\(format.fileExtension)"))
                print("[ExportSelfTest] OK \(format.rawValue)")
            } catch {
                print("[ExportSelfTest] FAILED \(format.rawValue): \(error.localizedDescription)")
            }
        }
        print("[ExportSelfTest] done → \(out.path)")
    }
}
#endif
