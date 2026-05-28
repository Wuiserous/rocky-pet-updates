import AppKit
import Foundation
import Network

enum PluginConnectionServiceError: LocalizedError {
    case invalidBrokerURL
    case couldNotOpenBrowser
    case invalidCallbackState
    case missingConnectionCode
    case invalidExchangeResponse
    case brokerError(String)

    var errorDescription: String? {
        switch self {
        case .invalidBrokerURL:
            return "Rocky couldn't create the plugin connection URL."
        case .couldNotOpenBrowser:
            return "Rocky couldn't open the browser to connect this plugin."
        case .invalidCallbackState:
            return "Rocky received an invalid plugin callback."
        case .missingConnectionCode:
            return "Rocky didn't receive a connection code from the website."
        case .invalidExchangeResponse:
            return "Rocky couldn't read the connection result from the website."
        case .brokerError(let message):
            return message
        }
    }
}

final class PluginConnectionService {
    private let session: URLSession
    private let brokerBaseURL: URL

    init(
        session: URLSession = .shared,
        brokerBaseURL: URL = URL(string: "https://rocky-web-gules.vercel.app")!
    ) {
        self.session = session
        self.brokerBaseURL = brokerBaseURL
    }

    func connect(provider: PluginProvider) async throws -> PluginConnection {
        let callbackServer = try PluginCallbackServer()
        try await callbackServer.start()
        defer { callbackServer.stop() }

        let state = UUID().uuidString
        let connectURL = try makeConnectURL(
            provider: provider,
            redirectURI: callbackServer.redirectURI,
            state: state
        )

        guard NSWorkspace.shared.open(connectURL) else {
            throw PluginConnectionServiceError.couldNotOpenBrowser
        }

        let callbackURL = try await callbackServer.waitForCallback()
        let callbackState = try callbackValue(named: "state", from: callbackURL)
        guard callbackState == state else {
            throw PluginConnectionServiceError.invalidCallbackState
        }

        let code = try callbackValue(named: "connection_code", from: callbackURL)
        let exchangeToken = try await exchangeConnectionCode(provider: provider, code: code)

        let connection = PluginConnection(
            connectionMode: exchangeToken.connectionMode,
            provider: exchangeToken.provider,
            composioEntityID: exchangeToken.composioEntityID,
            composioConnectedAccountID: exchangeToken.composioConnectedAccountID,
            composioToolRouterSessionID: exchangeToken.composioToolRouterSessionID,
            connectedAt: Date()
        )
        PluginConnectionStore.save(connection)
        return connection
    }

    func disconnect(provider: PluginProvider) {
        PluginConnectionStore.removeConnection(for: provider)
    }

    private func makeConnectURL(provider: PluginProvider, redirectURI: String, state: String) throws -> URL {
        guard var components = URLComponents(
            url: brokerBaseURL.appendingPathComponent("connect").appendingPathComponent(provider.rawValue),
            resolvingAgainstBaseURL: false
        ) else {
            throw PluginConnectionServiceError.invalidBrokerURL
        }

        components.queryItems = [
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "state", value: state),
        ]

        guard let url = components.url else {
            throw PluginConnectionServiceError.invalidBrokerURL
        }

        return url
    }

    private func exchangeConnectionCode(provider: PluginProvider, code: String) async throws -> PluginExchangeToken {
        let endpoint = brokerBaseURL
            .appendingPathComponent("api")
            .appendingPathComponent("connections")
            .appendingPathComponent("exchange")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(ExchangeRequest(provider: provider.rawValue, code: code))

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PluginConnectionServiceError.invalidExchangeResponse
        }

        if !(200..<300).contains(httpResponse.statusCode) {
            let brokerError = try? JSONDecoder().decode(ExchangeErrorResponse.self, from: data)
            throw PluginConnectionServiceError.brokerError(
                brokerError?.error.replacingOccurrences(of: "_", with: " ") ?? "Rocky couldn't finish connecting this plugin."
            )
        }

        let exchangeResponse = try JSONDecoder().decode(ExchangeResponse.self, from: data)
        guard exchangeResponse.ok else {
            throw PluginConnectionServiceError.invalidExchangeResponse
        }

        return exchangeResponse.token
    }

    private func callbackValue(named name: String, from url: URL) throws -> String {
        guard
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let value = components.queryItems?.first(where: { $0.name == name })?.value,
            !value.isEmpty
        else {
            throw name == "connection_code"
                ? PluginConnectionServiceError.missingConnectionCode
                : PluginConnectionServiceError.invalidCallbackState
        }

        return value
    }
}

