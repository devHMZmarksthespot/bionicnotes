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

    // MARK: - Backup

    private static let backupKey = "includeSessionsInBackup"

    /// Standard: Sessions sind vom iCloud-/Geräte-Backup ausgeschlossen – die Daten bleiben auf dem Gerät,
    /// solange der Kunde es nicht ausdrücklich anders will.
    static var isIncludedInBackup: Bool {
        get { UserDefaults.standard.bool(forKey: backupKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: backupKey)
            applyBackupPreference()
        }
    }

    static func applyBackupPreference() {
        var url = root
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = !isIncludedInBackup
        try? url.setResourceValues(values)
    }

    static func delete(_ id: UUID) {
        try? FileManager.default.removeItem(at: root.appending(path: id.uuidString, directoryHint: .isDirectory))
    }
}
