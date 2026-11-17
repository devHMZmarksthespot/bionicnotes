import UIKit

/// Export-Blöcke → NSAttributedString (für RTF und PDF). Farben fest schwarz/grau,
/// damit Dateien im Dark Mode nicht weiß auf weiß landen.
enum AttributedDocument {
    static let contentWidth: CGFloat = PDFDocumentRenderer.pageSize.width - 2 * PDFDocumentRenderer.margin
    static let maxImageHeight: CGFloat = PDFDocumentRenderer.pageSize.height - 2 * PDFDocumentRenderer.margin - 80

    static func make(_ blocks: [SessionExporter.Block]) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let body = UIFont.systemFont(ofSize: 11)
        let text = UIColor.black
        let secondary = UIColor.darkGray

        func style(spacingBefore: CGFloat = 0, after: CGFloat = 4, indent: CGFloat = 0, hanging: CGFloat = 0) -> NSParagraphStyle {
            let p = NSMutableParagraphStyle()
            p.paragraphSpacingBefore = spacingBefore
            p.paragraphSpacing = after
            p.firstLineHeadIndent = indent
            p.headIndent = indent + hanging
            p.lineHeightMultiple = 1.15
            return p
        }

        func append(_ markdown: String, font: UIFont, color: UIColor, paragraph: NSParagraphStyle, prefix: String = "") {
            let line = NSMutableAttributedString(string: prefix, attributes: [.font: font, .foregroundColor: color])
            line.append(inline(markdown, font: font, color: color))
            line.append(NSAttributedString(string: "\n"))
            line.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: line.length))
            out.append(line)
        }

        for block in blocks {
            switch block {
            case .title(let s):
                append(s, font: .systemFont(ofSize: 22, weight: .bold), color: text, paragraph: style(after: 4))
            case .meta(let s):
                append(s, font: .italicSystemFont(ofSize: 10), color: secondary, paragraph: style(after: 14))
            case .heading(let s, let level):
                let size: CGFloat = level <= 2 ? 15 : 12.5
                append(s, font: .systemFont(ofSize: size, weight: .semibold), color: text,
                       paragraph: style(spacingBefore: level <= 2 ? 14 : 8, after: 6))
            case .paragraph(let s):
                append(s, font: body, color: text, paragraph: style(after: 6))
            case .bullet(let s, let indent):
                append(s.replacingOccurrences(of: "\n", with: " "), font: body, color: text,
                       paragraph: style(after: 3, indent: 6 + CGFloat(indent) * 14, hanging: 10), prefix: "•  ")
            case .quote(let s):
                append(s, font: .italicSystemFont(ofSize: 10.5), color: secondary, paragraph: style(after: 6, indent: 14))
            case .timed(let time, let s):
                let line = NSMutableAttributedString(string: time.clockString + "\t",
                                                     attributes: [.font: UIFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .medium),
                                                                  .foregroundColor: secondary])
                line.append(NSAttributedString(string: s + "\n", attributes: [.font: body, .foregroundColor: text]))
                let paragraph = style(after: 3, hanging: 46).mutableCopy() as! NSMutableParagraphStyle
                paragraph.tabStops = [NSTextTab(textAlignment: .left, location: 46)]
                line.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: line.length))
                out.append(line)
            case .image(let image, let caption):
                let attachment = NSTextAttachment(image: image)
                let scale = min(contentWidth / image.size.width, maxImageHeight / image.size.height, 1.5)
                attachment.bounds = CGRect(x: 0, y: 0, width: image.size.width * scale, height: image.size.height * scale)
                let line = NSMutableAttributedString(attachment: attachment)
                line.append(NSAttributedString(string: "\n"))
                line.addAttribute(.paragraphStyle, value: style(spacingBefore: 6, after: caption == nil ? 10 : 2),
                                  range: NSRange(location: 0, length: line.length))
                out.append(line)
                if let caption {
                    append(caption, font: .systemFont(ofSize: 9.5, weight: .medium), color: secondary, paragraph: style(after: 10))
                }
            }
        }
        return out
    }

    private static func inline(_ markdown: String, font: UIFont, color: UIColor) -> NSAttributedString {
        let parsed = MarkdownBlock.inline(markdown)
        let result = NSMutableAttributedString()
        for run in parsed.runs {
            let piece = String(parsed[run.range].characters)
            var runFont = font
            if let intent = run.inlinePresentationIntent {
                var traits = font.fontDescriptor.symbolicTraits
                if intent.contains(.stronglyEmphasized) { traits.insert(.traitBold) }
                if intent.contains(.emphasized) { traits.insert(.traitItalic) }
                if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) {
                    runFont = UIFont(descriptor: descriptor, size: font.pointSize)
                }
            }
            result.append(NSAttributedString(string: piece, attributes: [.font: runFont, .foregroundColor: color]))
        }
        return result
    }
}

/// A4-PDF mit Seitenumbruch über TextKit 1 (zeichnet auch Bild-Anhänge) und Seitenzahl.
enum PDFDocumentRenderer {
    static let pageSize = CGSize(width: 595.2, height: 841.8)
    static let margin: CGFloat = 50

    static func render(_ blocks: [SessionExporter.Block], title: String) -> Data {
        let storage = NSTextStorage(attributedString: AttributedDocument.make(blocks))
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: title, kCGPDFContextCreator as String: "BionicNotes"]
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize), format: format)
        let footer: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 8), .foregroundColor: UIColor.gray]

        return renderer.pdfData { context in
            let textSize = CGSize(width: pageSize.width - 2 * margin, height: pageSize.height - 2 * margin - 16)
            var page = 0
            var location = 0
            repeat {
                let container = NSTextContainer(size: textSize)
                container.lineFragmentPadding = 0
                layout.addTextContainer(container)
                let range = layout.glyphRange(for: container)
                context.beginPage()
                page += 1
                let origin = CGPoint(x: margin, y: margin)
                layout.drawBackground(forGlyphRange: range, at: origin)
                layout.drawGlyphs(forGlyphRange: range, at: origin)
                let label = "\(title) · \(page)" as NSString
                label.draw(at: CGPoint(x: margin, y: pageSize.height - margin + 10), withAttributes: footer)
                // Leere Seite (nichts passte) → abbrechen statt Endlosschleife
                guard range.length > 0 else { break }
                location = NSMaxRange(range)
            } while location < layout.numberOfGlyphs && page < 500
        }
    }
}