private struct ExchangeRequest: Encodable {
    let provider: String
    let code: String
}

private struct ExchangeResponse: Decodable {
    let ok: Bool
    let token: PluginExchangeToken
}

private struct ExchangeErrorResponse: Decodable {
    let ok: Bool?
    let error: String
}

private struct PluginExchangeToken: Decodable {
    let connectionMode: PluginConnectionMode
    let provider: PluginProvider
    let composioEntityID: String
    let composioConnectedAccountID: String?
    let composioToolRouterSessionID: String?

    enum CodingKeys: String, CodingKey {
        case connectionMode = "connection_mode"
        case provider
        case composioEntityID = "composio_entity_id"
        case composioConnectedAccountID = "composio_connected_account_id"
        case composioToolRouterSessionID = "composio_tool_router_session_id"
    }
}

private final class PluginCallbackServer {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "com.anil.Rocky.plugin.callback")
    private let configuredPort: UInt16
    private var callbackContinuation: CheckedContinuation<URL, Error>?
    private var startupContinuation: CheckedContinuation<Void, Error>?

    init() throws {
        var boundListener: NWListener?
        var boundPort: UInt16?

        for candidatePort in 8765...8774 {
            if let port = NWEndpoint.Port(rawValue: UInt16(candidatePort)),
               let listener = try? NWListener(using: .tcp, on: port) {
                boundListener = listener
                boundPort = UInt16(candidatePort)
                break
            }
        }

        guard let listener = boundListener, let boundPort else {
            throw PluginConnectionServiceError.invalidBrokerURL
        }

        self.listener = listener
        self.configuredPort = boundPort
    }

    var redirectURI: String {
        "http://127.0.0.1:\(configuredPort)/rocky/oauth/callback"
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
                let pathLine = request.split(separator: "\r\n").first,
                let path = pathLine.split(separator: " ").dropFirst().first,
                let callbackURL = URL(string: "http://127.0.0.1:\(self.configuredPort)\(path)")
            else {
                self.callbackContinuation?.resume(throwing: PluginConnectionServiceError.invalidCallbackState)
                self.callbackContinuation = nil
                connection.cancel()
                return
            }

            self.respond(to: connection)
            self.callbackContinuation?.resume(returning: callbackURL)
            self.callbackContinuation = nil
        }
    }

    private func respond(to connection: NWConnection) {
        let html = """
        <!doctype html>
        <html lang="en">
          <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>Rocky Connected</title>
            <style>
              body { margin: 0; min-height: 100vh; display: grid; place-items: center; background: #0d1018; color: #fff9ef; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
              main { width: min(520px, calc(100% - 32px)); padding: 28px; border-radius: 20px; background: rgba(255,255,255,0.06); border: 1px solid rgba(255,255,255,0.12); box-shadow: 0 24px 72px rgba(0,0,0,0.28); }
              h1 { margin: 0 0 12px; font-size: 32px; }
              p { margin: 0; color: rgba(255,255,255,0.72); line-height: 1.6; }
            </style>
          </head>
          <body>
            <main>
              <h1>Gently connected.</h1>
              <p>Rocky received this plugin connection. You can close this tab and return to the app.</p>
            </main>
          </body>
        </html>
        """

        let response = """
        HTTP/1.1 200 OK\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(html.utf8.count)\r
        Connection: close\r
        \r
        \(html)
        """

        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
