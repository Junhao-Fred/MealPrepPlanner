import Foundation
import Testing
@testable import MealPrepPlanner

@MainActor
struct TodayViewModelTests {
    private let now = Date(timeIntervalSince1970: 1_704_110_400)

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    @Test("Today includes missed meals and finds the next unfinished meal")
    func overview() async throws {
        let start = calendar.startOfDay(for: now)
        let yesterday = makeEntry(at: start.addingTimeInterval(-1))
        let missed = makeEntry(at: start)
        let next = makeEntry(at: now)
        let tomorrow = makeEntry(at: start.addingTimeInterval(86_400))
        var prepared = makeEntry(at: now.addingTimeInterval(60))
        prepared.isPrepared = true
        let soon = Ingredient(name: "Milk", quantity: 500, unit: "ml", expiryDate: start)
        let expired = Ingredient(name: "Old milk", quantity: 100, unit: "ml", expiryDate: start.addingTimeInterval(-1))
        let repository = InMemoryMealRepository(
            entries: [tomorrow, prepared, missed, next, yesterday], ingredients: [expired, soon]
        )
        let model = makeModel(repository)
        await model.load()

        #expect(model.snapshot?.meals.map(\.id) == [missed.id, next.id])
        #expect(model.snapshot?.nextMeal?.id == next.id)
        #expect(model.snapshot?.expiringIngredients == [soon])
        #expect(model.errorMessage == nil)
        #expect(!model.isLoading)

        _ = try await MarkMealPreparedUseCase(repository: repository).execute(id: next.id)
        await model.load()
        #expect(model.snapshot?.meals.map(\.id) == [missed.id])
        #expect(model.snapshot?.nextMeal?.id == tomorrow.id)
    }

    @Test("An empty repository produces an empty overview")
    func emptyOverview() async {
        let model = makeModel(InMemoryMealRepository())
        await model.load()
        #expect(model.snapshot?.meals.isEmpty == true)
        #expect(model.snapshot?.nextMeal == nil)
        #expect(model.snapshot?.expiringIngredients.isEmpty == true)
        #expect(model.errorMessage == nil)
    }

    @Test("Load errors can be retried and refresh errors preserve existing data")
    func loadFailureAndRetry() async {
        let repository = InMemoryMealRepository(entries: [makeEntry(at: now)])
        let model = makeModel(repository)
        await repository.fail(.read, with: .readFailed)
        await model.load()
        #expect(model.snapshot == nil)
        #expect(model.errorMessage != nil)
        #expect(!model.isLoading)

        await repository.clearFailures()
        await model.load()
        #expect(model.errorMessage == nil)
        let previous = model.snapshot
        #expect(previous != nil)

        await repository.fail(.read, with: .readFailed)
        await model.load()
        #expect(model.snapshot == previous)
        #expect(model.errorMessage != nil)
        #expect(!model.isLoading)
    }

    @Test("Detail retries a failed save and ignores simultaneous completion taps")
    func detailCompletion() async throws {
        var entry = makeEntry(at: now)
        let repository = InMemoryMealRepository(entries: [entry])
        let model = MealDetailViewModel(id: entry.id, useCase: MarkMealPreparedUseCase(repository: repository))
        entry.meal.name = "Updated Oats"
        try await repository.updateMealPlanEntry(entry)
        await model.load()
        #expect(model.entry?.meal.name == "Updated Oats")

        await repository.fail(.write, with: .writeFailed)
        let failed = await model.markPrepared()
        #expect(!failed)
        #expect(model.entry?.isPrepared == false)
        #expect(model.errorMessage != nil)
        #expect(!model.isSaving)

        await repository.clearFailures()
        let writesBefore = await repository.writeCount
        async let first = model.markPrepared()
        async let second = model.markPrepared()
        let results = await [first, second]
        #expect(results.filter { $0 }.count == 1)
        #expect(model.entry?.isPrepared == true)
        #expect(model.errorMessage == nil)
        let writesAfter = await repository.writeCount
        #expect(writesAfter == writesBefore + 1)
    }

    private func makeModel(_ repository: any MealPlanningRepository) -> TodayViewModel {
        let date = now
        return TodayViewModel(useCase: LoadTodayOverviewUseCase(
            repository: repository, calendar: calendar, now: { date }
        ))
    }

    private func makeEntry(at date: Date) -> MealPlanEntry {
        MealPlanEntry(
            meal: Meal(name: "Oats", ingredients: [MealIngredient(name: "Oats", quantity: 80, unit: "g")]),
            scheduledDate: date,
            mealType: .breakfast
        )
    }
}
