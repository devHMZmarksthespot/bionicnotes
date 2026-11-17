import Foundation
import PencilKit
import UIKit

enum ExportFormat: String, CaseIterable, Identifiable {
    case pdf, rtf, markdown, text, srt, audio, package

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pdf: "PDF"
        case .rtf: "Word / Pages (RTF)"
        case .markdown: "Markdown"
        case .text: "Text"
        case .srt: "Untertitel (SRT)"
        case .audio: "Audio (M4A)"
        case .package: "Session-Paket (ZIP)"
        }
    }

    var detail: String {
        switch self {
        case .pdf: "Dokument mit Notizen und Fotos – zum Teilen und Drucken"
        case .rtf: "Bearbeitbarer Text für Word, Pages, Google Docs (ohne Bilder)"
        case .markdown: "Für Obsidian, Notion, Bear & Co."
        case .text: "Reiner Text"
        case .srt: "Transkript mit Zeitstempeln für Video-Player"
        case .audio: "Die Originalaufnahme"
        case .package: "Alles in einem Archiv – zum Archivieren und Weiterbearbeiten am Mac"
        }
    }

    var symbol: String {
        switch self {
        case .pdf: "doc.richtext"
        case .rtf: "doc.text"
        case .markdown: "number"
        case .text: "text.alignleft"
        case .srt: "captions.bubble"
        case .audio: "waveform"
        case .package: "archivebox"
        }
    }

    var fileExtension: String {
        switch self {
        case .pdf: "pdf"
        case .rtf: "rtf"
        case .markdown: "md"
        case .text: "txt"
        case .srt: "srt"
        case .audio: "m4a"
        case .package: "zip"
        }
    }

    /// Ob die Inhalts-Auswahl (Zusammenfassung, Transkript …) für dieses Format eine Rolle spielt.
    var usesOptions: Bool { [.pdf, .rtf, .markdown, .text].contains(self) }
    var supportsImages: Bool { self == .pdf }
}

struct ExportOptions: Equatable {
    var summaryID: UUID?
    var includeMarkers = true
    var includeNotes = true
    var includePhotos = true
    var includeTranscript = true
}

enum ExportError: LocalizedError {
    case noAudio
    case nothingToExport
    case packageFailed

    var errorDescription: String? {
        switch self {
        case .noAudio: "Diese Session hat keine Audioaufnahme."
        case .nothingToExport: "Für diese Auswahl gibt es keinen Inhalt."
        case .packageFailed: "Das Session-Paket konnte nicht erstellt werden."
        }
    }
}

