import Foundation

enum UserProfileSettings {
    private static let userNameDefaultsKey = "rocky.user.name"
    private static let idleSleepDelayDefaultsKey = "rocky.movement.idleSleepDelaySeconds"
    private static let shortcutPreferencesDefaultsKey = "rocky.shortcuts.preferences"
    private static let defaultLinearTeamDefaultsKey = "rocky.linear.defaultTeam"
    private static let defaultIdleSleepDelaySeconds = 90

    static var userName: String {
        UserDefaults.standard.string(forKey: userNameDefaultsKey) ?? ""
    }

    static var idleSleepDelaySeconds: Int {
        let storedValue = UserDefaults.standard.integer(forKey: idleSleepDelayDefaultsKey)
        return storedValue > 0 ? storedValue : defaultIdleSleepDelaySeconds
    }

    static var shortcutPreferences: RockyShortcutPreferences {
        guard
            let data = UserDefaults.standard.data(forKey: shortcutPreferencesDefaultsKey),
            let decoded = try? JSONDecoder().decode(RockyShortcutPreferences.self, from: data)
        else {
            return .defaults
        }

        return decoded
    }

    static var defaultLinearTeam: LinearTeamPreference? {
        guard
            let data = UserDefaults.standard.data(forKey: defaultLinearTeamDefaultsKey),
            let decoded = try? JSONDecoder().decode(LinearTeamPreference.self, from: data)
        else {
            return nil
        }

        return decoded
    }

    static func setUserName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(trimmed, forKey: userNameDefaultsKey)
    }

    static func setIdleSleepDelaySeconds(_ seconds: Int) {
        let sanitized = max(1, seconds)
        UserDefaults.standard.set(sanitized, forKey: idleSleepDelayDefaultsKey)
    }

    static func setShortcutPreferences(_ preferences: RockyShortcutPreferences) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        UserDefaults.standard.set(data, forKey: shortcutPreferencesDefaultsKey)
        NotificationCenter.default.post(name: .rockyShortcutPreferencesDidChange, object: nil)
    }

    static func setDefaultLinearTeam(_ team: LinearTeamPreference?) {
        if let team, let data = try? JSONEncoder().encode(team) {
            UserDefaults.standard.set(data, forKey: defaultLinearTeamDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: defaultLinearTeamDefaultsKey)
        }
    }
}
