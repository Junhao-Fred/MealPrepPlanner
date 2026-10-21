//  Created by Mingchen Liang on 2026/10/21.

import Foundation
import Testing
@testable import MealPrepPlanner

@MainActor
@Suite("Meal plan display and date selection")
struct MealPlanViewModelTests {
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(secondsFromGMT: 0)!
        return result
    }

    private var today: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 21))!
    }

    @Test("Meals group by day in time order, preserving prepared state and the seven-day boundary")
    func groupsMealsByDate() async {
        let first = entry(at: today)
        let prepared = entry(at: today.addingTimeInterval(3_600), prepared: true)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let later = entry(at: tomorrow)
        let excluded = entry(at: calendar.date(byAdding: .day, value: 7, to: today)!)
        let repository = InMemoryMealRepository(entries: [excluded, later, prepared, first])
        let model = makeModel(repository)

        await model.load()

        #expect(model.days == [MealPlanDay(date: today, entries: [first, prepared]),
                              MealPlanDay(date: tomorrow, entries: [later])])
        #expect(model.hasLoaded)
        #expect(!model.isLoading)
        #expect(model.errorMessage == nil)
        let writes = await repository.writeCount
        #expect(writes == 0)
    }

    @Test("No meals produce a successfully loaded empty state")
    func emptyPlan() async {
        let model = makeModel(InMemoryMealRepository())

        await model.load()

        #expect(model.days.isEmpty)
        #expect(model.hasLoaded)
        #expect(!model.isLoading)
        #expect(model.errorMessage == nil)
    }

    @Test("Initial read failures can retry; later failures retain the current range's meals")
    func retriesAndPreservesLoadedData() async {
        let meal = entry(at: today)
        let repository = InMemoryMealRepository(entries: [meal])
        let model = makeModel(repository)
        await repository.fail(.read, with: .readFailed)

        await model.load()
        #expect(!model.hasLoaded)
        #expect(model.days.isEmpty)
        #expect(model.errorMessage != nil)
        #expect(!model.isLoading)

        await repository.clearFailures()
        await model.load()
        let expected = [MealPlanDay(date: today, entries: [meal])]
        #expect(model.days == expected)
        #expect(model.errorMessage == nil)

        await repository.fail(.read, with: .storeUnavailable)
        await model.load()
        #expect(model.days == expected)
        #expect(model.hasLoaded)
        #expect(model.errorMessage != nil)
        #expect(!model.isLoading)
    }

    @Test("Changing dates clears old results even when the new range cannot load")
    func failedRangeChangeDoesNotShowOldMeals() async {
        let repository = InMemoryMealRepository(entries: [entry(at: today)])
        let model = makeModel(repository)
        await model.load()
        await repository.fail(.read, with: .readFailed)
        let next = calendar.date(byAdding: .day, value: 7, to: today)!

        await model.showRange(starting: next.addingTimeInterval(3_600))

        #expect(model.rangeStart == next)
        #expect(model.days.isEmpty)
        #expect(!model.hasLoaded)
        #expect(model.errorMessage != nil)
        #expect(!model.isLoading)
    }

    @Test("Date selection loads another range and Today restores the initial range")
    func selectsDatesAndReturnsToToday() async {
        let next = calendar.date(byAdding: .day, value: 7, to: today)!
        let currentMeal = entry(at: today)
        let nextMeal = entry(at: next)
        let repository = InMemoryMealRepository(entries: [currentMeal, nextMeal])
        let model = makeModel(repository)

        await model.showRange(starting: next.addingTimeInterval(12 * 3_600))
        #expect(model.rangeStart == next)
        #expect(model.days == [MealPlanDay(date: next, entries: [nextMeal])])
        #expect(model.lastDay == calendar.date(byAdding: .day, value: 6, to: next))

        await model.showToday()
        #expect(model.rangeStart == today)
        #expect(model.days == [MealPlanDay(date: today, entries: [currentMeal])])
    }

    @Test("Day grouping and range end respect Sydney daylight saving")
    func respectsCalendarDaysAcrossDaylightSaving() async throws {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = try #require(TimeZone(identifier: "Australia/Sydney"))
        let start = try #require(local.date(from: DateComponents(year: 2026, month: 10, day: 1)))
        let last = try #require(local.date(from: DateComponents(year: 2026, month: 10, day: 7)))
        let end = try #require(local.date(from: DateComponents(year: 2026, month: 10, day: 8)))
        let firstMeal = entry(at: start)
        let lastMeal = entry(at: end.addingTimeInterval(-1))
        let repository = InMemoryMealRepository(entries: [firstMeal, lastMeal, entry(at: end)])
        let fixedNow = start.addingTimeInterval(12 * 3_600)
        let model = MealPlanViewModel(repository: repository, calendar: local, now: { fixedNow })

        await model.load()

        #expect(model.rangeStart == start)
        #expect(model.lastDay == last)
        #expect(model.days == [MealPlanDay(date: start, entries: [firstMeal]),
                              MealPlanDay(date: last, entries: [lastMeal])])
    }

    private func makeModel(_ repository: InMemoryMealRepository) -> MealPlanViewModel {
        let fixedNow = today.addingTimeInterval(12 * 3_600)
        return MealPlanViewModel(repository: repository, calendar: calendar, now: { fixedNow })
    }

    private func entry(at date: Date, prepared: Bool = false) -> MealPlanEntry {
        MealPlanEntry(
            meal: Meal(name: "Rice bowl", ingredients: [MealIngredient(name: "Rice", quantity: 100, unit: "g")]),
            scheduledDate: date,
            mealType: .lunch,
            isPrepared: prepared
        )
    }
}
