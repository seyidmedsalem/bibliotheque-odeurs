import Foundation

struct APIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Client HTTP de l'API FastAPI (async/await).
final class APIClient {
    var baseURL: URL
    var token: String?

    init(baseURL: URL, token: String? = nil) {
        self.baseURL = baseURL
        self.token = token
    }

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            if let date = parseDate(s) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Date invalide : \(s)"))
        }
        return d
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()

    /// Dates ISO 8601 du serveur, avec ou sans fractions de seconde, avec ou sans fuseau.
    static func parseDate(_ raw: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        for candidate in [raw, raw + "Z"] {
            if let d = withFraction.date(from: candidate) ?? plain.date(from: candidate) { return d }
        }
        return nil
    }

    func get<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        try await request("GET", path, query: query, body: Optional<String>.none)
    }

    func request<T: Decodable, B: Encodable>(_ method: String, _ path: String,
                                             query: [String: String] = [:], body: B?) async throws -> T {
        let data = try await raw(method, path, query: query, body: body)
        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            throw APIError(message: "Réponse inattendue du serveur (\(path)) : \(error)")
        }
    }

    func send<B: Encodable>(_ method: String, _ path: String, body: B?) async throws {
        _ = try await raw(method, path, query: [:], body: body)
    }

    func send(_ method: String, _ path: String) async throws {
        _ = try await raw(method, path, query: [:], body: Optional<String>.none)
    }

    private func raw<B: Encodable>(_ method: String, _ path: String, query: [String: String], body: B?) async throws -> Data {
        var comps = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var req = URLRequest(url: comps.url!, timeoutInterval: 20)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body { req.httpBody = try Self.encoder.encode(body) }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw APIError(message: "Serveur injoignable (\(baseURL.absoluteString)). Vérifiez l'adresse et que le backend est lancé.")
        }
        guard let http = response as? HTTPURLResponse else { throw APIError(message: "Réponse invalide") }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError(message: Self.detail(from: data) ?? "Erreur \(http.statusCode)")
        }
        return data
    }

    /// Extrait le message d'erreur FastAPI : {"detail": "..."} ou {"detail": [{"msg": "..."}]}
    private static func detail(from data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let s = obj["detail"] as? String { return s }
        if let list = obj["detail"] as? [[String: Any]] {
            return list.compactMap { $0["msg"] as? String }.joined(separator: "\n")
        }
        return nil
    }

    func webSocketURL() -> URL? {
        guard var comps = URLComponents(url: baseURL.appendingPathComponent("ws"), resolvingAgainstBaseURL: false) else { return nil }
        comps.scheme = baseURL.scheme == "https" ? "wss" : "ws"
        comps.queryItems = [URLQueryItem(name: "token", value: token ?? "")]
        return comps.url
    }
}
