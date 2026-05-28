import Foundation

enum PluginConnectionMode: String, Codable {
    case composio
}

struct PluginConnection: Codable, Equatable, Identifiable {
    let connectionMode: PluginConnectionMode
    let provider: PluginProvider
    let composioEntityID: String
    let composioConnectedAccountID: String?
    let composioToolRouterSessionID: String?
    let connectedAt: Date

    var id: String { provider.rawValue }
}

enum PluginConnectionStore {
    private static let defaultsKey = "rocky.plugins.connections"

    static func loadConnections() -> [PluginConnection] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else {
            return []
        }

        return (try? JSONDecoder().decode([PluginConnection].self, from: data)) ?? []
    }

    static func connection(for provider: PluginProvider) -> PluginConnection? {
        loadConnections().first(where: { $0.provider == provider })
    }

    static func save(_ connection: PluginConnection) {
        var connections = loadConnections().filter { $0.provider != connection.provider }
        connections.append(connection)
        persist(connections)
    }

    static func removeConnection(for provider: PluginProvider) {
        let filtered = loadConnections().filter { $0.provider != provider }
        persist(filtered)
    }

    static func removeAllConnections() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    private static func persist(_ connections: [PluginConnection]) {
        guard let data = try? JSONEncoder().encode(connections) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
