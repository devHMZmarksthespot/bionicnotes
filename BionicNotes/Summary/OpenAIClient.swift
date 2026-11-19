import Foundation
import Security

/// Optional: Berichte mit dem eigenen OpenAI-API-Key des Nutzers („bring your own key“).
///
/// - Der Key liegt nur in der Keychain dieses Geräts (`…ThisDeviceOnly`: kein iCloud-Schlüsselbund,
///   nicht in Backups übertragbar) – nie in UserDefaults, Logs oder Exporten.
/// - Transkript, Folientexte und Marker gehen dabei an OpenAI (Drittanbieter); die Kosten trägt der Nutzer.
/// - Endpunkt bewusst konfigurierbar (später Enterprise, z. B. Azure OpenAI / OpenAI-kompatibel).
enum OpenAIClient {
    static let enabledKey = "summaryUsesOpenAI"
    static let defaultModel = "gpt-6-astra"
    static let defaultBaseURL = URL(string: "https://api.openai.com/v1")!

    static var model: String { defaultModel }
    static var baseURL: URL { defaultBaseURL }

    /// Nutzer hat OpenAI eingeschaltet und einen Key hinterlegt. Debug: `-summaryEngine openai`.
    static var isEnabled: Bool {
        guard hasKey else { return false }
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-summaryEngine"), i + 1 < args.count { return args[i + 1] == "openai" }
        #endif
        return UserDefaults.standard.bool(forKey: enabledKey)
    }

    enum ClientError: LocalizedError {
        case noKey
        case invalidKey
        case quotaExceeded
        case rateLimited
        case server(Int)
        case emptyResponse
        case network

        var errorDescription: String? {
            switch self {
            case .noKey: "Kein OpenAI-Key hinterlegt."
            case .invalidKey: "Der OpenAI-Key ist ungültig oder wurde widerrufen."
            case .quotaExceeded: "Das Guthaben bzw. Limit des OpenAI-Kontos ist aufgebraucht."
            case .rateLimited: "OpenAI ist gerade ausgelastet (zu viele Anfragen)."
            case .server(let code): "OpenAI hat mit einem Fehler geantwortet (\(code))."
            case .emptyResponse: "OpenAI hat keinen Text zurückgegeben."
            case .network: "Keine Verbindung zu OpenAI."
            }
        }
    }

    struct Response {
        var text: String
        var inputTokens: Int?
        var outputTokens: Int?
    }

    // MARK: - Aufrufe

    /// Ein Aufruf der Responses-API. Wiederholt bei Überlast/Serverfehlern bis zu zweimal.
    static func respond(instructions: String, input: String) async throws -> Response {
        guard let key = Keychain.load() else { throw ClientError.noKey }
        var request = URLRequest(url: baseURL.appending(path: "responses"), timeoutInterval: 900)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model, "instructions": instructions, "input": input, "store": false,
        ])

        var delays: [Double] = [3, 10]
        while true {
            do {
                let (data, response) = try await send(request)
                try check(response, data: data)
                return try parse(data)
            } catch let error as ClientError {
                switch error {
                case .rateLimited, .server, .network:
                    guard !delays.isEmpty else { throw error }
                    try await Task.sleep(for: .seconds(delays.removeFirst()))
                default:
                    throw error
                }
            }
        }
    }

    /// Prüft einen Key ohne Kosten (Modellliste abrufen).
    static func verify(key: String) async throws {
        var request = URLRequest(url: baseURL.appending(path: "models"), timeoutInterval: 20)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await send(request)
        try check(response, data: data)
    }

    private static func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await URLSession.shared.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw ClientError.network
        }
    }

    private static func check(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw ClientError.network }
        switch http.statusCode {
        case 200..<300: return
        case 401, 403: throw ClientError.invalidKey
        case 429:
            // 429 bedeutet entweder Drosselung oder aufgebrauchtes Guthaben („insufficient_quota“).
            let body = String(data: data, encoding: .utf8) ?? ""
            throw body.contains("insufficient_quota") ? ClientError.quotaExceeded : ClientError.rateLimited
        case 500...: throw ClientError.server(http.statusCode)
        default: throw ClientError.server(http.statusCode)
        }
    }

    private static func parse(_ data: Data) throws -> Response {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ClientError.emptyResponse }
        let output = json["output"] as? [[String: Any]] ?? []
        let text = output
            .filter { $0["type"] as? String == "message" }
            .flatMap { $0["content"] as? [[String: Any]] ?? [] }
            .compactMap { $0["text"] as? String }
            .joined()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ClientError.emptyResponse }
        let usage = json["usage"] as? [String: Any]
        return Response(text: text, inputTokens: usage?["input_tokens"] as? Int, outputTokens: usage?["output_tokens"] as? Int)
    }

    // MARK: - Keychain

    static var hasKey: Bool { Keychain.load() != nil }

    /// Für die Anzeige: nur Anfang und Ende, z. B. „sk-…a1B2“.
    static var maskedKey: String? {
        guard let key = Keychain.load(), key.count > 8 else { return nil }
        return "\(key.prefix(3))…\(key.suffix(4))"
    }

    enum Keychain {
        private static let service = "hmzinnovation.bionicnotes.openai"
        private static let account = "api-key"

        private static var query: [String: Any] {
            [kSecClass as String: kSecClassGenericPassword,
             kSecAttrService as String: service,
             kSecAttrAccount as String: account]
        }

        static func load() -> String? {
            var item: CFTypeRef?
            var q = query
            q[kSecReturnData as String] = true
            q[kSecMatchLimit as String] = kSecMatchLimitOne
            guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
                  let data = item as? Data, let key = String(data: data, encoding: .utf8), !key.isEmpty else { return nil }
            return key
        }

        @discardableResult
        static func save(_ key: String) -> Bool {
            delete()
            var q = query
            q[kSecValueData as String] = Data(key.utf8)
            q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
        }

        static func delete() {
            SecItemDelete(query as CFDictionary)
        }
    }
}
