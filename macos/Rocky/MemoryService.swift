import AppKit
import Foundation
import Network

enum MemoryServiceError: LocalizedError {
    case notAuthenticated
    case invalidBrokerURL
    case couldNotOpenBrowser
    case invalidCallbackState
    case missingAccessToken
    case invalidResponse
    case serviceError(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Rocky memory isn't connected to your web account yet."
        case .invalidBrokerURL:
            return "Rocky couldn't create the memory account login URL."
        case .couldNotOpenBrowser:
            return "Rocky couldn't open the browser to sign in."
        case .invalidCallbackState:
            return "Rocky received an invalid memory login callback."
        case .missingAccessToken:
            return "Rocky didn't receive a memory session token."
        case .invalidResponse:
            return "Rocky couldn't read the memory service response."
        case .serviceError(let message):
            return message
        }
    }
}

struct RockyAccountSession: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Int?
    let userID: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresAt = "expires_at"
        case userID = "user_id"
    }

    var isExpired: Bool {
        guard let expiresAt, expiresAt > 0 else { return false }
        return Date().timeIntervalSince1970 >= Double(expiresAt)
    }
}

struct MemoryConversationRecord: Decodable {
    let id: String
    let title: String?
    let status: String

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case status
    }
}

struct MemoryConversationSummaryRecord: Decodable {
    let id: String
    let summaryText: String
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case summaryText = "summary_text"
        case updatedAt = "updated_at"
    }
}

struct MemoryItemRecord: Decodable {
    let id: String
    let type: String
    let content: String
    let confidence: Double
}

struct MemoryPromptContext: Decodable {
    let summaryText: String?
    let recentTranscript: String
    let memoryLines: [String]

    enum CodingKeys: String, CodingKey {
        case summaryText = "summary_text"
        case recentTranscript = "recent_transcript"
        case memoryLines = "memory_lines"
    }
}

struct MemoryConversationContextEnvelope: Decodable {
    let ok: Bool
    let conversation: MemoryConversationRecord
    let summary: MemoryConversationSummaryRecord?
    let relevantMemoryItems: [MemoryItemRecord]
    let promptContext: MemoryPromptContext

    enum CodingKeys: String, CodingKey {
        case ok
        case conversation
        case summary
        case relevantMemoryItems = "relevant_memory_items"
        case promptContext = "prompt_context"
    }
}

private struct ConversationEnvelope: Decodable {
    let ok: Bool
    let conversation: MemoryConversationRecord
}

private struct GenericOKEnvelope: Decodable {
    let ok: Bool
}

final class MemoryService {
    private let session: URLSession
    private let brokerBaseURL: URL
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    private let accountSessionKeychainKey = "rocky.memory.accountSession"

    init(
        session: URLSession = .shared,
        brokerBaseURL: URL = URL(string: "https://rocky-web-gules.vercel.app")!
    ) {
        self.session = session
        self.brokerBaseURL = brokerBaseURL

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
    }

    var hasAuthenticatedSession: Bool {
        guard let accountSession = currentSession else { return false }
        return !accountSession.accessToken.isEmpty && !accountSession.isExpired
    }

    var currentSession: RockyAccountSession? {
        guard
            let raw = KeychainStore.string(for: accountSessionKeychainKey),
            let data = raw.data(using: .utf8),
            let session = try? decoder.decode(RockyAccountSession.self, from: data)
        else {
            return nil
        }

        return session
    }

