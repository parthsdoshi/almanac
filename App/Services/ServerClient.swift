import CryptoKit
import Foundation

/// Talks to the push server (server/ in this repo).
///
/// The upload is a full-state PUT: the push token, time zone, send hour and,
/// for each unmuted occasion, its opaque id, kind, first names and month/day.
/// No last names, years, phone numbers or contact ids leave the phone.
struct ServerClient {
    struct DevicePayload: Codable, Equatable {
        struct Item: Codable, Equatable {
            let id: String
            let kind: String
            let names: [String]
            let month: Int
            let day: Int
        }
        let pushToStartToken: String
        let apnsEnvironment: String
        let timeZone: String
        let sendHour: Int
        let occasions: [Item]

        var fingerprint: String {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            let data = (try? encoder.encode(self)) ?? Data()
            return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
    }

    enum ServerError: LocalizedError {
        case notConfigured
        case badStatus(Int)
        var errorDescription: String? {
            switch self {
            case .notConfigured: "The push server isn't set up in Config/Secrets.xcconfig."
            case .badStatus(let code): "The push server answered \(code)."
            }
        }
    }

    let baseURL: URL?
    let apiKey: String

    var isConfigured: Bool { baseURL != nil && !apiKey.isEmpty }
    var hostDescription: String { baseURL?.host() ?? "Not set" }

    static func fromBundle(_ bundle: Bundle = .main) -> ServerClient {
        let host = (bundle.object(forInfoDictionaryKey: "OccasionsServerHost") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let key = (bundle.object(forInfoDictionaryKey: "OccasionsAPIKey") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ServerClient(baseURL: host.isEmpty ? nil : URL(string: "https://\(host)"), apiKey: key)
    }

    /// A best guess: builds run from Xcode get sandbox tokens, TestFlight/App
    /// Store builds get production ones. If it's wrong (say a Release build run
    /// from Xcode), the server retries the other APNs host and remembers it.
    static var apnsEnvironment: String {
        #if DEBUG
        return "development"
        #else
        return "production"
        #endif
    }

    func putDevice(id: String, payload: DevicePayload) async throws {
        var request = try makeRequest(path: "v1/devices/\(id)", method: "PUT")
        request.httpBody = try JSONEncoder().encode(payload)
        try await send(request)
    }

    /// Asks the server to push-start a Live Activity right now, for testing.
    func sendTest(deviceID: String) async throws {
        try await send(makeRequest(path: "v1/devices/\(deviceID)/test", method: "POST"))
    }

    private func makeRequest(path: String, method: String) throws -> URLRequest {
        guard let baseURL, !apiKey.isEmpty else { throw ServerError.notConfigured }
        var request = URLRequest(url: baseURL.appending(path: path), timeoutInterval: 30)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func send(_ request: URLRequest) async throws {
        let (_, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw ServerError.badStatus(code) }
    }
}
