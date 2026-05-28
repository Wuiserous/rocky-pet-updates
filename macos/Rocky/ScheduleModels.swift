import Foundation

enum ScheduledItemKind: String, Codable, CaseIterable, Identifiable {
    case task
    case reminder
    case alarm

    var id: String { rawValue }

    var title: String {
        switch self {
        case .task:
            return "Task"
        case .reminder:
            return "Reminder"
        case .alarm:
            return "Alarm"
        }
    }

    var notificationTitle: String {
        switch self {
        case .task:
            return "Rocky task due"
        case .reminder:
            return "Rocky reminder"
        case .alarm:
            return "Rocky alarm"
        }
    }

    var iconName: String {
        switch self {
        case .task:
            return "checklist"
        case .reminder:
            return "bell"
        case .alarm:
            return "alarm"
        }
    }
}

enum ScheduledItemRepeatRule: String, Codable, CaseIterable {
    case none
    case daily
    case weekdays
    case weekly
    case monthly

    var title: String {
        switch self {
        case .none:
            return "Once"
        case .daily:
            return "Daily"
        case .weekdays:
            return "Weekdays"
        case .weekly:
            return "Weekly"
        case .monthly:
            return "Monthly"
        }
    }
}

enum ScheduledItemStatus: String, Codable {
    case pending
    case completed
    case dismissed
    case missed
    case cancelled

    var title: String {
        rawValue.capitalized
    }
}

enum ScheduleNotificationAuthorizationState: String {
    case notDetermined
    case denied
    case authorized

    var title: String {
        switch self {
        case .notDetermined:
            return "Not enabled"
        case .denied:
            return "Denied"
        case .authorized:
            return "Enabled"
        }
    }
}

struct ScheduledItem: Codable, Identifiable, Equatable {
    let id: String
    let deviceID: String
    let title: String
    let kind: ScheduledItemKind
    let scheduledFor: Date
    let timezone: String
    let repeatRule: ScheduledItemRepeatRule
    let intervalMinutes: Int?
    let windowStartTime: String?
    let windowEndTime: String?
    let notes: String?
    let status: ScheduledItemStatus
    let snoozedUntil: Date?
    let lastDeliveredAt: Date?
    let deliveredCount: Int
    let createdAt: Date
    let updatedAt: Date

    var effectiveTriggerDate: Date {
        snoozedUntil ?? scheduledFor
    }

    var isPending: Bool {
        status == .pending
    }

    enum CodingKeys: String, CodingKey {
        case id
        case deviceID = "device_id"
        case title
        case kind
        case scheduledFor = "scheduled_for"
        case timezone
        case repeatRule = "repeat_rule"
        case intervalMinutes = "interval_minutes"
        case windowStartTime = "window_start_time"
        case windowEndTime = "window_end_time"
        case notes
        case status
        case snoozedUntil = "snoozed_until"
        case lastDeliveredAt = "last_delivered_at"
        case deliveredCount = "delivered_count"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct CreateScheduledItemRequest {
    let title: String
    let kind: ScheduledItemKind
    let scheduledFor: Date
    let timezone: String
    let repeatRule: ScheduledItemRepeatRule
    let intervalMinutes: Int?
    let windowStartTime: String?
    let windowEndTime: String?
    let notes: String?
}
