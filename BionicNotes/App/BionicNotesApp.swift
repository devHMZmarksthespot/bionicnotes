import SwiftUI
import SwiftData

@main
struct BionicNotesApp: App {
    var body: some Scene {
        WindowGroup {
            SessionListView()
        }
        .modelContainer(for: NoteSession.self)
    }
}
