import AppKit
import Foundation

enum RockyShortcutAction: String, CaseIterable, Identifiable, Codable {
    case quickType
    case checkGmail
    case openControlCenter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quickType:
            return "Type to Rocky"
        case .checkGmail:
            return "Check Gmail"
        case .openControlCenter:
            return "Open Control Center"
        }
    }

    var subtitle: String {
        switch self {
        case .quickType:
            return "Show or hide the quick input bubble."
        case .checkGmail:
            return "Ask Rocky to summarize your unread Gmail."
        case .openControlCenter:
            return "Open Rocky's settings and plugins window."
        }
    }
}

struct RockyShortcut: Codable, Equatable {
    var key: String
    var command: Bool
    var option: Bool
    var control: Bool
    var shift: Bool

    init(key: String, command: Bool = false, option: Bool = false, control: Bool = false, shift: Bool = false) {
        self.key = key.lowercased()
        self.command = command
        self.option = option
        self.control = control
        self.shift = shift
    }

    var modifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if command { flags.insert(.command) }
        if option { flags.insert(.option) }
        if control { flags.insert(.control) }
        if shift { flags.insert(.shift) }
        return flags
    }

    var displayString: String {
        var parts: [String] = []
        if control { parts.append("^") }
        if option { parts.append("⌥") }
        if shift { parts.append("⇧") }
        if command { parts.append("⌘") }
        parts.append(displayKey)
        return parts.joined()
    }

    var menuKeyEquivalent: String {
        key
    }

    var displayKey: String {
        switch key {
        case ",":
            return ","
        case ".":
            return "."
        case "/":
            return "/"
        case ";":
            return ";"
        default:
            return key.uppercased()
        }
    }

    var isValid: Bool {
        !key.isEmpty && !modifierFlags.isEmpty
    }

    func matches(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let typedCharacter = event.charactersIgnoringModifiers?.lowercased()
        return flags == modifierFlags && typedCharacter == key
    }

    static func from(event: NSEvent) -> RockyShortcut? {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !flags.isEmpty else { return nil }
        guard let key = event.charactersIgnoringModifiers?.lowercased(), key.count == 1 else { return nil }
        return RockyShortcut(
            key: key,
            command: flags.contains(.command),
            option: flags.contains(.option),
            control: flags.contains(.control),
            shift: flags.contains(.shift)
        )
    }
}

struct RockyShortcutPreferences: Codable, Equatable {
    var quickType: RockyShortcut
    var checkGmail: RockyShortcut
    var openControlCenter: RockyShortcut

    static let defaults = RockyShortcutPreferences(
        quickType: RockyShortcut(key: "c", option: true),
        checkGmail: RockyShortcut(key: "g", option: true),
        openControlCenter: RockyShortcut(key: ",", command: true)
    )

    func shortcut(for action: RockyShortcutAction) -> RockyShortcut {
        switch action {
        case .quickType:
            return quickType
        case .checkGmail:
            return checkGmail
        case .openControlCenter:
            return openControlCenter
        }
    }

    mutating func setShortcut(_ shortcut: RockyShortcut, for action: RockyShortcutAction) {
        switch action {
        case .quickType:
            quickType = shortcut
        case .checkGmail:
            checkGmail = shortcut
        case .openControlCenter:
            openControlCenter = shortcut
        }
    }

    var hasDuplicateShortcuts: Bool {
        let shortcuts = RockyShortcutAction.allCases.map { shortcut(for: $0) }
        return Set(shortcuts.map(\.displayString)).count != shortcuts.count
    }
}

extension Notification.Name {
    static let rockyShortcutPreferencesDidChange = Notification.Name("rockyShortcutPreferencesDidChange")
    static let rockyShortcutRecordingDidChange = Notification.Name("rockyShortcutRecordingDidChange")
}
