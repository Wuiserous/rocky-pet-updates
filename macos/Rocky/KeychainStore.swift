import Foundation
import Security

enum KeychainStore {
    private static let service = "com.anil.Rocky"

    static func string(for key: String) -> String? {
        guard let data = data(for: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String, for key: String) {
        guard let data = value.data(using: .utf8) else { return }
        set(data, for: key)
    }

    static func removeValue(for key: String) {
        let query = baseQuery(for: key)
        SecItemDelete(query as CFDictionary)
    }

    private static func data(for key: String) -> Data? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    private static func set(_ data: Data, for key: String) {
        let query = baseQuery(for: key)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        var insertQuery = query
        insertQuery[kSecValueData as String] = data
        SecItemAdd(insertQuery as CFDictionary, nil)
    }

    private static func baseQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }
}
