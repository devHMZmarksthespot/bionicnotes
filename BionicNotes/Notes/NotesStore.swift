import Foundation
import Observation
import PencilKit

/// Pencil-Notizen einer Session plus Zeitindex: welcher Strich gehört zu welcher Stelle der Aufnahme.
///
/// PencilKit gibt jedem Strich ein `creationDate`. Wir rechnen es beim Zeichnen auf die
/// Session-Zeitachse um (gleiche Zeitachse wie Audio, Transkript und Marker) und speichern
/// das in strokes.json. Gespeichert wird drawing.data (PKDrawing) im Session-Ordner.
@MainActor
@Observable
final class NotesStore {
    private struct StrokeTime: Codable {
        let created: Double   // creationDate.timeIntervalSinceReferenceDate
        let time: Double      // Sekunden auf der Session-Zeitachse
    }

    private(set) var drawing = PKDrawing()
    @ObservationIgnored private var times: [Double: TimeInterval] = [:]
    @ObservationIgnored private var drawingURL: URL?
    @ObservationIgnored private var timesURL: URL?
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    var isEmpty: Bool { drawing.strokes.isEmpty }

    func load(drawingURL: URL, timesURL: URL) {
        self.drawingURL = drawingURL
        self.timesURL = timesURL
        if let data = try? Data(contentsOf: drawingURL), let loaded = try? PKDrawing(data: data) {
            drawing = loaded
        }
        if let data = try? Data(contentsOf: timesURL),
           let list = try? JSONDecoder().decode([StrokeTime].self, from: data) {
            times = Dictionary(list.map { ($0.created, $0.time) }, uniquingKeysWith: { first, _ in first })
        }
    }

    /// Neue Zeichnung vom Canvas. Neue Striche bekommen ihre Session-Zeit über `timeFor`.
    func update(_ newDrawing: PKDrawing, timeFor: (Date) -> TimeInterval?) {
        for stroke in newDrawing.strokes {
            let key = Self.key(stroke)
            guard times[key] == nil, let time = timeFor(stroke.path.creationDate) else { continue }
            times[key] = time
        }
        drawing = newDrawing
        scheduleSave()
    }

    func time(of stroke: PKStroke) -> TimeInterval? {
        times[Self.key(stroke)]
    }

    /// Strich mit Zeitverknüpfung an einer Stelle der Zeichnung (Content-Koordinaten).
    func timedStroke(at point: CGPoint, tolerance: CGFloat = 22) -> (stroke: PKStroke, time: TimeInterval)? {
        var best: (stroke: PKStroke, time: TimeInterval, distance: CGFloat)?
        for stroke in drawing.strokes.reversed() {
            guard let time = time(of: stroke),
                  stroke.renderBounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point) else { continue }
            for strokePoint in stroke.path {
                let location = strokePoint.location.applying(stroke.transform)
                let distance = hypot(location.x - point.x, location.y - point.y)
                if distance <= tolerance, distance < (best?.distance ?? .infinity) {
                    best = (stroke, time, distance)
                }
            }
        }
        return best.map { ($0.stroke, $0.time) }
    }

    /// Sofort speichern (z. B. beim Verlassen der Session).
    func saveNow() {
        saveTask?.cancel()
        write()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.write()
        }
    }

    private func write() {
        guard let drawingURL, let timesURL else { return }
        try? drawing.dataRepresentation().write(to: drawingURL, options: .atomic)
        let list = times.map { StrokeTime(created: $0.key, time: $0.value) }
        try? JSONEncoder().encode(list).write(to: timesURL, options: .atomic)
    }

    private static func key(_ stroke: PKStroke) -> Double {
        stroke.path.creationDate.timeIntervalSinceReferenceDate
    }
}
