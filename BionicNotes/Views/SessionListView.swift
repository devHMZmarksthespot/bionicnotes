import SwiftUI
import SwiftData

struct SessionListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \NoteSession.createdAt, order: .reverse) private var sessions: [NoteSession]
    @State private var path: [NoteSession] = []
    @State private var query = ""
    /// Durchsuchbarer Text pro Session – wird beim Beginn einer Suche frisch von der Platte gelesen.
    @State private var searchIndex: [UUID: String] = [:]
    @State private var isSettingsShown = false

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    private var visibleSessions: [NoteSession] {
        guard !trimmedQuery.isEmpty else { return sessions }
        return sessions.filter { session in
            session.title.localizedStandardContains(trimmedQuery)
                || (searchIndex[session.uuid]?.localizedStandardContains(trimmedQuery) ?? false)
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(visibleSessions) { session in
                    NavigationLink(value: session) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.title).font(.headline)
                            HStack {
                                Text(session.createdAt, format: .dateTime.day().month().hour().minute())
                                if session.hasAudio {
                                    Label(session.duration.clockString, systemImage: "waveform")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            if let snippet = snippet(for: session) {
                                Text(snippet)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
                .onDelete(perform: delete)
            }
            .overlay {
                if !trimmedQuery.isEmpty && visibleSessions.isEmpty {
                    ContentUnavailableView.search(text: trimmedQuery)
                } else if sessions.isEmpty {
                    ContentUnavailableView("Noch keine Sessions",
                                           systemImage: "waveform",
                                           description: Text("Tippe auf +, um einen Vortrag aufzunehmen."))
                }
            }
            .navigationTitle("BionicNotes")
            .searchable(text: $query, prompt: "Titel, Transkript, Folien, Zusammenfassungen")
            .onChange(of: query) { old, new in
                if old.isEmpty && !new.isEmpty { buildSearchIndex() }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { isSettingsShown = true } label: {
                        Label("Einstellungen", systemImage: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: newSession) {
                        Label("Neue Session", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $isSettingsShown) { SettingsView() }
            .navigationDestination(for: NoteSession.self) { session in
                SessionView(session: session)
            }
        }
        // „Starte Aufnahme“ per Siri/Kurzbefehl/Action-Taste
        .onAppear {
            #if DEBUG
            DemoSession.runAllSummariesIfRequested(context: context)
            DemoSession.runRetranscribeAllIfRequested(context: context)
            DemoSession.runPCCProbeIfRequested()
            if ProcessInfo.processInfo.arguments.contains("-openSettings") { isSettingsShown = true }
            if let demo = DemoSession.seedIfRequested(context: context), DemoSession.shouldOpenDemo, path.isEmpty {
                path = [demo]
            }
            #endif
            handleStartRequest()
        }
        .onChange(of: SessionCommands.shared.pending) { handleStartRequest() }
    }

    private func handleStartRequest() {
        // Läuft schon eine Aufnahme, beantwortet der Intent das selbst.
        guard PhoneWatchLink.shared.current == nil,
              SessionCommands.shared.take(.newRecording) else { return }
        let title = "Vortrag " + Date.now.formatted(date: .abbreviated, time: .shortened)
        let session = NoteSession(title: title)
        context.insert(session)
        SessionCommands.shared.autoStartSessionID = session.uuid
        path = [session]
    }

    private func newSession() {
        let title = "Vortrag " + Date.now.formatted(date: .abbreviated, time: .shortened)
        let session = NoteSession(title: title)
        context.insert(session)
        path.append(session)
    }

    private func buildSearchIndex() {
        var index: [UUID: String] = [:]
        for session in sessions {
            let content = SessionContent.load(session)
            var parts = [content.transcriptText]
            parts += content.photos.compactMap(\.recognizedText)
            parts += content.markers.map(\.snippet)
            parts += content.summaries.map(\.text)
            index[session.uuid] = parts.joined(separator: "\n")
        }
        searchIndex = index
    }

    /// Textausschnitt rund um den ersten Treffer (nicht im Titel).
    private func snippet(for session: NoteSession) -> String? {
        guard !trimmedQuery.isEmpty, !session.title.localizedStandardContains(trimmedQuery),
              let text = searchIndex[session.uuid],
              let range = text.range(of: trimmedQuery, options: [.caseInsensitive, .diacriticInsensitive]) else { return nil }
        let start = text.index(range.lowerBound, offsetBy: -40, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: 80, limitedBy: text.endIndex) ?? text.endIndex
        let excerpt = text[start..<end].replacingOccurrences(of: "\n", with: " ")
        return (start > text.startIndex ? "…" : "") + excerpt + (end < text.endIndex ? "…" : "")
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let session = visibleSessions[index]
            SessionStorage.delete(session.uuid)
            context.delete(session)
        }
    }
}
