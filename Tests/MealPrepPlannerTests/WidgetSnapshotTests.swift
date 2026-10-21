//  Created by Junhao Huang on 2026/10/19.

import Foundation
import Testing
@testable import MealPrepPlanner

/// Fixed UTC clock and throwaway App Group defaults for widget tests.
enum WidgetFixtures {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// 2026-10-19 10:00 UTC.
    static let now = date(day: 0, hour: 10)

    static func date(day: Int, hour: Int = 0) -> Date {
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 19))!
        return calendar.date(byAdding: DateComponents(day: day, hour: hour), to: start)!
    }

    static func meal(_ name: String, at date: Date) -> MealWidgetSnapshot.Meal {
        MealWidgetSnapshot.Meal(id: UUID(), name: name, mealType: "Dinner", scheduledDate: date)
    }

    static func ingredient(_ name: String, expiring date: Date) -> MealWidgetSnapshot.ExpiringIngredient {
        MealWidgetSnapshot.ExpiringIngredient(id: UUID(), name: name, expiryDate: date)
    }
}

struct TemporaryDefaults {
    let suiteName = "MealPrepPlannerTests.\(UUID().uuidString)"

    var store: WidgetSnapshotStore { WidgetSnapshotStore(suiteName: suiteName) }

    func write(_ data: Data) {
        UserDefaults(suiteName: suiteName)?.set(data, forKey: AppGroupConfiguration.snapshotKey)
    }

    func remove() {
        UserDefaults().removePersistentDomain(forName: suiteName)
    }
}

struct WidgetSnapshotTests {
    private let calendar = WidgetFixtures.calendar

    @Test("Next meal and today's remaining meals are worked out at display time, including after midnight")
    func mealsAreComputedAtDisplayTime() {
        let breakfast = WidgetFixtures.meal("Oats", at: WidgetFixtures.date(day: 0, hour: 8))
        let dinner = WidgetFixtures.meal("Pasta", at: WidgetFixtures.date(day: 0, hour: 19))
        let tomorrow = WidgetFixtures.meal("Curry", at: WidgetFixtures.date(day: 1, hour: 12))
        let snapshot = MealWidgetSnapshot(
            generatedAt: WidgetFixtures.date(day: 0, hour: 7),
            meals: [breakfast, dinner, tomorrow],
            ingredients: []
        )

        #expect(snapshot.nextMeal(at: WidgetFixtures.now) == dinner)
        #expect(snapshot.remainingMealsToday(at: WidgetFixtures.now, calendar: calendar) == [dinner])

        let afterMidnight = WidgetFixtures.date(day: 1, hour: 1)
        #expect(snapshot.nextMeal(at: afterMidnight) == tomorrow)
        #expect(snapshot.remainingMealsToday(at: afterMidnight, calendar: calendar) == [tomorrow])
    }

    @Test("Use soon covers [today, today + 3 days) and moves with the display day")
    func useSoonWindow() {
        let today = WidgetFixtures.ingredient("Milk", expiring: WidgetFixtures.date(day: 0, hour: 23))
        let dayTwo = WidgetFixtures.ingredient("Spinach", expiring: WidgetFixtures.date(day: 2))
        let dayThree = WidgetFixtures.ingredient("Eggs", expiring: WidgetFixtures.date(day: 3))
        let snapshot = MealWidgetSnapshot(
            generatedAt: WidgetFixtures.now,
            meals: [],
            ingredients: [today, dayTwo, dayThree]
        )

        #expect(snapshot.useSoonIngredients(at: WidgetFixtures.now, calendar: calendar) == [today, dayTwo])
        #expect(snapshot.useSoonIngredients(at: WidgetFixtures.date(day: 1, hour: 9), calendar: calendar) == [dayTwo, dayThree])
    }

    @Test("Content comparison ignores when the snapshot was generated")
    func sameContentIgnoresGeneratedAt() {
        let meal = WidgetFixtures.meal("Soup", at: WidgetFixtures.date(day: 0, hour: 18))
        let first = MealWidgetSnapshot(generatedAt: WidgetFixtures.now, meals: [meal], ingredients: [])
        var second = first
        second.generatedAt = WidgetFixtures.date(day: 0, hour: 11)

        #expect(first.hasSameContent(as: second))
        second.meals = []
        #expect(!second.hasSameContent(as: first))
    }

    @Test("The store round-trips a snapshot through App Group defaults")
    func storeRoundTrip() throws {
        let temporary = TemporaryDefaults()
        defer { temporary.remove() }
        let snapshot = MealWidgetSnapshot(
            generatedAt: WidgetFixtures.now,
            meals: [WidgetFixtures.meal("Soup", at: WidgetFixtures.date(day: 0, hour: 18))],
            ingredients: [WidgetFixtures.ingredient("Milk", expiring: WidgetFixtures.date(day: 1))]
        )

        #expect(temporary.store.load() == nil)
        try temporary.store.save(snapshot)
        #expect(temporary.store.load() == snapshot)
    }

    @Test("Snapshots from another schema version or unreadable data load as nil")
    func incompatibleDataLoadsAsNil() throws {
        let temporary = TemporaryDefaults()
        defer { temporary.remove() }
        var future = MealWidgetSnapshot(generatedAt: WidgetFixtures.now, meals: [], ingredients: [])
        future.schemaVersion = MealWidgetSnapshot.currentSchemaVersion + 1

        temporary.write(try JSONEncoder().encode(future))
        #expect(temporary.store.load() == nil)

        temporary.write(Data("not json".utf8))
        #expect(temporary.store.load() == nil)
    }
}
