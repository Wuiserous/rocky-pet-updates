import Foundation
import UserNotifications

enum ScheduleServiceError: LocalizedError {
    case invalidResponse
    case serviceError(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Rocky couldn't read the schedule service response."
        case .serviceError(let message):
            return message
        }
    }
}

final class ScheduleService {
    private let session: URLSession
    private let brokerBaseURL: URL
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let notificationCenter: UNUserNotificationCenter
    private let deviceIDDefaultsKey = "rocky.schedule.deviceID"
    private let notificationCategoryIdentifier = "ROCKY_SCHEDULE_ACTIONS"
    private let notificationIdentifierPrefix = "rocky.schedule."
    private let scheduleHorizon: TimeInterval = 60 * 60 * 36

    init(
        session: URLSession = .shared,
        brokerBaseURL: URL = URL(string: "https://rocky-web-gules.vercel.app")!,
        notificationCenter: UNUserNotificationCenter = .current()
    ) {
        self.session = session
        self.brokerBaseURL = brokerBaseURL
        self.notificationCenter = notificationCenter

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        registerNotificationCategories()
    }

    var deviceID: String {
        if let stored = UserDefaults.standard.string(forKey: deviceIDDefaultsKey), !stored.isEmpty {
            return stored
        }

        let generated = UUID().uuidString.lowercased()
        UserDefaults.standard.set(generated, forKey: deviceIDDefaultsKey)
        return generated
    }

    func fetchScheduledItems() async throws -> [ScheduledItem] {
        let endpoint = brokerBaseURL
            .appendingPathComponent("api")
            .appendingPathComponent("schedule")
            .appendingPathComponent("items")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue(deviceID, forHTTPHeaderField: "x-rocky-device-id")

        let (data, response) = try await session.data(for: request)
        return try decodeItemsResponse(data: data, response: response)
    }

    func createScheduledItem(_ input: CreateScheduledItemRequest) async throws -> ScheduledItem {
        let endpoint = brokerBaseURL
            .appendingPathComponent("api")
            .appendingPathComponent("schedule")
            .appendingPathComponent("items")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(deviceID, forHTTPHeaderField: "x-rocky-device-id")
        let payload: [String: Any] = [
            "device_id": deviceID,
            "title": input.title,
            "kind": input.kind.rawValue,
            "scheduled_for": isoFormatter.string(from: input.scheduledFor),
            "timezone": input.timezone,
            "repeat_rule": input.repeatRule.rawValue,
            "interval_minutes": input.intervalMinutes ?? NSNull(),
            "window_start_time": input.windowStartTime ?? NSNull(),
            "window_end_time": input.windowEndTime ?? NSNull(),
            "notes": input.notes ?? NSNull()
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        let envelope = try decodeItemEnvelope(data: data, response: response)
        return envelope.item
    }

    func completeScheduledItem(id: String) async throws -> ScheduledItem {
        try await updateScheduledItem(
            id: id,
            payload: [
                "device_id": deviceID,
                "status": ScheduledItemStatus.completed.rawValue,
                "snoozed_until": NSNull()
            ]
        )
    }

    func snoozeScheduledItem(id: String, minutes: Int) async throws -> ScheduledItem {
        let snoozedUntil = Date().addingTimeInterval(TimeInterval(max(1, minutes) * 60))
        return try await updateScheduledItem(
            id: id,
            payload: [
                "device_id": deviceID,
                "status": ScheduledItemStatus.pending.rawValue,
                "snoozed_until": isoFormatter.string(from: snoozedUntil)
            ]
        )
    }

    func markScheduledItemDelivered(_ item: ScheduledItem) async throws -> ScheduledItem {
        try await updateScheduledItem(
            id: item.id,
            payload: [
                "device_id": deviceID,
                "last_delivered_at": isoFormatter.string(from: Date()),
                "delivered_count": item.deliveredCount + 1
            ]
        )
    }

    func deleteScheduledItem(id: String) async throws {
        let endpoint = brokerBaseURL
            .appendingPathComponent("api")
            .appendingPathComponent("schedule")
            .appendingPathComponent("items")
            .appendingPathComponent(id)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "DELETE"
        request.setValue(deviceID, forHTTPHeaderField: "x-rocky-device-id")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ScheduleServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let errorPayload = try? decoder.decode(ScheduleErrorEnvelope.self, from: data)
            throw ScheduleServiceError.serviceError(
                errorPayload?.message ?? "Rocky couldn't delete that scheduled item."
            )
        }
    }