/// Erstellt Exportdateien in einem temporären Ordner. Die Datei verlässt das Gerät nur,
/// wenn der Kunde sie danach aktiv teilt oder in „Dateien“ sichert.
@MainActor
enum SessionExporter {
    static func export(_ content: SessionContent, format: ExportFormat, options: ExportOptions) async throws -> URL {
        let folder = URL.temporaryDirectory.appending(path: "Export/\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: fileName(content.title) + "." + format.fileExtension)

        switch format {
        case .pdf:
            try PDFDocumentRenderer.render(document(content, options: options, images: true), title: content.title).write(to: url)
        case .rtf:
            let attributed = AttributedDocument.make(document(content, options: options, images: false))
            let data = try attributed.data(from: NSRange(location: 0, length: attributed.length),
                                           documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
            try data.write(to: url)
        case .markdown:
            try markdown(document(content, options: options, images: false)).write(to: url, atomically: true, encoding: .utf8)
        case .text:
            try plainText(document(content, options: options, images: false)).write(to: url, atomically: true, encoding: .utf8)
        case .srt:
            guard !content.segments.isEmpty else { throw ExportError.nothingToExport }
            try srt(content.segments).write(to: url, atomically: true, encoding: .utf8)
        case .audio:
            guard content.hasAudio, FileManager.default.fileExists(atPath: content.audioURL.path) else { throw ExportError.noAudio }
            try FileManager.default.copyItem(at: content.audioURL, to: url)
        case .package:
            try await package(content, to: url, staging: folder)
        }
        return url
    }

    static func fileName(_ title: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.newlines)
        let cleaned = title.components(separatedBy: invalid).joined(separator: "-").trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "BionicNotes" : String(cleaned.prefix(80))
    }

    // MARK: - Dokumentaufbau

    enum Block {
        case title(String)
        case meta(String)
        case heading(String, level: Int)
        case paragraph(String)
        case bullet(String, indent: Int)
        case quote(String)
        case timed(TimeInterval, String)
        case image(UIImage, caption: String?)
    }

    static func document(_ content: SessionContent, options: ExportOptions, images: Bool) -> [Block] {
        var blocks: [Block] = []
        let summary = options.summaryID.flatMap { id in content.summaries.first { $0.id == id } }

        if let summary {
            // Die Zusammenfassung bringt Titel und Kopfzeile selbst mit.
            for block in MarkdownBlock.parse(summary.text) {
                switch block {
                case .heading(let level, let text):
                    blocks.append(level == 1 && blocks.isEmpty ? .title(text) : .heading(text, level: level))
                case .bullet(let text, let indent): blocks.append(.bullet(text, indent: indent))
                case .quote(let text): blocks.append(.quote(text))
                case .paragraph(let text):
                    if blocks.count == 1, case .title = blocks[0], text.hasPrefix("*") { blocks.append(.meta(text)) }
                    else { blocks.append(.paragraph(text)) }
                }
            }
        } else {
            blocks.append(.title(content.title))
            var meta = [content.createdAt.formatted(date: .long, time: .shortened)]
            if content.duration > 0 { meta.append("Dauer \(content.duration.clockString)") }
            blocks.append(.meta(meta.joined(separator: " · ")))
        }

        if options.includeMarkers, !content.markers.isEmpty {
            blocks.append(.heading("⭐ Markierte Momente", level: 2))
            blocks += content.markers.map { .timed($0.time, $0.snippet.isEmpty ? "Marker" : String($0.snippet.suffix(300))) }
        }

        if options.includeNotes, let pages = notesImages(content), !pages.isEmpty {
            blocks.append(.heading("Handnotizen", level: 2))
            if images {
                blocks += pages.map { .image($0, caption: nil) }
            } else {
                blocks.append(.paragraph("\(pages.count) Seite(n) Handnotizen – im PDF-Export enthalten."))
            }
        }

        if options.includePhotos, !content.photos.isEmpty {
            blocks.append(.heading("Fotos & Folien", level: 2))
            for photo in content.photos {
                let label = (photo.kind == .slide ? "Folie" : "Foto") + (photo.time.map { " bei \($0.clockString)" } ?? "")
                if images, let image = UIImage(contentsOfFile: content.photoURL(photo).path) {
                    blocks.append(.image(image, caption: label))
                } else {
                    blocks.append(.heading(label, level: 3))
                }
                if let text = photo.recognizedText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                    blocks.append(.quote(text.replacingOccurrences(of: "\n", with: " · ")))
                }
            }
        }

        if options.includeTranscript, !content.segments.isEmpty {
            blocks.append(.heading("Transkript", level: 2))
            blocks += content.segments.map { .timed($0.start, $0.text) }
        }
        return blocks
    }

