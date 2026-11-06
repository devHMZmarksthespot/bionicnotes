import Foundation

/// Sprachen, die wir in der UI anbieten (SpeechTranscriber kann mehr – bei Bedarf erweitern).
enum TranscriptionLanguage: String, CaseIterable, Identifiable {
    case german = "de-DE"
    case english = "en-US"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .german: "Deutsch"
        case .english: "English"
        }
    }

    var shortLabel: String {
        switch self {
        case .german: "DE"
        case .english: "EN"
        }
    }

    private static let lastUsedKey = "lastTranscriptionLanguage"

    /// Zuletzt gewählte Sprache; beim allerersten Mal die Gerätesprache (Englisch) bzw. Deutsch.
    static var defaultIdentifier: String {
        if let last = UserDefaults.standard.string(forKey: lastUsedKey) { return last }
        return Locale.current.language.languageCode?.identifier == "en" ? english.rawValue : german.rawValue
    }

    static func remember(_ identifier: String) {
        UserDefaults.standard.set(identifier, forKey: lastUsedKey)
    }
}
