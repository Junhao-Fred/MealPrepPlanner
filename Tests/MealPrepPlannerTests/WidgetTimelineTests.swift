import Foundation
import Testing
@testable import MealPrepPlanner

struct WidgetTimelineTests {
    @Test func mealAndMidnightBoundaries() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Australia/Sydney"))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 9)))
        let meal = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 12)))
        let midnight = try #require(calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)))
        let end = try #require(calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: now)))

        let dates = WidgetTimelineSchedule.dates(
            from: now,
            mealDates: [meal, meal, midnight, now.addingTimeInterval(-60), end.addingTimeInterval(60)],
            calendar: calendar
        )

        #expect(dates == [now, meal, meal.addingTimeInterval(1), midnight, midnight.addingTimeInterval(1), end])
    }

    @Test func emptyScheduleStillCrossesMidnight() throws {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let firstMidnight = try #require(calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)))
        let secondMidnight = try #require(calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: now)))

        #expect(WidgetTimelineSchedule.dates(from: now, mealDates: [], calendar: calendar) == [now, firstMidnight, secondMidnight])
    }

    @Test(arguments: [4, 10]) func daylightSaving(month: Int) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Australia/Sydney"))
        let day = month == 4 ? 5 : 4
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: month, day: day)))
        let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: now))
        let end = try #require(calendar.date(byAdding: .day, value: 2, to: now))

        #expect(WidgetTimelineSchedule.dates(from: now, mealDates: [], calendar: calendar) == [now, tomorrow, end])
        #expect(tomorrow.timeIntervalSince(now) == Double(month == 4 ? 25 : 23) * 3_600)
    }
}