    /// Handnotizen als Seitenbilder (heller Hintergrund, unabhängig vom Dark Mode).
    static func notesImages(_ content: SessionContent) -> [UIImage]? {
        guard let data = try? Data(contentsOf: content.drawingURL),
              let drawing = try? PKDrawing(data: data), !drawing.strokes.isEmpty else { return nil }
        let bounds = drawing.bounds
        let rect = CGRect(x: min(0, bounds.minX), y: min(0, bounds.minY),
                          width: max(bounds.maxX, 300) - min(0, bounds.minX) + 20,
                          height: bounds.maxY - min(0, bounds.minY) + 20)
        let sliceHeight = rect.width * 1.3
        var images: [UIImage] = []
        var y = rect.minY
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            while y < rect.maxY {
                let slice = CGRect(x: rect.minX, y: y, width: rect.width, height: min(sliceHeight, rect.maxY - y))
                y += sliceHeight
                guard drawing.strokes.contains(where: { $0.renderBounds.intersects(slice) }) else { continue }
                let ink = drawing.image(from: slice, scale: 2)
                let format = UIGraphicsImageRendererFormat()
                format.scale = 2
                let page = UIGraphicsImageRenderer(size: slice.size, format: format).image { context in
                    UIColor.white.setFill()
                    context.fill(CGRect(origin: .zero, size: slice.size))
                    ink.draw(in: CGRect(origin: .zero, size: slice.size))
                }
                images.append(page)
            }
        }
        return images
    }

    // MARK: - Text-Formate

    static func markdown(_ blocks: [Block]) -> String {
        var out: [String] = []
        for block in blocks {
            switch block {
            case .title(let text): out.append("# \(text)\n")
            case .meta(let text): out.append("\(text)\n")
            case .heading(let text, let level): out.append("\n" + String(repeating: "#", count: min(level, 4)) + " \(text)\n")
            case .paragraph(let text): out.append("\(text)\n")
            case .bullet(let text, let indent):
                out.append(String(repeating: "  ", count: indent) + "- " + text.replacingOccurrences(of: "\n", with: "\n  "))
            case .quote(let text): out.append("> \(text)\n")
            case .timed(let time, let text): out.append("- **\(time.clockString)** \(text)")
            case .image(_, let caption): out.append("*[Bild\(caption.map { ": \($0)" } ?? "")]*\n")
            }
        }
        return out.joined(separator: "\n") + "\n"
    }

    static func plainText(_ blocks: [Block]) -> String {
        var out: [String] = []
        for block in blocks {
            switch block {
            case .title(let text): out.append(MarkdownBlock.plain(text).uppercased() + "\n")
            case .meta(let text): out.append(MarkdownBlock.plain(text) + "\n")
            case .heading(let text, _): out.append("\n" + MarkdownBlock.plain(text) + "\n")
            case .paragraph(let text): out.append(MarkdownBlock.plain(text) + "\n")
            case .bullet(let text, let indent): out.append(String(repeating: "  ", count: indent) + "• " + MarkdownBlock.plain(text))
            case .quote(let text): out.append("  » " + MarkdownBlock.plain(text))
            case .timed(let time, let text): out.append("[\(time.clockString)] \(text)")
            case .image(_, let caption): out.append("[Bild\(caption.map { ": \($0)" } ?? "")]")
            }
        }
        return out.joined(separator: "\n") + "\n"
    }

    static func srt(_ segments: [TranscriptSegment]) -> String {
        func stamp(_ t: TimeInterval) -> String {
            let ms = Int((t * 1000).rounded())
            return String(format: "%02d:%02d:%02d,%03d", ms / 3_600_000, (ms / 60_000) % 60, (ms / 1000) % 60, ms % 1000)
        }
        return segments.enumerated().map { index, segment in
            "\(index + 1)\n\(stamp(segment.start)) --> \(stamp(max(segment.end, segment.start + 1)))\n\(segment.text)\n"
        }.joined(separator: "\n")
    }

    // MARK: - Session-Paket

    /// Rohdaten der Session + lesbare Dateien, als ZIP (über NSFileCoordinator, ohne Fremdbibliothek).
    private static func package(_ content: SessionContent, to url: URL, staging: URL) async throws {
        let fm = FileManager.default
        let root = staging.appending(path: fileName(content.title), directoryHint: .isDirectory)
        try fm.copyItem(at: content.folderURL, to: root)

        var all = ExportOptions()
        all.summaryID = nil
        try markdown(document(content, options: all, images: false))
            .write(to: root.appending(path: "Session.md"), atomically: true, encoding: .utf8)
        for summary in content.summaries {
            try summary.text.write(to: root.appending(path: fileName(summary.template.title) + ".md"),
                                   atomically: true, encoding: .utf8)
        }
        if !content.segments.isEmpty {
            try srt(content.segments).write(to: root.appending(path: "Transkript.srt"), atomically: true, encoding: .utf8)
        }
        let info: [String: Any] = [
            "format": "BionicNotes Session 1",
            "title": content.title,
            "createdAt": ISO8601DateFormatter().string(from: content.createdAt),
            "duration": content.duration,
            "language": content.language,
        ]
        try JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys])
            .write(to: root.appending(path: "session.json"))

        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: root, options: .forUploading, error: &coordinationError) { zipURL in
            do { try fm.copyItem(at: zipURL, to: url) } catch { copyError = error }
        }
        try? fm.removeItem(at: root)
        if coordinationError != nil || copyError != nil { throw ExportError.packageFailed }
    }
}
