import AppKit
import Foundation

enum GeminiSettings {
    private static let apiKeyDefaultsKey = "gemini.apiKey"

    static var apiKey: String? {
        let stored = UserDefaults.standard.string(forKey: apiKeyDefaultsKey)
        if let stored, !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return stored
        }

        let environmentKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"]
        if let environmentKey, !environmentKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return environmentKey
        }

        return nil
    }

    @MainActor
    static func requestAPIKeyIfNeeded() -> String? {
        if let apiKey {
            return apiKey
        }

        let alert = NSAlert()
        alert.messageText = "Gemini API Key"
        alert.informativeText = "Paste your Gemini API key to connect Rocky's brain."
        alert.addButton(withTitle: "Connect")
        alert.addButton(withTitle: "Cancel")

        let input = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        input.placeholderString = "AIza..."
        alert.accessoryView = input

        guard alert.runModal() == .alertFirstButtonReturn else {
            return nil
        }

        let value = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return nil
        }

        UserDefaults.standard.set(value, forKey: apiKeyDefaultsKey)
        return value
    }

    static func setAPIKey(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: apiKeyDefaultsKey)
        } else {
            UserDefaults.standard.set(trimmed, forKey: apiKeyDefaultsKey)
        }
    }

    static func forgetAPIKey() {
        UserDefaults.standard.removeObject(forKey: apiKeyDefaultsKey)
    }
}
