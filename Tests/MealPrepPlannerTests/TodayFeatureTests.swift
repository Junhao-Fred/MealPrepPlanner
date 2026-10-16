import Foundation
import Testing
@testable import MealPrepPlanner

@MainActor
struct TodayFeatureTests {
    private let now = Date(timeIntervalSince1970: 1_704_110_400)

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    @Test("Today keeps missed meals while next meal excludes completed and past plans")
    func todayAndNextMealHaveDifferentWindows() async throws {
        let start = calendar.startOfDay(for: now)
        let missed = makeEntry(at: start)
        let next = makeEntry(at: now)
        let tomorrow = makeEntry(at: start.addingTimeInterval(86_400))
        var prepared = makeEntry(at: now.addingTimeInterval(60))
        prepared.isPrepared = true
        let yesterday = makeEntry(at: start.addingTimeInterval(-1))
        let repository = MockMealPlanningRepository(entries: [tomorrow, prepared, next, yesterday, missed])
        let snapshot = try await makeUseCase(repository).execute()

        #expect(snapshot.meals.map(\.id) == [missed.id, next.id])
        #expect(snapshot.nextMeal?.id == next.id)
    }

    @Test("Next meal can be tomorrow when today has only a missed meal")
    func nextMealCanBeOutsideToday() async throws {
        let missed = makeEntry(at: now.addingTimeInterval(-1))
        let tomorrow = makeEntry(at: now.addingTimeInterval(86_400))
        let repository = MockMealPlanningRepository(entries: [tomorrow, missed])
        let snapshot = try await makeUseCase(repository).execute()

        #expect(snapshot.meals.map(\.id) == [missed.id])
        #expect(snapshot.nextMeal?.id == tomorrow.id)
    }

    @Test("Use soon includes today but excludes expired, depleted, undated and day-three stock")
    func expiryBoundaries() async throws {
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 3, to: start)!
        let today = Ingredient(name: "Milk", quantity: 1, unit: "ml", expiryDate: start)
        let last = Ingredient(name: "Tomato", quantity: 1, unit: "g", expiryDate: end.addingTimeInterval(-1))
        let repository = MockMealPlanningRepository(ingredients: [
            today, last,
            Ingredient(name: "Expired", quantity: 1, unit: "g", expiryDate: start.addingTimeInterval(-1)),
            Ingredient(name: "Later", quantity: 1, unit: "g", expiryDate: end),
            Ingredient(name: "Used", quantity: 0, unit: "g", expiryDate: start),
            Ingredient(name: "Undated", quantity: 1, unit: "g")
        ])
        let snapshot = try await makeUseCase(repository).execute()

        #expect(Set(snapshot.expiringIngredients.map(\.id)) == Set([today.id, last.id]))
    }

    @Test("Today recovers from a failed load and keeps its last snapshot on refresh failure")
    func loadFailureAndRetry() async {
        let repository = MockMealPlanningRepository()
        let model = TodayViewModel(useCase: makeUseCase(repository))
        await repository.setFailure(true)
        await model.load()
        #expect(model.errorMessage != nil)
        #expect(model.snapshot == nil)
        #expect(!model.isLoading)

        await repository.setFailure(false)
        await model.load()
        #expect(model.errorMessage == nil)
        #expect(model.snapshot?.meals.isEmpty == true)
        #expect(model.snapshot?.nextMeal == nil)

        await repository.setFailure(true)
        await model.load()
        #expect(model.errorMessage != nil)
        #expect(model.snapshot != nil)
        #expect(!model.isLoading)
    }

    @Test("Failed completion leaves the displayed and stored state unchanged and can be retried")
    func completionFailureAndRetry() async throws {
        let entry = makeEntry(at: now)
        let stock = Ingredient(name: "Oats", quantity: 500, unit: "g")
        let repository = MockMealPlanningRepository(entries: [entry], ingredients: [stock])
        let useCase = MealDetailsUseCase(repository: repository)
        let model = MealDetailViewModel(id: entry.id, useCase: useCase)
        await model.load()
        await repository.setWriteFailure(true)

        let failed = await model.markPrepared()
        #expect(!failed)
        #expect(model.entry?.isPrepared == false)
        #expect(model.errorMessage != nil)
        #expect(!model.isSaving)

        await repository.setWriteFailure(false)
        let unchanged = try await useCase.fetch(id: entry.id)
        #expect(!unchanged.isPrepared)
        let success = await model.markPrepared()
        #expect(success)
        #expect(model.entry?.isPrepared == true)
        #expect(model.errorMessage == nil)
        let snapshot = try await makeUseCase(repository).execute()
        #expect(snapshot.meals.isEmpty)
        #expect(snapshot.nextMeal == nil)
        let stockAfter = try await repository.fetchAvailableIngredients()
        #expect(stockAfter == [stock])
    }

    @Test("Concurrent completion taps perform one update")
    func duplicateCompletionIsIgnored() async {
        let entry = makeEntry(at: now)
        let repository = MockMealPlanningRepository(entries: [entry])
        let model = MealDetailViewModel(id: entry.id, useCase: MealDetailsUseCase(repository: repository))
        await model.load()

        async let first = model.markPrepared()
        async let second = model.markPrepared()
        let results = await [first, second]
        let count = await repository.updateCount
        #expect(results.filter { $0 }.count == 1)
        #expect(count == 1)
    }

    @Test("Details load the latest entry by ID and missing entries show a recoverable error")
    func detailLoadsByID() async throws {
        var entry = makeEntry(at: now)
        let repository = MockMealPlanningRepository(entries: [entry])
        let model = MealDetailViewModel(id: entry.id, useCase: MealDetailsUseCase(repository: repository))
        entry.meal.name = "Updated Oats"
        try await repository.updateMealPlanEntry(entry)
        await model.load()
        #expect(model.entry?.meal.name == "Updated Oats")

        let missing = MealDetailViewModel(id: UUID(), useCase: MealDetailsUseCase(repository: repository))
        await missing.load()
        #expect(missing.entry == nil)
        #expect(missing.errorMessage != nil)
        #expect(!missing.isLoading)
    }

    private func makeUseCase(_ repository: any MealPlanningRepository) -> TodayMealsUseCase {
        let date = now
        return TodayMealsUseCase(repository: repository, calendar: calendar, now: { date })
    }

    private func makeEntry(at date: Date) -> MealPlanEntry {
        MealPlanEntry(
            meal: Meal(name: "Oats", ingredients: [MealIngredient(name: "Oats", quantity: 80, unit: "g")]),
            scheduledDate: date,
            mealType: .breakfast
        )
    }
}
