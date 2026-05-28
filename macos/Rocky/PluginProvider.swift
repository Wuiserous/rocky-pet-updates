import Foundation

enum PluginProvider: String, CaseIterable, Codable, Identifiable {
    case gmail
    case googleSheets = "google_sheets"
    case googleDrive = "google_drive"
    case github
    case linear
    case notion
    case slack
    case youtube

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gmail:
            return "Gmail"
        case .googleSheets:
            return "Google Sheets"
        case .googleDrive:
            return "Google Drive"
        case .github:
            return "GitHub"
        case .linear:
            return "Linear"
        case .notion:
            return "Notion"
        case .slack:
            return "Slack"
        case .youtube:
            return "YouTube"
        }
    }

    var iconName: String {
        switch self {
        case .gmail:
            return "envelope.badge"
        case .googleSheets:
            return "tablecells"
        case .googleDrive:
            return "externaldrive"
        case .github:
            return "chevron.left.forwardslash.chevron.right"
        case .linear:
            return "line.3.horizontal.decrease.circle"
        case .notion:
            return "note.text"
        case .slack:
            return "bubble.left.and.bubble.right"
        case .youtube:
            return "play.rectangle"
        }
    }

    var assetImageName: String {
        switch self {
        case .gmail:
            return "gmail"
        case .googleSheets:
            return "google-sheet"
        case .googleDrive:
            return "gdrive"
        case .github:
            return "github"
        case .linear:
            return "linear"
        case .notion:
            return "notion"
        case .slack:
            return "slack"
        case .youtube:
            return "youtube"
        }
    }

    var shortDescription: String {
        switch self {
        case .gmail:
            return "Summarize unread emails and answer follow-up questions."
        case .googleSheets:
            return "Read spreadsheets and help you reason over sheet data."
        case .googleDrive:
            return "Find files, inspect docs, and pull relevant workspace context."
        case .github:
            return "Check repositories, pull requests, issues, and engineering activity."
        case .linear:
            return "Track tasks, issues, priorities, and product planning updates."
        case .notion:
            return "Search pages, notes, and docs so Rocky can answer from your workspace."
        case .slack:
            return "Review channels, threads, and recent team messages when you ask."
        case .youtube:
            return "Search videos, inspect channels, and summarize fresh YouTube context."
        }
    }

    var privacyNote: String {
        switch self {
        case .gmail:
            return "Rocky reads recent Gmail metadata through the secure website broker."
        case .googleSheets:
            return "Rocky accesses connected spreadsheets only through the website broker."
        case .googleDrive:
            return "Rocky accesses Drive file metadata and allowed documents through the broker."
        case .github:
            return "Rocky uses the broker to access repositories and collaboration data you authorize."
        case .linear:
            return "Rocky reads your connected workspace data through the broker when needed."
        case .notion:
            return "Rocky reads connected pages and databases only through the broker flow."
        case .slack:
            return "Rocky accesses connected channel data through the broker after you approve it."
        case .youtube:
            return "Rocky accesses your connected YouTube data through the website broker only after approval."
        }
    }
}
