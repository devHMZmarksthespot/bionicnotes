import Foundation

/// Dateiablage: Documents/Sessions/<uuid>/audio.m4a, später auch drawing.data, photos/, transcript.json
enum SessionStorage {
    static var root: URL {
        URL.documentsDirectory.appending(path: "Sessions", directoryHint: .isDirectory)
    }

    static func folder(for id: UUID) -> URL {
        let url = root.appending(path: id.uuidString, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func delete(_ id: UUID) {
        try? FileManager.default.removeItem(at: root.appending(path: id.uuidString, directoryHint: .isDirectory))
    }
}
