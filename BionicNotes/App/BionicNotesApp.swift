import SwiftUI
import SwiftData

@main
struct BionicNotesApp: App {
    init() {
        PhoneWatchLink.shared.activate()
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
