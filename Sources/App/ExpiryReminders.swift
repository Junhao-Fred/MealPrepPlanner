//  Created by Junhao Huang on 2026/10/23.

import Foundation
import OSLog
import UserNotifications

/// A local notification for a pantry batch that is about to expire.
struct ExpiryReminder: Equatable, Sendable {
    let id: String
    let title: String
    let body: String
    let fireDate: Date
}

enum ExpiryReminderPlanner {
    static let identifierPrefix = "expiry-"
    /// iOS keeps at most 64 pending notifications per app.
    static let limit = 60
    static let hour = 9

    /// Reminds at 9:00 the day before batches expire, or at 9:00 on the day itself once the day before has passed.
    /// Batches of the same ingredient expiring on the same day share one reminder with their combined amount.
    static func reminders(for ingredients: [Ingredient], now: Date, calendar: Calendar) -> [ExpiryReminder] {
        let dated = ingredients.filter { $0.isAvailable && $0.expiryDate != nil }
        let byDay = Dictionary(grouping: dated) { ingredient in
            ExpiryDay(
                key: IngredientMatching.key(name: ingredient.name, unit: ingredient.unit),
                day: calendar.startOfDay(for: ingredient.expiryDate ?? now)
            )
        }
        let reminders = byDay.compactMap { expiryDay, batches -> ExpiryReminder? in
            guard let group = PantryItemGroup.group(batches).first,
                  let expiryMorning = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: expiryDay.day),
                  let dayBefore = calendar.date(byAdding: .day, value: -1, to: expiryMorning) else { return nil }
            let id = "\(identifierPrefix)\(expiryDay.key.name)|\(expiryDay.key.unit)|\(Int(expiryDay.day.timeIntervalSince1970))"
            let amount = "\(group.quantity.formatted()) \(group.unit)"
            if dayBefore > now {
                return ExpiryReminder(id: id, title: "\(group.name) expires tomorrow",
                                      body: "Plan a meal for the \(amount) in your pantry.", fireDate: dayBefore)
            }
            if expiryMorning > now {
                return ExpiryReminder(id: id, title: "\(group.name) expires today",
                                      body: "Use the \(amount) in your pantry today.", fireDate: expiryMorning)
            }
            return nil
        }
        return Array(reminders.sorted { ($0.fireDate, $0.id) < ($1.fireDate, $1.id) }.prefix(limit))
    }

    private struct ExpiryDay: Hashable {
        let key: IngredientMatching.Key
        let day: Date
    }
}

/// Replaces the app's pending expiry reminders with a new set.
protocol ExpiryReminderScheduling: Sendable {
    func replace(with reminders: [ExpiryReminder]) async
}

/// Schedules reminders as local notifications. Asks for permission the first time there is something to remind.
struct NotificationExpiryReminderScheduler: ExpiryReminderScheduling {
    func replace(with reminders: [ExpiryReminder]) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(
            withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(ExpiryReminderPlanner.identifierPrefix) }
        )
        guard !reminders.isEmpty else { return }

        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            status = await center.notificationSettings().authorizationStatus
        }
        guard status == .authorized || status == .provisional else { return }

        for reminder in reminders {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger))
        }
    }
}

/// Rebuilds reminders from current pantry stock. Refreshes run one after another, so the newest stock always wins.
actor ExpiryReminderRefresher {
    private static let logger = Logger(subsystem: "com.manbo.MealPrepPlanner", category: "ExpiryReminders")

    private let repository: any MealPlanningRepository
    private let scheduler: any ExpiryReminderScheduling
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private var latest: Task<Void, Never>?

    init(
        repository: any MealPlanningRepository,
        scheduler: any ExpiryReminderScheduling,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.repository = repository
        self.scheduler = scheduler
        self.calendar = calendar
        self.now = now
    }

    func refresh() async {
        let previous = latest
        let task = Task {
            await previous?.value
            await self.rebuild()
        }
        latest = task
        await task.value
    }

    private func rebuild() async {
        do {
            let ingredients = try await repository.fetchAvailableIngredients()
            await scheduler.replace(with: ExpiryReminderPlanner.reminders(for: ingredients, now: now(), calendar: calendar))
        } catch {
            Self.logger.error("Expiry reminder refresh failed: \(String(describing: error), privacy: .public)")
        }
    }
}
