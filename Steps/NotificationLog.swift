//
//  NotificationLog.swift
//  Steps
//
//  A persistent history of every notification the app posts. `StepNotifier`
//  records each alert here at its single posting choke point, so the in-app
//  Inbox (see InboxView) mirrors exactly what was — or would have been —
//  delivered as a banner, even for alerts fired during background wake-ups.
//
//  Stored in the App Group so background-process writes survive and the same
//  log is readable wherever SettingsStore is. Capped to a recent window; an
//  "unread" marker tracks what the user has seen since last opening the Inbox.
//

import Foundation

/// One logged notification: the exact title/body that was posted, and when.
struct InboxMessage: Codable, Identifiable, Equatable {
    let id: UUID
    let title: String
    let body: String
    let date: Date

    init(id: UUID = UUID(), title: String, body: String, date: Date = Date()) {
        self.id = id
        self.title = title
        self.body = body
        self.date = date
    }
}

/// Append-only (capped) history of posted notifications, persisted in the App
/// Group. Newest first.
enum NotificationLog {
    private static let key = "notificationLog"
    private static let lastSeenKey = "notificationLogLastSeen"
    private static let maxEntries = 100

    private static var defaults: UserDefaults { SettingsStore.defaults }

    /// Record a posted notification. Called from `StepNotifier.post`.
    static func record(title: String, body: String, date: Date = Date()) {
        var entries = all()
        entries.insert(InboxMessage(title: title, body: body, date: date), at: 0)
        if entries.count > maxEntries { entries = Array(entries.prefix(maxEntries)) }
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: key)
        }
    }

    /// The full history, newest first.
    static func all() -> [InboxMessage] {
        guard let data = defaults.data(forKey: key),
              let entries = try? JSONDecoder().decode([InboxMessage].self, from: data) else { return [] }
        return entries
    }

    /// How many messages arrived since the user last opened the Inbox — drives
    /// the unread badge on the Inbox button.
    static var unreadCount: Int {
        let lastSeen = (defaults.object(forKey: lastSeenKey) as? Double)
            .map { Date(timeIntervalSince1970: $0) } ?? .distantPast
        return all().filter { $0.date > lastSeen }.count
    }

    /// Mark everything currently logged as seen (call when the Inbox opens).
    static func markAllSeen() {
        defaults.set(Date().timeIntervalSince1970, forKey: lastSeenKey)
    }

    /// Wipe the history (and reset the unread marker).
    static func clear() {
        defaults.removeObject(forKey: key)
        defaults.removeObject(forKey: lastSeenKey)
    }
}
