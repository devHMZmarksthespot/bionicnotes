import SwiftUI

/// Minimaler Block-Parser für das Markdown unserer Zusammenfassungen
/// (Überschriften, Aufzählungen, Zitate, Absätze). Gemeinsam für Anzeige und Export.
enum MarkdownBlock: Hashable {
    case heading(level: Int, text: String)
    case bullet(text: String, indent: Int)
    case quote(String)
    case paragraph(String)

    static func parse(_ markdown: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: " "))) }
            paragraph = []
        }
        for raw in markdown.components(separatedBy: "\n") {
            let indent = raw.prefix { $0 == " " }.count / 2
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { flush(); continue }
            if let level = headingLevel(line) {
                flush()
                blocks.append(.heading(level: level, text: String(line.dropFirst(level + 1))))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") {
                flush()
                blocks.append(.bullet(text: String(line.dropFirst(2)), indent: indent))
            } else if line.hasPrefix(">") {
                flush()
                blocks.append(.quote(line.dropFirst().trimmingCharacters(in: .whitespaces)))
            } else if indent > 0, case .bullet(let text, let level)? = blocks.last, paragraph.isEmpty {
                // Fortsetzungszeile einer Aufzählung
                blocks[blocks.count - 1] = .bullet(text: text + "\n" + line, indent: level)
            } else {
                paragraph.append(line)
            }
        }
        flush()
        return blocks
    }

    private static func headingLevel(_ line: String) -> Int? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...4).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return hashes
    }

    /// Inline-Markdown (fett, kursiv) → AttributedString; bei Fehlern der Rohtext.
    static func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }

    /// Text ohne Markdown-Zeichen (für Klartext-Export).
    static func plain(_ text: String) -> String {
        String(inline(text).characters)
    }
}

/// Darstellung des Markdowns in SwiftUI.
struct MarkdownView: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(MarkdownBlock.parse(markdown).enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let level, let text):
                    Text(MarkdownBlock.inline(text))
                        .font(level == 1 ? .title2.bold() : level == 2 ? .title3.bold() : .headline)
                        .padding(.top, level <= 2 ? 8 : 4)
                case .bullet(let text, let indent):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(.secondary)
                        Text(MarkdownBlock.inline(text))
                    }
                    .padding(.leading, CGFloat(indent) * 16)
                case .quote(let text):
                    Text(MarkdownBlock.inline(text))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 10)
                        .overlay(alignment: .leading) { Rectangle().fill(.tertiary).frame(width: 3) }
                case .paragraph(let text):
                    Text(MarkdownBlock.inline(text))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }
}
