import SwiftUI

/// Watch-App: später Fernbedienung (Aufnahme, ⭐ Marker, Foto) und BionicNotes Rewind.
/// Aktuell nur Gerüst, damit Projekt-Setup und Signing für beide Plattformen stehen.
@main
struct BionicNotesWatchApp: App {
    var body: some Scene {
        WindowGroup {
            WatchHomeView()
        }
    }
}

struct WatchHomeView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.system(size: 36))
                .foregroundStyle(.red)
            Text("BionicNotes")
                .font(.headline)
            Text("Starte eine Session auf dem iPhone.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
