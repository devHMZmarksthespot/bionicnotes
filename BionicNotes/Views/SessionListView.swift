import SwiftUI
import SwiftData

struct SessionListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \NoteSession.createdAt, order: .reverse) private var sessions: [NoteSession]
    @State private var path: [NoteSession] = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(sessions) { session in
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
                        }
                    }
                }
                .onDelete(perform: delete)
            }
            .overlay {
                if sessions.isEmpty {
                    ContentUnavailableView("Noch keine Sessions",
                                           systemImage: "waveform",
                                           description: Text("Tippe auf +, um einen Vortrag aufzunehmen."))
                }
            }
            .navigationTitle("BionicNotes")
            .toolbar {
                Button(action: newSession) {
                    Label("Neue Session", systemImage: "plus")
                }
            }
            .navigationDestination(for: NoteSession.self) { session in
                SessionView(session: session)
            }
        }
        // „Starte Aufnahme“ per Siri/Kurzbefehl/Action-Taste
        .onAppear(perform: handleStartRequest)
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

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let session = sessions[index]
            SessionStorage.delete(session.uuid)
            context.delete(session)
        }
    }
}
