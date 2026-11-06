import Foundation

/// „⭐ Wichtig“-Marker auf der Session-Zeitachse, gesetzt am iPhone oder an der Watch.
struct SessionMarker: Codable, Identifiable, Hashable, Sendable {
    enum Source: String, Codable, Sendable { case phone, watch }

    var id = UUID()
    /// Sekunden ab Aufnahmebeginn (ohne Pausen) – gleiche Zeitachse wie Transkript und Audio.
    var time: TimeInterval
    /// Transkript-Ausschnitt vor dem Marker (Kontext).
    var snippet: String
    var source: Source
}

/// Marker einer Session, gespeichert als markers.json im Session-Ordner.
@MainActor
@Observable
final class MarkerStore {
    private(set) var markers: [SessionMarker] = []

    func add(_ marker: SessionMarker, savingTo url: URL) {
        markers.append(marker)
        markers.sort { $0.time < $1.time }
        save(to: url)
    }

    func remove(_ marker: SessionMarker, savingTo url: URL) {
        markers.removeAll { $0.id == marker.id }
        save(to: url)
    }

    func load(from url: URL) {
        guard let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([SessionMarker].self, from: data) else {
            markers = []
            return
        }
        markers = list
    }

    private func save(to url: URL) {
        try? JSONEncoder().encode(markers).write(to: url, options: .atomic)
    }
}
