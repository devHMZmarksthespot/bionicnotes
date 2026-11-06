import SwiftUI

/// Watch-App: Status der Aufnahme, BionicNotes Rewind (letzte 30–60 s Transkript) und ⭐-Marker.
/// Transkribiert wird auf dem iPhone – SpeechAnalyzer gibt es auf watchOS nicht.
@main
struct BionicNotesWatchApp: App {
    init() {
        WatchLink.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                WatchHomeView(link: WatchLink.shared)
            }
        }
    }
}
