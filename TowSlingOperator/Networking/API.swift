import Foundation

/// Anything the server said no to, in a form a view can show a person.
struct APIError: LocalizedError {
    let message: String
    let status: Int

    var errorDescription: String? { message }

    /// 401 means the token is gone or expired — the only error that should
    /// bounce someone back to the sign-in screen. Everything else is a problem
    /// with one request, not with being signed in, and logging a driver out
    /// mid-job because a poll failed would be its own bug.
    var isUnauthorized: Bool { status == 401 }
}

/// The shape every endpoint answers with.
private struct Envelope<T: Decodable>: Decodable {
    let success: Bool
    let message: String?
    let error: String?
    let payload: T?

    // The API puts its data at the TOP level alongside success/message rather
    // than under a "data" key, so the payload is decoded from the same
    // container. `payload` is filled in by the decoder below.
    private enum CodingKeys: String, CodingKey {
        case success, message, error
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = (try? c.decode(Bool.self, forKey: .success)) ?? false
        message = try? c.decode(String.self, forKey: .message)
        error   = try? c.decode(String.self, forKey: .error)

        // Written out rather than as a ternary: `cond ? try? x : nil` does not
        // parse.
        if success {
            payload = try? T(from: decoder)
        } else {
            payload = nil
        }
    }
}

/// Money and distances come back as JSON numbers in some endpoints and as
/// strings in others — the PHP helper `money()` formats to "110.00" while a
/// plain `(float)` cast emits 110. Rather than chase every field back through
/// the API and risk missing one, decode either.
/// Equatable so the models that carry it can synthesise their own ==, which is
/// what lets SwiftUI skip redrawing a board where nothing actually changed.
@propertyWrapper
struct Flexible: Decodable, Equatable {
    var wrappedValue: Double

    init(wrappedValue: Double) { self.wrappedValue = wrappedValue }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) { wrappedValue = d; return }
        if let s = try? c.decode(String.self), let d = Double(s) { wrappedValue = d; return }
        wrappedValue = 0
    }
}

extension KeyedDecodingContainer {
    /// So a missing money field decodes as 0 rather than throwing.
    func decode(_ type: Flexible.Type, forKey key: Key) throws -> Flexible {
        try decodeIfPresent(Flexible.self, forKey: key) ?? Flexible(wrappedValue: 0)
    }
}

/// One HTTP client for the whole app.
actor API {
    static let shared = API()

    /// Set by Session on sign-in, cleared on sign-out.
    private var token: String?

    func setToken(_ value: String?) { token = value }

    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = Config.requestTimeout
        c.waitsForConnectivity = false      // fail and say so, do not hang
        return URLSession(configuration: c)
    }()

    private let decoder = JSONDecoder()

    // MARK: - Verbs

    // [:] not [] — an empty DICTIONARY literal. `[]` is an empty array and Swift
    // says so: "Use [:] to get an empty dictionary literal".
    func get<T: Decodable>(_ path: String, query: [String: String] = [:],
                           as type: T.Type) async throws -> T {
        try await send(path, method: "GET", query: query, body: nil, as: type)
    }

    func post<T: Decodable>(_ path: String, body: [String: Any] = [:],
                            as type: T.Type) async throws -> T {
        let data = try JSONSerialization.data(withJSONObject: body)
        return try await send(path, method: "POST", query: [:], body: data, as: type)
    }

    /// For endpoints whose reply we do not care about beyond success.
    ///
    /// Deliberately NOT an overload of `post`: two functions differing only by
    /// return type make every call site that ignores the result ambiguous.
    func postIgnoringResult(_ path: String, body: [String: Any] = [:]) async throws {
        struct Ack: Decodable { }
        _ = try await post(path, body: body, as: Ack.self)
    }

    // MARK: - The one request function

    private func send<T: Decodable>(_ path: String, method: String,
                                    query: [String: String], body: Data?,
                                    as type: T.Type) async throws -> T {

        // The leading slash is trimmed first. appendingPathComponent("/calls/board")
        // yields ".../api//calls/board", and the server's rewrite rule matches
        // ^api/([a-z-]+)/([a-z-]+)$ — a double slash misses it and every call
        // 404s. Cheaper to normalise here than to remember it at each call site.
        let clean = path.hasPrefix("/") ? String(path.dropFirst()) : path
        var comps = URLComponents(
            url: Config.apiBase.appendingPathComponent(clean),
            resolvingAgainstBaseURL: false
        )!

        // lang=en on every call. The API answers in Spanish by default, and an
        // English-speaking operator being told "No pudimos cobrar la tarjeta"
        // is a support ticket rather than a message.
        var items = [URLQueryItem(name: "lang", value: "en")]
        for (k, v) in query { items.append(URLQueryItem(name: k, value: v)) }
        comps.queryItems = items

        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        req.httpBody = body
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            // A dead network is not a server error and must not read like one.
            throw APIError(message: "No connection. Check your signal and try again.",
                           status: 0)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        let envelope: Envelope<T>
        do {
            envelope = try decoder.decode(Envelope<T>.self, from: data)
        } catch {
            // The body was not the JSON we expect. Almost always a PHP fatal,
            // which returns an empty body or an HTML error page — say something
            // truthful rather than surfacing a decoding error at a driver.
            throw APIError(message: "The server sent back something we could not read.",
                           status: status)
        }

        guard envelope.success, let payload = envelope.payload else {
            throw APIError(message: envelope.error ?? "Something went wrong.",
                           status: status)
        }
        return payload
    }
}