    func connectAccount() async throws -> RockyAccountSession {
        let callbackServer = try MemoryCallbackServer()
        try await callbackServer.start()
        defer { callbackServer.stop() }

        let state = UUID().uuidString
        let loginURL = try makeDesktopLoginURL(redirectURI: callbackServer.redirectURI, state: state)

        guard NSWorkspace.shared.open(loginURL) else {
            throw MemoryServiceError.couldNotOpenBrowser
        }

        let callbackURL = try await callbackServer.waitForCallback()
        let callbackState = try callbackValue(named: "state", from: callbackURL)
        guard callbackState == state else {
            throw MemoryServiceError.invalidCallbackState
        }

        if let errorMessage = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "error" })?
            .value,
           !errorMessage.isEmpty
        {
            throw MemoryServiceError.serviceError(errorMessage.replacingOccurrences(of: "_", with: " "))
        }

        let accessToken = try callbackValue(named: "access_token", from: callbackURL)
        let refreshToken = try callbackValue(named: "refresh_token", from: callbackURL)
        let userID = try callbackValue(named: "user_id", from: callbackURL)
        let expiresAt = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "expires_at" })?
            .value
            .flatMap(Int.init)

        let accountSession = RockyAccountSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            userID: userID
        )
        try saveSession(accountSession)
        return accountSession
    }

    func signOut() {
        KeychainStore.removeValue(for: accountSessionKeychainKey)
    }

    func fetchMemorySettings() async throws -> MemorySettingsRecord {
        let endpoint = brokerBaseURL
            .appendingPathComponent("api")
            .appendingPathComponent("memory")
            .appendingPathComponent("settings")

        var request = try authorizedRequest(url: endpoint)
        request.httpMethod = "GET"

        let (data, response) = try await session.data(for: request)
        let envelope: MemorySettingsEnvelope = try decode(data: data, response: response)
        guard envelope.ok else {
            throw MemoryServiceError.invalidResponse
        }

        return envelope.settings
    }

    func updateMemorySettings(_ settings: MemorySettingsRecord) async throws -> MemorySettingsRecord {
        let endpoint = brokerBaseURL
            .appendingPathComponent("api")
            .appendingPathComponent("memory")
            .appendingPathComponent("settings")

        var request = try authorizedRequest(url: endpoint)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "memory_enabled": settings.memoryEnabled,
            "profile_memory_enabled": settings.profileMemoryEnabled,
            "project_memory_enabled": settings.projectMemoryEnabled,
            "preference_memory_enabled": settings.preferenceMemoryEnabled,
            "sensitive_memory_enabled": settings.sensitiveMemoryEnabled,
            "auto_extract_enabled": settings.autoExtractEnabled,
            "retention_days": settings.retentionDays as Any
        ])

        let (data, response) = try await session.data(for: request)
        let envelope: MemorySettingsEnvelope = try decode(data: data, response: response)
        guard envelope.ok else {
            throw MemoryServiceError.invalidResponse
        }

        return envelope.settings
    }

    func createConversation(existingConversationID: String?) async throws -> String {
        if let existingConversationID, !existingConversationID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return existingConversationID
        }

        let endpoint = brokerBaseURL
            .appendingPathComponent("api")
            .appendingPathComponent("chat")
            .appendingPathComponent("conversations")

        var request = try authorizedRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [:])

        let (data, response) = try await session.data(for: request)
        let envelope: ConversationEnvelope = try decode(data: data, response: response)
        guard envelope.ok else {
            throw MemoryServiceError.invalidResponse
        }

        return envelope.conversation.id
    }

    func fetchConversationContext(conversationID: String) async throws -> MemoryConversationContextEnvelope {
        let endpoint = brokerBaseURL
            .appendingPathComponent("api")
            .appendingPathComponent("chat")
            .appendingPathComponent("conversations")
            .appendingPathComponent(conversationID)
            .appendingPathComponent("context")

        var request = try authorizedRequest(url: endpoint)
        request.httpMethod = "GET"

        let (data, response) = try await session.data(for: request)
        return try decode(data: data, response: response)
    }

    func appendCompletedTurn(
        conversationID: String,
        userText: String?,
        assistantText: String?
    ) async throws {
        let trimmedUserText = userText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trimmedAssistantText = assistantText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !trimmedUserText.isEmpty {
            _ = try await appendMessage(
                conversationID: conversationID,
                role: "user",
                content: trimmedUserText,
                processAfterWrite: false
            )
        }

        if !trimmedAssistantText.isEmpty {
            _ = try await appendMessage(
                conversationID: conversationID,
                role: "assistant",
                content: trimmedAssistantText,
                processAfterWrite: false
            )
        }

        if !trimmedUserText.isEmpty || !trimmedAssistantText.isEmpty {
            try await processConversation(conversationID: conversationID)
        }
    }

    func buildInstructionText(from context: MemoryConversationContextEnvelope) -> String? {
        let summaryText = context.promptContext.summaryText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let memoryLines = context.promptContext.memoryLines.filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        guard !summaryText.isEmpty || !memoryLines.isEmpty else {
            return nil
        }

        var sections: [String] = []
        if !summaryText.isEmpty {
            sections.append("Current conversation summary:\n\(summaryText)")
        }
        if !memoryLines.isEmpty {
            sections.append("Relevant memory:\n\(memoryLines.joined(separator: "\n"))")
        }

        return sections.joined(separator: "\n\n")
    }

    private func appendMessage(
        conversationID: String,
        role: String,
        content: String,
        processAfterWrite: Bool
    ) async throws -> GenericOKEnvelope {
        let endpoint = brokerBaseURL
            .appendingPathComponent("api")
            .appendingPathComponent("chat")
            .appendingPathComponent("conversations")
            .appendingPathComponent(conversationID)
            .appendingPathComponent("messages")

        var request = try authorizedRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "role": role,
            "content": content,
            "process_after_write": processAfterWrite,
        ])

        let (data, response) = try await session.data(for: request)
        return try decode(data: data, response: response)
    }

    private func processConversation(conversationID: String) async throws {
        let endpoint = brokerBaseURL
            .appendingPathComponent("api")
            .appendingPathComponent("chat")
            .appendingPathComponent("conversations")
            .appendingPathComponent(conversationID)
            .appendingPathComponent("process")

        var request = try authorizedRequest(url: endpoint)
        request.httpMethod = "POST"

        let (data, response) = try await session.data(for: request)
        let envelope: GenericOKEnvelope = try decode(data: data, response: response)
        guard envelope.ok else {
            throw MemoryServiceError.invalidResponse
        }
    }

    private func saveSession(_ accountSession: RockyAccountSession) throws {
        let data = try encoder.encode(accountSession)
        guard let encoded = String(data: data, encoding: .utf8) else {
            throw MemoryServiceError.invalidResponse
        }

        KeychainStore.set(encoded, for: accountSessionKeychainKey)
    }

    private func makeDesktopLoginURL(redirectURI: String, state: String) throws -> URL {
        guard var components = URLComponents(
            url: brokerBaseURL.appendingPathComponent("auth").appendingPathComponent("desktop").appendingPathComponent("start"),
            resolvingAgainstBaseURL: false
        ) else {
            throw MemoryServiceError.invalidBrokerURL
        }

        components.queryItems = [
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "state", value: state),
        ]

        guard let url = components.url else {
            throw MemoryServiceError.invalidBrokerURL
        }

        return url
    }

    private func authorizedRequest(url: URL) throws -> URLRequest {
        guard let accountSession = currentSession, !accountSession.accessToken.isEmpty else {
            throw MemoryServiceError.notAuthenticated
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accountSession.accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func callbackValue(named name: String, from url: URL) throws -> String {
        guard
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let value = components.queryItems?.first(where: { $0.name == name })?.value,
            !value.isEmpty
        else {
            throw name == "access_token" ? MemoryServiceError.missingAccessToken : MemoryServiceError.invalidCallbackState
        }

        return value
    }

    private func decode<T: Decodable>(data: Data, response: URLResponse) throws -> T {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MemoryServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let payload = try? decoder.decode(MemoryErrorEnvelope.self, from: data)
            throw MemoryServiceError.serviceError(
                payload?.message ?? payload?.error.replacingOccurrences(of: "_", with: " ") ?? "Rocky couldn't complete the memory request."
            )
        }

        return try decoder.decode(T.self, from: data)
    }
}

