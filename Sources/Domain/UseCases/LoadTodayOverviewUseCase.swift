import Foundation

enum TodayOverviewError: Error {
    case invalidDate
}

struct TodayOverview: Equatable, Sendable {
    let date: Date
    let meals: [MealPlanEntry]
    let nextMeal: MealPlanEntry?
    let expiringIngredients: [Ingredient]
}

struct LoadTodayOverviewUseCase: Sendable {
    let repository: any MealPlanningRepository
    var calendar: Calendar = .current
    var now: @Sendable () -> Date = { Date() }

    func execute() async throws -> TodayOverview {
        let date = now()
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
            throw TodayOverviewError.invalidDate
        }
        let meals = try await repository.fetchMealPlanEntries(
            from: start, to: end, includingPrepared: false
        )
        let upcoming = try await repository.fetchMealPlanEntries(
            from: date, to: .distantFuture, includingPrepared: false
        )
        let ingredients = try await FindIngredientsToUseSoonUseCase(
            repository: repository, calendar: calendar, now: { date }
        ).execute()
        return TodayOverview(date: date, meals: meals, nextMeal: upcoming.first, expiringIngredients: ingredients)
    }
}
