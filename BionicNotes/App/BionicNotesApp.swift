import SwiftUI
import SwiftData

@main
struct BionicNotesApp: App {
    init() {
        #if DEBUG
        TranscriptionSelfTest.runIfRequested()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            SessionListView()
        }
        .modelContainer(for: NoteSession.self)
    }
}