private struct MemoryErrorEnvelope: Decodable {
    let error: String
    let message: String?
}

private final class MemoryCallbackServer {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "com.anil.Rocky.memory.callback")
    private let configuredPort: UInt16
    private var callbackContinuation: CheckedContinuation<URL, Error>?
    private var startupContinuation: CheckedContinuation<Void, Error>?

    init() throws {
        var boundListener: NWListener?
        var boundPort: UInt16?

        for candidatePort in 8785...8794 {
            if let port = NWEndpoint.Port(rawValue: UInt16(candidatePort)),
               let listener = try? NWListener(using: .tcp, on: port) {
                boundListener = listener
                boundPort = UInt16(candidatePort)
                break
            }
        }

        guard let listener = boundListener, let boundPort else {
            throw MemoryServiceError.invalidBrokerURL
        }

        self.listener = listener
        self.configuredPort = boundPort
    }

    var redirectURI: String {
        "http://127.0.0.1:\(configuredPort)/rocky/auth/callback"
    }

    func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            startupContinuation = continuation

            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.startupContinuation?.resume()
                    self.startupContinuation = nil
                case .failed(let error):
                    self.startupContinuation?.resume(throwing: error)
                    self.startupContinuation = nil
                default:
                    break
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }

            listener.start(queue: queue)
        }
    }

    func waitForCallback() async throws -> URL {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            callbackContinuation = continuation
        }
    }

    func stop() {
        listener.cancel()
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
            guard let self else { return }

            if let error {
                self.callbackContinuation?.resume(throwing: error)
                self.callbackContinuation = nil
                connection.cancel()
                return
            }

            guard
                let data,
                let request = String(data: data, encoding: .utf8),
                let requestLine = request.components(separatedBy: "\r\n").first
            else {
                self.callbackContinuation?.resume(throwing: MemoryServiceError.invalidCallbackState)
                self.callbackContinuation = nil
                connection.cancel()
                return
            }

            let parts = requestLine.split(separator: " ")
            guard parts.count >= 2 else {
                self.callbackContinuation?.resume(throwing: MemoryServiceError.invalidCallbackState)
                self.callbackContinuation = nil
                connection.cancel()
                return
            }

            let path = String(parts[1])
            guard let url = URL(string: "http://127.0.0.1:\(self.configuredPort)\(path)") else {
                self.callbackContinuation?.resume(throwing: MemoryServiceError.invalidCallbackState)
                self.callbackContinuation = nil
                connection.cancel()
                return
            }

            let callbackError = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "error" })?
                .value

            let body: String
            if let callbackError, !callbackError.isEmpty {
                body = """
                <html><body style="font-family:-apple-system;padding:24px;background:#111;color:#eee;">
                <h2>Rocky memory connection failed</h2>
                <p>\(callbackError.replacingOccurrences(of: "_", with: " "))</p>
                <p>You can close this window and return to Rocky.</p>
                </body></html>
                """
            } else {
                body = """
                <html><body style="font-family:-apple-system;padding:24px;background:#111;color:#eee;">
                <h2>Rocky memory account connected</h2>
                <p>You can close this window and return to Rocky.</p>
                </body></html>
                """
            }

            let response = """
            HTTP/1.1 200 OK\r
            Content-Type: text/html; charset=utf-8\r
            Content-Length: \(body.utf8.count)\r
            Connection: close\r
            \r
            \(body)
            """
            connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
                connection.cancel()
            })

            self.callbackContinuation?.resume(returning: url)
            self.callbackContinuation = nil
        }
    }
}
