import SwiftUI

/// Ansicht auf schmalem Bildschirm (Duo zugeklappt). „Schnell“ gibt es nur während der Aufnahme.
enum CompactPane: String, CaseIterable, Identifiable {
    case quick = "Schnell", notes = "Notizen", transcript = "Transkript"
    var id: String { rawValue }
}

/// Arbeitsbereich einer Session: Pencil-Notizen + Transkript.
/// Breit (Duo aufgeklappt): Transkript links, Notizen rechts. Schmal: `compactPane` entscheidet.
struct SessionWorkspace: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    let notes: NotesStore
    let transcript: TranscriptStore
    let isPlaybackMode: Bool
    let playbackTime: TimeInterval?
    /// Abspielposition, solange abgespielt wird – für das Mitlaufen der Notizen.
    let highlightTime: TimeInterval?
    let timeForStroke: (Date) -> TimeInterval?
    let onJump: (TimeInterval) -> Void
    let onSelectSegment: ((TranscriptSegment) -> Void)?
    /// Auf schmalem Bildschirm: welche Ansicht (der Umschalter liegt in der SessionView).
    let compactPane: CompactPane

    @State private var mode: NotesMode = .write
    @State private var pencilMode = PencilPreference.isPencilMode

    var body: some View {
        if sizeClass == .regular {
            GeometryReader { geo in
                // Rechtshänder: Transkript links, Notizen rechts – die Schreibhand verdeckt so nicht das Transkript.
                HStack(spacing: 12) {
                    transcriptPanel
                        .frame(width: geo.size.width * 0.38)
                    notesPanel
                }
            }
        } else {
            switch compactPane {
            case .transcript: transcriptPanel
            case .notes, .quick: notesPanel
            }
        }
    }


    private var notesPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Notizen").font(.headline)
                Spacer()
                if isPlaybackMode && !notes.isEmpty && !pencilMode {
                    Picker("Modus", selection: $mode) {
                        Label("Schreiben", systemImage: "pencil.tip").tag(NotesMode.write)
                        Label("Springen", systemImage: "hand.tap").tag(NotesMode.jump)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
            }
            NotesCanvas(store: notes,
                        pencilMode: pencilMode,
                        mode: mode,
                        jumpEnabled: isPlaybackMode,
                        highlightTime: highlightTime,
                        timeForStroke: timeForStroke,
                        onJump: onJump,
                        onPencilDetected: { pencilMode = true })
            if isPlaybackMode && !notes.isEmpty && (pencilMode || mode == .jump) {
                Text(pencilMode
                     ? "Mit dem Finger auf eine Notiz tippen – das Audio springt an die Stelle. Der Pencil schreibt weiter."
                     : "Tippe auf eine Notiz – das Audio springt an die Stelle, an der du sie geschrieben hast.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var transcriptPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Transkript").font(.headline)
            if transcript.isEmpty {
                Text("Noch kein Transkript.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                TranscriptView(store: transcript, playbackTime: playbackTime, onSelect: onSelectSegment)
            }
        }
    }
}
