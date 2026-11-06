import SwiftUI

/// Arbeitsbereich einer Session: Pencil-Notizen + Transkript.
/// Breit (Duo aufgeklappt): Transkript links, Notizen rechts. Schmal: umschaltbar.
struct SessionWorkspace: View {
    enum Tab: String, CaseIterable, Identifiable {
        case notes = "Notizen", transcript = "Transkript"
        var id: String { rawValue }
    }

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

    @State private var mode: NotesMode = .write
    @State private var pencilMode = PencilPreference.isPencilMode
    @State private var tab: Tab = .notes

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
            VStack(spacing: 8) {
                Picker("Ansicht", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                switch tab {
                case .notes: notesPanel
                case .transcript: transcriptPanel
                }
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
