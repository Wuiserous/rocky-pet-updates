import Foundation

struct MemorySettingsRecord: Codable, Equatable {
    let userID: String
    let memoryEnabled: Bool
    let profileMemoryEnabled: Bool
    let projectMemoryEnabled: Bool
    let preferenceMemoryEnabled: Bool
    let sensitiveMemoryEnabled: Bool
    let autoExtractEnabled: Bool
    let retentionDays: Int?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case memoryEnabled = "memory_enabled"
        case profileMemoryEnabled = "profile_memory_enabled"
        case projectMemoryEnabled = "project_memory_enabled"
        case preferenceMemoryEnabled = "preference_memory_enabled"
        case sensitiveMemoryEnabled = "sensitive_memory_enabled"
        case autoExtractEnabled = "auto_extract_enabled"
        case retentionDays = "retention_days"
    }

    static let defaults = MemorySettingsRecord(
        userID: "",
        memoryEnabled: false,
        profileMemoryEnabled: true,
        projectMemoryEnabled: true,
        preferenceMemoryEnabled: true,
        sensitiveMemoryEnabled: false,
        autoExtractEnabled: false,
        retentionDays: nil
    )
}

struct MemorySettingsEnvelope: Decodable {
    let ok: Bool
    let settings: MemorySettingsRecord
}
