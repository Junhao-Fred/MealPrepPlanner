//  Created by Junhao Huang on 2026/10/23.

import Foundation
import Testing
@testable import MealPrepPlanner

@Suite("Expiry reminders")
struct ExpiryReminderTests {
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(secondsFromGMT: 0)!
        return result
    }

    /// 22 Oct 2026, 12:00 UTC.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 12))!
    }

    private func day(_ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    @Test("Reminds at 9:00 the day before, or on the day once that has passed; skips past, undated and empty batches")
    func plansReminders() {
        let later = Ingredient(name: "Rice", quantity: 1, unit: "kg", expiryDate: day(25))
        let tomorrow = Ingredient(name: "Milk", quantity: 1, unit: "L", expiryDate: day(23))
        let today = Ingredient(name: "Bread", quantity: 1, unit: "loaf", expiryDate: day(22))
        let undated = Ingredient(name: "Salt", quantity: 1, unit: "kg")
        let empty = Ingredient(name: "Eggs", quantity: 0, unit: "piece", expiryDate: day(26))

        let reminders = ExpiryReminderPlanner.reminders(
            for: [later, tomorrow, today, undated, empty], now: now, calendar: calendar
        )

        #expect(reminders.map(\.title) == ["Milk expires today", "Rice expires tomorrow"])
        #expect(reminders.map(\.fireDate) == [day(23, hour: 9), day(24, hour: 9)])
        #expect(reminders.first?.id.hasPrefix(ExpiryReminderPlanner.identifierPrefix) == true)
    }

    @Test("Batches of one ingredient expiring the same day share a reminder with the combined amount")
    func combinesSameDayBatches() {
        let tomato = Ingredient(name: "Tomato", quantity: 200, unit: "g", expiryDate: day(25))
        let tomatoes = Ingredient(name: "Tomatoes", quantity: 300, unit: "g", expiryDate: day(25, hour: 8))
        let laterTomato = Ingredient(name: "Tomato", quantity: 100, unit: "g", expiryDate: day(27))

        let reminders = ExpiryReminderPlanner.reminders(for: [tomato, tomatoes, laterTomato], now: now, calendar: calendar)

        #expect(reminders.map(\.title) == ["Tomato expires tomorrow", "Tomato expires tomorrow"])
        #expect(reminders.first?.body == "Plan a meal for the 500 g in your pantry.")
        #expect(Set(reminders.map(\.id)).count == 2)
    }

    @Test("At most 60 reminders are planned, soonest first")
    func capsReminders() {
        let ingredients = (0..<80).map { offset in
            Ingredient(name: "Item \(offset)", quantity: 1, unit: "g", expiryDate: day(24).addingTimeInterval(Double(offset) * 86_400))
        }

        let reminders = ExpiryReminderPlanner.reminders(for: ingredients, now: now, calendar: calendar)

        #expect(reminders.count == ExpiryReminderPlanner.limit)
        #expect(reminders.first?.title == "Item 0 expires tomorrow")
    }

    @Test("Writes through the app dependencies reschedule reminders from current stock")
    @MainActor
    func dependenciesRescheduleAfterWrites() async throws {
        let scheduler = RecordingReminderScheduler()
        let withReminders = AppDependencies(
            repository: InMemoryMealRepository(),
            makeSnapshotRefresher: {
                WidgetSnapshotRefresher(repository: $0, store: WidgetSnapshotStore(suiteName: "ExpiryReminderTests"), reloadTimelines: {})
            },
            reminderScheduler: scheduler
        )

        try await withReminders.repository.saveIngredient(
            Ingredient(name: "Milk", quantity: 1, unit: "L", expiryDate: Date().addingTimeInterval(5 * 86_400))
        )
        await withReminders.refreshExpiryReminders()

        let latest = await scheduler.latest
        #expect(latest.map(\.title) == ["Milk expires tomorrow"])
    }
}

private actor RecordingReminderScheduler: ExpiryReminderScheduling {
    private(set) var latest: [ExpiryReminder] = []

    func replace(with reminders: [ExpiryReminder]) async {
        latest = reminders
    }
}