    func notificationAuthorizationStatus() async -> ScheduleNotificationAuthorizationState {
        let settings = await notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .ephemeral, .provisional:
            return .authorized
        case .denied:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .notDetermined
        }
    }

    func requestNotificationAuthorization() async -> ScheduleNotificationAuthorizationState {
        _ = try? await notificationCenter.requestAuthorization(options: [.alert, .badge, .sound])
        return await notificationAuthorizationStatus()
    }

    func synchronizeNotifications(for items: [ScheduledItem]) async {
        await clearManagedNotifications()

        for item in items where item.isPending {
            await scheduleNotifications(for: item)
        }
    }

    func notificationItemID(from userInfo: [AnyHashable: Any]) -> String? {
        userInfo["item_id"] as? String
    }

    func dueOccurrences(for item: ScheduledItem, since: Date, until: Date) -> [Date] {
        occurrences(for: item, between: since, and: until)
    }

    private func updateScheduledItem(id: String, payload: [String: Any]) async throws -> ScheduledItem {
        let endpoint = brokerBaseURL
            .appendingPathComponent("api")
            .appendingPathComponent("schedule")
            .appendingPathComponent("items")
            .appendingPathComponent(id)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(deviceID, forHTTPHeaderField: "x-rocky-device-id")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        let envelope = try decodeItemEnvelope(data: data, response: response)
        return envelope.item
    }

    private func decodeItemsResponse(data: Data, response: URLResponse) throws -> [ScheduledItem] {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ScheduleServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let errorPayload = try? decoder.decode(ScheduleErrorEnvelope.self, from: data)
            throw ScheduleServiceError.serviceError(
                errorPayload?.message ?? "Rocky couldn't load scheduled items."
            )
        }

        let envelope = try decoder.decode(ScheduleItemsEnvelope.self, from: data)
        guard envelope.ok else {
            throw ScheduleServiceError.invalidResponse
        }

        return envelope.items
    }

    private func decodeItemEnvelope(data: Data, response: URLResponse) throws -> ScheduleItemEnvelope {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ScheduleServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let errorPayload = try? decoder.decode(ScheduleErrorEnvelope.self, from: data)
            throw ScheduleServiceError.serviceError(
                errorPayload?.message ?? "Rocky couldn't update the scheduled item."
            )
        }

        let envelope = try decoder.decode(ScheduleItemEnvelope.self, from: data)
        guard envelope.ok else {
            throw ScheduleServiceError.invalidResponse
        }

        return envelope
    }

    private func registerNotificationCategories() {
        let complete = UNNotificationAction(
            identifier: "ROCKY_SCHEDULE_COMPLETE",
            title: "Complete"
        )
        let snooze = UNNotificationAction(
            identifier: "ROCKY_SCHEDULE_SNOOZE_10",
            title: "Snooze 10m"
        )
        let category = UNNotificationCategory(
            identifier: notificationCategoryIdentifier,
            actions: [complete, snooze],
            intentIdentifiers: [],
            options: []
        )

        notificationCenter.setNotificationCategories([category])
    }

    private func clearManagedNotifications() async {
        let pending = await pendingNotificationRequests()
        let pendingIDs = pending.map(\.identifier).filter { $0.hasPrefix(notificationIdentifierPrefix) }
        let delivered = await deliveredNotifications()
        let deliveredIDs = delivered.map(\.request.identifier).filter { $0.hasPrefix(notificationIdentifierPrefix) }
        notificationCenter.removePendingNotificationRequests(withIdentifiers: pendingIDs)
        notificationCenter.removeDeliveredNotifications(withIdentifiers: deliveredIDs)
    }

    private func scheduleNotifications(for item: ScheduledItem) async {
        let now = Date()
        let horizonEnd = now.addingTimeInterval(scheduleHorizon)
        let upcomingOccurrences = occurrences(for: item, between: now, and: horizonEnd)

        for occurrence in upcomingOccurrences where occurrence > now {
            guard let trigger = oneOffTrigger(for: occurrence) else { continue }
            let identifier = notificationIdentifier(for: item, occurrence: occurrence)
            await addRequest(makeRequest(for: item, occurrence: occurrence, identifier: identifier, trigger: trigger))
        }
    }

    private func oneOffTrigger(for date: Date) -> UNNotificationTrigger? {
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    }

    private func notificationIdentifier(for item: ScheduledItem, occurrence: Date) -> String {
        let timestamp = Int(occurrence.timeIntervalSince1970)
        return "\(notificationIdentifierPrefix)\(item.id).\(timestamp)"
    }

    private func makeRequest(
        for item: ScheduledItem,
        occurrence: Date,
        identifier: String,
        trigger: UNNotificationTrigger
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = item.kind.notificationTitle
        content.body = item.title
        if let notes = item.notes, !notes.isEmpty {
            content.subtitle = notes
        }
        content.sound = .default
        content.categoryIdentifier = notificationCategoryIdentifier
        content.userInfo = [
            "item_id": item.id,
            "kind": item.kind.rawValue,
            "occurrence_at": isoFormatter.string(from: occurrence)
        ]
        return UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
    }

    private func occurrences(for item: ScheduledItem, between start: Date, and end: Date) -> [Date] {
        guard start <= end else { return [] }

        if let intervalMinutes = item.intervalMinutes,
           intervalMinutes > 0,
           let windowStartTime = item.windowStartTime,
           let windowEndTime = item.windowEndTime,
           let windowStartMinutes = minutesSinceMidnight(from: windowStartTime),
           let windowEndMinutes = minutesSinceMidnight(from: windowEndTime) {
            return intervalOccurrences(
                for: item,
                intervalMinutes: intervalMinutes,
                windowStartMinutes: windowStartMinutes,
                windowEndMinutes: windowEndMinutes,
                between: start,
                and: end
            )
        }

        return singleOccurrences(for: item, between: start, and: end)
    }

    private func singleOccurrences(for item: ScheduledItem, between start: Date, and end: Date) -> [Date] {
        let calendar = Calendar.current
        let anchor = item.effectiveTriggerDate

        switch item.repeatRule {
        case .none:
            return (anchor >= start && anchor <= end) ? [anchor] : []
        case .daily, .weekdays, .weekly, .monthly:
            let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: anchor)
            var occurrences: [Date] = []
            var cursor = calendar.startOfDay(for: start.addingTimeInterval(-86400))
            let finalDay = calendar.startOfDay(for: end)

            while cursor <= finalDay {
                if matchesRepeatRule(item, on: cursor) {
                    var components = calendar.dateComponents([.year, .month, .day], from: cursor)
                    components.hour = timeComponents.hour
                    components.minute = timeComponents.minute
                    components.second = timeComponents.second ?? 0
                    if let date = calendar.date(from: components), date >= start && date <= end {
                        occurrences.append(date)
                    }
                }
                guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
            }

            return occurrences.sorted()
        }
    }

    private func intervalOccurrences(
        for item: ScheduledItem,
        intervalMinutes: Int,
        windowStartMinutes: Int,
        windowEndMinutes: Int,
        between start: Date,
        and end: Date
    ) -> [Date] {
        let calendar = Calendar.current
        var occurrences: [Date] = []
        var cursor = calendar.startOfDay(for: start.addingTimeInterval(-86400))
        let finalDay = calendar.startOfDay(for: end)

        while cursor <= finalDay {
            if matchesRepeatRule(item, on: cursor) {
                var minuteOffset = windowStartMinutes
                while minuteOffset <= windowEndMinutes {
                    let occurrence = cursor.addingTimeInterval(TimeInterval(minuteOffset * 60))
                    if occurrence >= start && occurrence <= end {
                        occurrences.append(occurrence)
                    }
                    minuteOffset += intervalMinutes
                }
            }

            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        return occurrences.sorted()
    }

    private func matchesRepeatRule(_ item: ScheduledItem, on day: Date) -> Bool {
        let calendar = Calendar.current
        let anchor = item.scheduledFor
        let weekday = calendar.component(.weekday, from: day)
        switch item.repeatRule {
        case .none:
            return calendar.isDate(day, inSameDayAs: anchor)
        case .daily:
            return true
        case .weekdays:
            return (2...6).contains(weekday)
        case .weekly:
            return weekday == calendar.component(.weekday, from: anchor)
        case .monthly:
            return calendar.component(.day, from: day) == calendar.component(.day, from: anchor)
        }
    }

    private func minutesSinceMidnight(from value: String) -> Int? {
        let parts = value.split(separator: ":")
        guard parts.count == 2,
              let hours = Int(parts[0]),
              let minutes = Int(parts[1]),
              (0...23).contains(hours),
              (0...59).contains(minutes) else {
            return nil
        }

        return hours * 60 + minutes
    }

    private func addRequest(_ request: UNNotificationRequest) async {
        try? await notificationCenter.add(request)
    }

    private func pendingNotificationRequests() async -> [UNNotificationRequest] {
        await withCheckedContinuation { continuation in
            notificationCenter.getPendingNotificationRequests { continuation.resume(returning: $0) }
        }
    }

    private func deliveredNotifications() async -> [UNNotification] {
        await withCheckedContinuation { continuation in
            notificationCenter.getDeliveredNotifications { continuation.resume(returning: $0) }
        }
    }

    private func notificationSettings() async -> UNNotificationSettings {
        await withCheckedContinuation { continuation in
            notificationCenter.getNotificationSettings { continuation.resume(returning: $0) }
        }
    }

    private var isoFormatter: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }
}

private struct ScheduleItemsEnvelope: Decodable {
    let ok: Bool
    let items: [ScheduledItem]
}

private struct ScheduleItemEnvelope: Decodable {
    let ok: Bool
    let item: ScheduledItem
}

private struct ScheduleErrorEnvelope: Decodable {
    let ok: Bool?
    let error: String?
    let message: String?
}
